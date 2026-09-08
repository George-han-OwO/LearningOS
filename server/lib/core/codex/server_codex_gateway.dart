import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

import '../../data/app_database.dart';
import '../../domain/models.dart';
import '../../domain/word_parser.dart';
import '../ai/ai_service.dart';
import '../ai/codex_ai_service.dart';
import 'codex_app_server_client.dart';

/// A deliberately narrow HTTPS-facing bridge for a server-installed Codex
/// App Server. It never proxies JSON-RPC or exposes credentials to a phone.
class ServerCodexGateway {
  ServerCodexGateway(
    this._database, {
    this.executable = 'codex',
    this.arguments = const ['app-server', '--stdio'],
    this.maxPendingLogins = 3,
    this.loginQuietPeriod = const Duration(seconds: 5),
    DateTime Function()? clock,
    this.clientFactory,
  }) : _clock = clock ?? _utcNow;

  final AppDatabase _database;
  final String executable;
  final List<String> arguments;
  final int maxPendingLogins;
  final Duration loginQuietPeriod;
  final DateTime Function() _clock;
  final Future<CodexAppServerClient> Function(Directory)? clientFactory;
  Future<void>? _restoringAttempts;
  int _startsInFlight = 0;
  bool _disposed = false;
  final Map<String, _PendingDeviceLogin> _pending = {};
  final Map<int, Map<String, DateTime>> _historyVersions = {};
  final Map<int, CodexAppServerClient> _userClients = {};
  final Map<int, Future<CodexAppServerClient>> _startingUserClients = {};
  final Map<String, Future<void>> _loginStartTails = {};

  bool get enabled =>
      Platform.environment['AILO_CODEX_GATEWAY_ENABLED']?.trim() == '1';

  Future<Map<String, Object?>> startDeviceLogin({
    AppUser? owner,
    String? clientInstanceId,
  }) {
    _ensureEnabled();
    final requestScope = _loginRequestScope(owner, clientInstanceId);
    return _serializeLoginStart(
      requestScope,
      () => _startDeviceLogin(owner: owner, requestScope: requestScope),
    );
  }

  Future<Map<String, Object?>> _startDeviceLogin({
    required AppUser? owner,
    required String requestScope,
  }) async {
    await _restoreAttempts();
    await _removeExpiredPendingLogins();
    final now = _clock().toUtc();
    final quietUntil = await _database.codexLoginQuietUntil(requestScope);
    if (quietUntil != null && quietUntil.isAfter(now)) {
      await _beginLoginQuietPeriod(requestScope, now);
      throw CodexLoginQuietPeriodException(
        retryAfterSeconds: loginQuietPeriod.inSeconds,
        cancelledAttempts: 0,
      );
    }
    final recent = _pending.values
        .where(
          (pending) =>
              pending.requestScope == requestScope &&
              pending.status == 'pending',
        )
        .toList(growable: false);
    if (recent.isNotEmpty) {
      var cancelled = 0;
      for (final pending in recent) {
        await _cancelPendingLogin(
          pending,
          message:
              '检测到频繁登录，此次登录已被服务器自动取消。'
              '请停止操作 ${loginQuietPeriod.inSeconds} 秒后重试。',
        );
        cancelled++;
      }
      await _beginLoginQuietPeriod(requestScope, now);
      throw CodexLoginQuietPeriodException(
        retryAfterSeconds: loginQuietPeriod.inSeconds,
        cancelledAttempts: cancelled,
      );
    }
    if (quietUntil != null) {
      await _database.clearCodexLoginQuietPeriod(requestScope);
    }
    if (_pending.values.where((p) => p.status == 'pending').length +
            _startsInFlight >=
        maxPendingLogins) {
      throw StateError('当前等待完成的 ChatGPT 登录过多，请稍后再试。');
    }
    _startsInFlight++;
    CodexAppServerClient? client;
    try {
      final homeId = _randomOpaqueId();
      final home = await _homeDirectory(homeId);
      client = await _startClient(home);
      final login = await client.startChatGptDeviceCodeLogin();
      final attemptId = _randomOpaqueId();
      final secret = _randomOpaqueId();
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 15));
      final pending = _PendingDeviceLogin(
        attemptId: attemptId,
        secretHash: _hashSecret(secret),
        homeId: homeId,
        client: client,
        loginId: login.loginId,
        ownerUserId: owner?.id,
        requestScope: requestScope,
        expiresAt: expiresAt,
      );
      await _database.saveCodexLoginAttempt({
        'attempt_id': attemptId,
        'secret_hash': pending.secretHash,
        'home_id': homeId,
        'login_id': login.loginId,
        'owner_user_id': owner?.id,
        'request_scope': requestScope,
        'expires_at': expiresAt.toIso8601String(),
      });
      _pending[attemptId] = pending;
      _listenForLogin(pending, client);
      // account/read is the authority. Notifications only accelerate polling.
      unawaited(_reconcileLogin(pending));
      return {
        'attempt_id': attemptId,
        // This is an opaque one-time attempt capability, not a ChatGPT token.
        'attempt_secret': secret,
        'login_id': login.loginId,
        if (login.verificationUrl != null)
          'verification_url': login.verificationUrl.toString(),
        if (login.userCode != null) 'user_code': login.userCode,
        'expires_at': expiresAt.toIso8601String(),
      };
    } catch (_) {
      await client?.dispose();
      rethrow;
    } finally {
      _startsInFlight--;
    }
  }

  /// Returns null while App Server is still waiting for the user. Mobile
  /// clients call this as a short HTTPS status poll, avoiding a fragile
  /// 15-minute reverse-proxy request while App Server itself keeps listening
  /// for `account/login/completed`.
  Future<ServerCodexLoginResult?> completeDeviceLogin({
    required String attemptId,
    required String attemptSecret,
    AppUser? requester,
  }) async {
    _ensureEnabled();
    await _restoreAttempts();
    final pending = _readPending(attemptId, attemptSecret, requester);
    if (pending.status == 'pending') {
      unawaited(_reconcileLogin(pending));
      return null;
    }
    if (pending.status != 'completed') {
      throw StateError(pending.errorMessage ?? '登录请求已结束，请重试。');
    }
    // Retain the result until expiry: a lost HTTP response must not consume
    // the login or create a different LearningOS account on retry.
    final boundHome = await _database.codexHomeIdForUser(pending.targetUserId!);
    if (boundHome != pending.homeId) throw StateError('此登录已被退出或新的连接替代。');
    try {
      return await (pending.result ??= _loginResult(pending));
    } catch (_) {
      pending.result = null;
      rethrow;
    }
  }

  Future<void> cancelDeviceLogin({
    required String attemptId,
    required String attemptSecret,
    AppUser? requester,
  }) async {
    await _restoreAttempts();
    final pending = _readPending(attemptId, attemptSecret, requester);
    if (pending.status != 'pending') return;
    await _cancelPendingLogin(pending);
  }

  Future<void> _cancelPendingLogin(
    _PendingDeviceLogin pending, {
    String? message,
  }) async {
    if (pending.status != 'pending') return;
    // A late cancel from an old phone must never close an adopted session.
    pending.status = 'cancelled';
    pending.errorMessage = message;
    await _database.endCodexLoginAttempt(
      pending.attemptId,
      'cancelled',
      message: message,
    );
    try {
      await pending.client?.cancelLogin(pending.loginId);
    } catch (_) {
      // Cancellation is best effort. Closing the isolated App Server below is
      // authoritative and prevents a stale completion from being adopted.
    } finally {
      await pending.stopListening();
      await pending.client?.dispose();
    }
  }

  Future<void> _beginLoginQuietPeriod(String requestScope, DateTime now) =>
      _database.setCodexLoginQuietUntil(
        requestScope,
        now.toUtc().add(loginQuietPeriod),
      );

  Future<T> _serializeLoginStart<T>(
    String requestScope,
    Future<T> Function() operation,
  ) {
    final previous = _loginStartTails[requestScope] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _loginStartTails[requestScope] = tail;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
        if (identical(_loginStartTails[requestScope], tail)) {
          _loginStartTails.remove(requestScope);
        }
      }
    }();
  }

  Future<ServerCodexLoginResult> _loginResult(
    _PendingDeviceLogin pending,
  ) async {
    final user = await _database.userForId(pending.targetUserId!);
    if (user == null) throw StateError('LearningOS 账号不存在。');
    return ServerCodexLoginResult(
      auth: pending.accountMetadata!,
      user: user,
      session: await _database.createAuthSession(user.id),
    );
  }

  Future<void> _restoreAttempts() => _restoringAttempts ??= () async {
    for (final row in await _database.activeCodexLoginAttempts()) {
      final pending = _PendingDeviceLogin.fromRow(row);
      _pending.putIfAbsent(pending.attemptId, () => pending);
    }
  }();

  void _listenForLogin(
    _PendingDeviceLogin pending,
    CodexAppServerClient client,
  ) {
    pending.notification = client.loginCompletions.listen((event) {
      if (event.loginId != pending.loginId) return;
      if (!event.success) pending.loginRejected = true;
      unawaited(_reconcileLogin(pending));
    });
  }

  /// Called by the server's two-second worker, including after restart.
  /// Never reads auth.json: Codex itself verifies its persisted login state.
  Future<void> reconcilePendingLogins() async {
    if (!enabled || _disposed) return;
    await _restoreAttempts();
    await _removeExpiredPendingLogins();
    await Future.wait([
      for (final pending in _pending.values.toList())
        if (pending.status == 'pending') _reconcileLogin(pending),
    ]);
  }

  Future<void> _reconcileLogin(_PendingDeviceLogin pending) =>
      pending.reconciliation ??= _checkLogin(pending).whenComplete(() {
        pending.reconciliation = null;
      });

  Future<void> _checkLogin(_PendingDeviceLogin pending) async {
    if (_disposed || pending.checking || pending.status != 'pending') return;
    pending.checking = true;
    var phase = 'start_client';
    try {
      var client = pending.client;
      if (client == null || !client.isInitialized) {
        await pending.stopListening();
        await client?.dispose();
        client = await _startClient(await _homeDirectory(pending.homeId));
        pending.client = client;
        _listenForLogin(pending, client);
      }
      phase = 'account_read';
      final state = await client.readAccount();
      if (_disposed || pending.status != 'pending') return;
      if (!pending.expiresAt.isAfter(DateTime.now().toUtc())) return;
      if (state.account?.isChatGpt != true) {
        pending.failures = 0;
        if (pending.loginRejected) {
          await _failLogin(pending, 'ChatGPT 授权未完成或已被取消，请重新登录。');
        }
        return;
      }
      phase = 'bind_account';
      final account = state.account!;
      AppUser? user;
      if (pending.ownerUserId != null) {
        user = await _database.userForId(pending.ownerUserId!);
      } else {
        final subject = account.accountId?.trim();
        if (subject == null || subject.isEmpty) {
          await _failLogin(
            pending,
            'ChatGPT 已授权，但未返回独立登录所需的账号标识。请先登录或注册 LearningOS，再在设置中连接 ChatGPT。',
          );
          return;
        }
        user =
            await _database.userForExternalAccount(
              provider: 'chatgpt',
              subject: subject,
            ) ??
            await _database.createExternalUser(
              provider: 'chatgpt',
              subject: subject,
              email: account.email ?? '',
              displayName: account.displayName ?? _displayName(account.email),
            );
      }
      if (user == null) throw StateError('LearningOS 账号不存在。');
      if (_disposed || pending.status != 'pending') return;
      final metadata = _safeAuthState(state);
      await _database.finishCodexLoginAttempt(
        attemptId: pending.attemptId,
        userId: user.id,
        homeId: pending.homeId,
        accountMetadata: metadata,
      );
      pending.status = 'completed';
      pending.targetUserId = user.id;
      pending.accountMetadata = metadata;
      await pending.stopListening();
      await _adoptUserClient(user.id, client);
      // Connecting credentials is not selecting a provider. Preserve the
      // existing DeepSeek key, selected provider, Canvas, notes and words.
      print(
        'Codex login: account verified and bound to LearningOS user ${user.id}.',
      );
    } catch (_) {
      if (_disposed || pending.status != 'pending') return;
      pending.failures++;
      print('Codex login: $phase retry ${pending.failures}.');
      if (pending.failures >= 3) {
        await _failLogin(pending, '后端无法确认 ChatGPT 登录状态。请检查 Codex 进程与服务器网络后重试。');
      }
    } finally {
      pending.checking = false;
      if (pending.status == 'cancelled' ||
          pending.status == 'expired' ||
          _disposed) {
        await pending.stopListening();
        await pending.client?.dispose();
      }
    }
  }

  Future<void> _failLogin(_PendingDeviceLogin pending, String message) async {
    pending.status = 'failed';
    pending.errorMessage = message;
    await _database.endCodexLoginAttempt(
      pending.attemptId,
      'failed',
      message: message,
    );
    await pending.stopListening();
    await pending.client?.dispose();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final pending in _pending.values) {
      await pending.stopListening();
      await pending.client?.dispose();
    }
    for (final client in _userClients.values) {
      await client.dispose();
    }
  }

  Future<Map<String, Object?>> readAccount(AppUser user) async {
    if (!enabled) return _unavailable('服务器未启用 Codex 网关。');
    final home = await _existingHomeDirectory(user.id);
    if (home == null) return _signedOut();
    try {
      return await _withUserClient(
        user,
        (client) async =>
            _safeAuthState(await client.readAccount(refreshToken: true)),
      );
    } on Object catch (error) {
      return _unavailable('Codex 网关不可用：$error');
    }
  }

  Future<List<String>> listModels(AppUser user) async {
    return _withUserClient(user, (client) => client.listModels());
  }

  Future<Map<String, Object?>> readQuota(AppUser user) async {
    return _withUserClient(user, (client) async {
      final quota = await client.readRateLimits();
      return {
        'available': true,
        'plan_type': quota.planType,
        ..._quotaWindow('primary', quota.primary),
        ..._quotaWindow('secondary', quota.secondary),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    });
  }

  /// Marks DeepSeek as the temporary route until Codex's primary (normally
  /// five-hour) usage window resets. The exact server-provided reset instant
  /// is preferred over calculating five hours on the phone.
  Future<DateTime> scheduleReturnAfterQuotaReset(AppUser user) async {
    var resumeAt = DateTime.now().toUtc().add(const Duration(hours: 5));
    try {
      final quota = await _withUserClient(
        user,
        (client) => client.readRateLimits(),
      );
      final advertised = quota.primary?.resetsAt;
      if (advertised != null && advertised.isAfter(DateTime.now().toUtc())) {
        resumeAt = advertised.toUtc();
      }
    } catch (_) {
      // A quota error may have closed the process. The conservative five-hour
      // retry still keeps requests on DeepSeek until Codex can be checked.
    }
    await _database.scheduleCodexReturn(user.id, resumeAt);
    return resumeAt;
  }

  /// Runs on the backend even while the mobile app is closed. A due account
  /// returns to Codex only after App Server confirms non-zero primary quota.
  Future<int> restoreDueCodexProviders() async {
    if (!enabled) return 0;
    var restored = 0;
    final now = DateTime.now().toUtc();
    for (final userId in await _database.userIdsDueForCodexReturn(now)) {
      final user = await _database.userForId(userId);
      if (user == null) continue;
      try {
        final quota = await _withUserClient(
          user,
          (client) => client.readRateLimits(),
        );
        final primary = quota.primary;
        final remaining = primary == null
            ? null
            : (100 - primary.usedPercent).clamp(0, 100);
        if (remaining != null && remaining > 0) {
          await _database.restoreCodexProvider(userId);
          restored++;
          continue;
        }
        await _database.scheduleCodexReturn(
          userId,
          primary?.resetsAt?.toUtc() ?? now.add(const Duration(minutes: 1)),
        );
      } catch (_) {
        await _database.scheduleCodexReturn(
          userId,
          now.add(const Duration(minutes: 1)),
        );
      }
    }
    return restored;
  }

  static bool isQuotaFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('quota') ||
        text.contains('rate limit') ||
        text.contains('usage limit') ||
        text.contains('额度') ||
        text.contains('429');
  }

  Future<Map<String, Object?>> readHistory(
    AppUser user, {
    required bool fullRefresh,
  }) async {
    return _withUserClient(user, (client) async {
      if (fullRefresh) _historyVersions.remove(user.id);
      final known = _historyVersions.putIfAbsent(user.id, () => {});
      final listedThreads = <CodexThreadSummary>[];
      String? cursor;
      while (listedThreads.length < 200) {
        final page = await client.listThreads(cursor: cursor, limit: 100);
        listedThreads.addAll(page.threads);
        if (page.nextCursor == null || page.nextCursor == cursor) break;
        cursor = page.nextCursor;
      }
      final threads = listedThreads
          .where((thread) => _workspaceName(thread.cwd) == 'oss')
          .toList(growable: false);
      final changed = <Map<String, Object?>>[];
      for (final thread in threads) {
        final previous = known[thread.id];
        known[thread.id] = thread.updatedAt;
        if (!fullRefresh &&
            previous != null &&
            !thread.updatedAt.isAfter(previous)) {
          continue;
        }
        final conversation = await client.readStoredConversation(thread);
        if (conversation.transcript.isEmpty) continue;
        changed.add({
          'external_id': thread.id,
          'title': thread.title,
          'transcript': conversation.transcript,
          'updated_at': thread.updatedAt.toIso8601String(),
          'is_complete': conversation.isComplete,
          'cwd': thread.cwd,
        });
      }
      return {
        'folder_name': 'OSS',
        'total_threads': threads.length,
        'changed_conversations': changed,
        'checked_at': DateTime.now().toUtc().toIso8601String(),
      };
    });
  }

  Future<AiConnectionProbe> testAiConnection(
    AppUser user,
    AiConnectionSettings settings,
  ) async {
    return _withUserClient(
      user,
      (client) =>
          const CodexAiService().testConnectionWithClient(client, settings),
    );
  }

  Future<AiEnrichmentReport> enrichWords(
    AppUser user,
    AiConnectionSettings settings,
    List<ParsedWord> words,
  ) async {
    return _withUserClient(
      user,
      (client) => const CodexAiService().enrichWordsWithClient(
        client,
        settings: settings,
        words: words,
      ),
    );
  }

  Future<String> completeText(
    AppUser user, {
    required AiConnectionSettings settings,
    required String prompt,
  }) async {
    return _withUserClient(user, (client) async {
      final account = await client.readAccount(refreshToken: true);
      if (!account.authenticated) {
        throw StateError('请先完成 ChatGPT / Codex 登录。');
      }
      final models = await client.listModels();
      final model = AiConnectionSettings.selectCodexModel(
        models,
        requested: settings.codexModel,
      );
      if (model == null) {
        throw StateError('Codex App Server 没有返回任何可用模型；请重新登录并刷新模型列表。');
      }
      final thread = await client.startThread(model: model);
      final turn = await client.runTurn(
        threadId: thread.id,
        prompt: prompt,
        model: model,
      );
      if (turn.error?.trim().isNotEmpty == true) throw StateError(turn.error!);
      return turn.outputText;
    });
  }

  Future<void> logout(AppUser user) async {
    final home = await _existingHomeDirectory(user.id);
    if (home == null) return;
    final client = _userClients.remove(user.id);
    _startingUserClients.remove(user.id);
    if (client != null) {
      try {
        await client.logout();
      } finally {
        await client.dispose();
      }
    } else {
      await _withClient<void>(home, (temporary) => temporary.logout());
    }
    await _database.clearCodexHomeForUser(user.id);
    _historyVersions.remove(user.id);
  }

  /// Server-owned near-realtime ingestion. Only user and assistant messages
  /// returned by [readHistory] are persisted; reasoning and tool output were
  /// already removed by the App Server client parser.
  Future<int> syncAllHistories() async {
    if (!enabled) return 0;
    var persisted = 0;
    for (final userId in await _database.userIdsWithCodexHomes()) {
      final user = await _database.userForId(userId);
      if (user == null) continue;
      try {
        final batch = await readHistory(user, fullRefresh: false);
        final rawItems = batch['changed_conversations'];
        if (rawItems is! List || rawItems.isEmpty) continue;
        final snapshots = <ChatGptConversationSnapshot>[];
        for (final raw in rawItems) {
          if (raw is! Map) continue;
          final item = Map<String, Object?>.from(raw);
          final snapshot = ChatGptConversationSnapshot.fromMap(item);
          snapshots.add(snapshot);
          await _database.saveObsidianEntry(
            userId: user.id,
            title: snapshot.title,
            contentEnglish: snapshot.transcript,
            contentChinese: '',
            source: 'Codex OSS 自动同步',
            category: 'Codex Raw',
            tags: const ['codex', 'oss', 'conversation'],
            sourceId: snapshot.externalId,
            updatedAt: snapshot.updatedAt,
          );
        }
        persisted += await _database.ingestConversationInbox(
          userId: user.id,
          conversations: snapshots,
        );
      } catch (error) {
        // One expired account must not stop other users from syncing.
        print('Codex OSS sync for user $userId will retry: $error');
      }
    }
    return persisted;
  }

  Future<T> _withUserClient<T>(
    AppUser user,
    Future<T> Function(CodexAppServerClient client) operation,
  ) async {
    final client = await _ensureUserClient(user);
    try {
      return await operation(client);
    } catch (_) {
      if (identical(_userClients[user.id], client)) {
        _userClients.remove(user.id);
      }
      await client.dispose();
      rethrow;
    }
  }

  Future<CodexAppServerClient> _ensureUserClient(AppUser user) async {
    _ensureEnabled();
    final current = _userClients[user.id];
    if (current != null && current.isInitialized) return current;
    final starting = _startingUserClients[user.id];
    if (starting != null) return starting;
    final future = _requireExistingHome(user.id).then(_startClient);
    _startingUserClients[user.id] = future;
    try {
      final client = await future;
      _userClients[user.id] = client;
      return client;
    } finally {
      if (identical(_startingUserClients[user.id], future)) {
        _startingUserClients.remove(user.id);
      }
    }
  }

  Future<void> _adoptUserClient(int userId, CodexAppServerClient client) async {
    final previous = _userClients[userId];
    _userClients[userId] = client;
    _startingUserClients.remove(userId);
    if (previous != null && !identical(previous, client)) {
      await previous.dispose();
    }
  }

  Future<T> _withClient<T>(
    Directory home,
    Future<T> Function(CodexAppServerClient client) operation,
  ) async {
    _ensureEnabled();
    CodexAppServerClient? client;
    try {
      client = await _startClient(home);
      return await operation(client);
    } finally {
      await client?.dispose();
    }
  }

  Future<CodexAppServerClient> _startClient(Directory home) async {
    await home.create(recursive: true);
    final factory = clientFactory;
    if (factory != null) return factory(home);
    final client = CodexAppServerClient(
      executable: executable,
      arguments: arguments,
      environment: {'CODEX_HOME': home.path},
      requestTimeout: const Duration(seconds: 10),
      runInShell:
          Platform.isWindows && !executable.toLowerCase().endsWith('.exe'),
    );
    // thread/turns/list is an experimental App Server method. The server-side
    // history worker needs this capability even though login/model/quota do
    // not, so every account process performs the same explicit handshake.
    try {
      await client.start(experimentalApi: true);
      return client;
    } catch (_) {
      await client.dispose();
      rethrow;
    }
  }

  Future<Directory> _homeDirectory(String homeId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{24,160}$').hasMatch(homeId)) {
      throw StateError('无效的服务器 Codex 目录标识。');
    }
    final directory = Directory(
      path.join(_database.dataDirectory.path, 'codex-users', homeId),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory?> _existingHomeDirectory(int userId) async {
    final homeId = await _database.codexHomeIdForUser(userId);
    return homeId == null ? null : _homeDirectory(homeId);
  }

  Future<Directory> _requireExistingHome(int userId) async {
    final home = await _existingHomeDirectory(userId);
    if (home == null) throw StateError('请先完成 ChatGPT / Codex 登录。');
    return home;
  }

  _PendingDeviceLogin _readPending(
    String id,
    String secret,
    AppUser? requester,
  ) {
    final pending = _pending[id.trim()];
    if (pending == null || pending.secretHash != _hashSecret(secret.trim())) {
      throw StateError('登录请求不存在、已取消或已过期。');
    }
    if (pending.ownerUserId != null && pending.ownerUserId != requester?.id) {
      throw StateError('请使用发起连接的 LearningOS 账号完成登录。');
    }
    if (!pending.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw StateError('设备码已过期，请重新发起 ChatGPT 登录。');
    }
    return pending;
  }

  Future<void> _removeExpiredPendingLogins() async {
    final now = DateTime.now().toUtc();
    final expired = _pending.values
        .where((item) => !item.expiresAt.isAfter(now))
        .toList(growable: false);
    for (final item in expired) {
      _pending.remove(item.attemptId);
      await item.stopListening();
      if (item.status == 'pending') {
        item.status = 'expired';
        await _database.endCodexLoginAttempt(item.attemptId, 'expired');
        await item.client?.dispose();
      }
    }
  }

  void _ensureEnabled() {
    if (_disposed) throw StateError('Codex 网关已关闭。');
    if (!enabled) {
      throw StateError('服务器未启用 Codex 网关（AILO_CODEX_GATEWAY_ENABLED=1）。');
    }
  }

  static Map<String, Object?> _safeAuthState(CodexAccountState state) {
    final account = state.account;
    if (account == null || !account.isChatGpt) return _signedOut();
    return {
      'available': true,
      'authenticated': true,
      'account_id': account.accountId,
      'email': account.email,
      'display_name': account.displayName,
      'plan_type': account.planType,
    };
  }

  static Map<String, Object?> _signedOut() => {
    'available': true,
    'authenticated': false,
  };

  static Map<String, Object?> _unavailable(String message) => {
    'available': false,
    'authenticated': false,
    'message': message,
  };

  static Map<String, Object?> _quotaWindow(
    String prefix,
    CodexRateLimitWindow? window,
  ) => {
    '${prefix}_used_percent': window?.usedPercent,
    '${prefix}_window_minutes': window?.windowDurationMinutes,
    '${prefix}_resets_at': window?.resetsAt?.toIso8601String(),
  };

  static String _randomOpaqueId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(36, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _hashSecret(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _loginRequestScope(AppUser? owner, String? clientInstanceId) {
    if (owner != null) return 'user:${owner.id}';
    final clientId = clientInstanceId?.trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{32,160}$').hasMatch(clientId)) {
      throw ArgumentError('请先更新 AILearningOS 客户端，再发起 ChatGPT-Codex 登录。');
    }
    // Persist only a one-way digest. The random installation identifier is
    // not an account credential and never appears in server logs.
    return 'client:${_hashSecret(clientId)}';
  }

  static String _displayName(String? email) {
    final local = email?.split('@').first.trim();
    return local == null || local.isEmpty ? 'ChatGPT 用户' : local;
  }

  static String _workspaceName(String cwd) {
    final normalized = cwd.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '';
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? '' : segments.last.toLowerCase();
  }
}

class CodexHistorySyncWorker {
  CodexHistorySyncWorker(
    this.gateway, {
    this.interval = const Duration(seconds: 2),
  });

  final ServerCodexGateway gateway;
  final Duration interval;
  Timer? _timer;
  bool _running = false;

  void start() {
    if (_timer != null || !gateway.enabled) return;
    _timer = Timer.periodic(interval, (_) => unawaited(runNow()));
    unawaited(runNow());
  }

  Future<void> runNow() async {
    if (gateway.enabled) {
      unawaited(
        gateway.reconcilePendingLogins().catchError((Object _) {
          print('Codex login: reconciliation will retry.');
        }),
      );
    }
    if (_running || !gateway.enabled) return;
    _running = true;
    try {
      final restored = await gateway.restoreDueCodexProviders();
      if (restored > 0) {
        print(
          'Codex quota restored for $restored user(s); route switched back.',
        );
      }
      final count = await gateway.syncAllHistories();
      if (count > 0) print('Codex OSS sync persisted $count conversation(s).');
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

class ServerCodexLoginResult {
  const ServerCodexLoginResult({
    required this.auth,
    required this.user,
    required this.session,
  });

  final Map<String, Object?> auth;
  final AppUser user;
  final AuthSession session;
}

class CodexLoginQuietPeriodException implements Exception {
  const CodexLoginQuietPeriodException({
    required this.retryAfterSeconds,
    required this.cancelledAttempts,
  });

  final int retryAfterSeconds;
  final int cancelledAttempts;

  @override
  String toString() =>
      'Codex 登录请求过于频繁，已取消近期未完成的登录。请停止操作 '
      '$retryAfterSeconds 秒后再创建新的登录。';
}

class _PendingDeviceLogin {
  _PendingDeviceLogin({
    required this.attemptId,
    required this.secretHash,
    required this.homeId,
    this.client,
    required this.loginId,
    this.ownerUserId,
    required this.requestScope,
    required this.expiresAt,
  });

  final String attemptId;
  final String secretHash;
  final String homeId;
  CodexAppServerClient? client;
  final String loginId;
  final int? ownerUserId;
  final String requestScope;
  final DateTime expiresAt;
  String status = 'pending';
  bool checking = false;
  Future<void>? reconciliation;
  bool loginRejected = false;
  int failures = 0;
  int? targetUserId;
  String? errorMessage;
  Map<String, Object?>? accountMetadata;
  Future<ServerCodexLoginResult>? result;
  StreamSubscription<CodexLoginCompleted>? notification;

  factory _PendingDeviceLogin.fromRow(Map<String, Object?> row) {
    final value = _PendingDeviceLogin(
      attemptId: row['attempt_id'] as String,
      secretHash: row['secret_hash'] as String,
      homeId: row['home_id'] as String,
      loginId: row['login_id'] as String,
      ownerUserId: row['owner_user_id'] as int?,
      requestScope:
          row['request_scope']?.toString() ?? 'legacy:${row['attempt_id']}',
      expiresAt: DateTime.parse(row['expires_at'] as String),
    );
    value.status = row['status'] as String;
    value.targetUserId = row['target_user_id'] as int?;
    value.errorMessage = row['error_message'] as String?;
    if (row['account_metadata'] != null) {
      value.accountMetadata = Map<String, Object?>.from(
        jsonDecode(row['account_metadata'] as String) as Map,
      );
    }
    return value;
  }

  Future<void> stopListening() async {
    await notification?.cancel();
    notification = null;
  }
}
