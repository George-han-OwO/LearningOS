import 'dart:io';

import 'package:path/path.dart' as p;

import 'chatgpt_auth_service.dart';
import 'codex_app_server_client.dart';

const _configuredHistoryCwd = String.fromEnvironment(
  'AI_STUDY_OS_CODEX_SYNC_CWD',
);
const _configuredHistoryFolder = String.fromEnvironment(
  'AI_STUDY_OS_CODEX_SYNC_FOLDER',
  defaultValue: 'OSS',
);

class LocalCodexChatGptAuthService extends ChatGptAuthService {
  LocalCodexChatGptAuthService({
    this.executable = 'codex',
    this.arguments = const ['app-server'],
    this.historyCwd = _configuredHistoryCwd,
    this.historyFolderName = _configuredHistoryFolder,
  });

  final String executable;
  final List<String> arguments;
  final String historyCwd;
  final String historyFolderName;

  CodexAppServerClient? _client;
  Future<CodexAppServerClient>? _clientFuture;
  final Map<String, String> _knownThreadVersions = <String, String>{};
  final Set<String> _resolvedHistoryCwds = <String>{};
  bool _chatGptSubscriptionVerified = false;
  bool _disposed = false;

  @override
  bool get supported =>
      !Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia;

  @override
  Future<ChatGptAuthState> read() async {
    if (!supported) return const ChatGptAuthState.unavailable();
    try {
      final state = await _withClient(
        (client) => client.readAccount(refreshToken: true),
      );
      _chatGptSubscriptionVerified = state.account?.isChatGpt == true;
      return _mapAccountState(state);
    } catch (error) {
      return ChatGptAuthState.unavailable('Codex 不可用：$error');
    }
  }

  @override
  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false}) async {
    if (!supported) {
      throw StateError('当前平台没有可用的 Codex App Server。');
    }
    final login = await _withClient(
      (client) => deviceCode
          ? client.startChatGptDeviceCodeLogin()
          : client.startChatGptLogin(),
    );
    return ChatGptLoginChallenge(
      loginId: login.loginId,
      authUrl: login.authUrl,
      verificationUrl: login.verificationUrl,
      userCode: login.userCode,
    );
  }

  @override
  Future<ChatGptAuthState> completeLogin(
    ChatGptLoginChallenge challenge,
  ) async {
    final state = await _withClient(
      (client) => client.completeChatGptLogin(
        CodexChatGptLogin(
          loginId: challenge.loginId,
          authUrl: challenge.authUrl,
          verificationUrl: challenge.verificationUrl,
          userCode: challenge.userCode,
        ),
        timeout: const Duration(minutes: 5),
      ),
    );
    _chatGptSubscriptionVerified = state.account?.isChatGpt == true;
    return _mapAccountState(state);
  }

  @override
  Future<void> cancelLogin(String loginId) async {
    if (_client == null && _clientFuture == null) return;
    await _withClient((client) => client.cancelLogin(loginId));
  }

  @override
  Future<void> logout() async {
    if (!supported) return;
    try {
      await _withClient((client) => client.logout());
    } finally {
      _knownThreadVersions.clear();
      _resolvedHistoryCwds.clear();
      _chatGptSubscriptionVerified = false;
      await _discardClient();
    }
  }

  @override
  Future<ChatGptCodexQuotaState> readQuota() async {
    if (!supported) {
      return const ChatGptCodexQuotaState.unavailable('当前平台不支持 Codex 额度读取。');
    }
    await _ensureChatGptSubscription();
    final quota = await _withClient((client) => client.readRateLimits());
    return ChatGptCodexQuotaState(
      available: true,
      planType: quota.planType,
      primaryUsedPercent: quota.primary?.usedPercent,
      primaryWindowMinutes: quota.primary?.windowDurationMinutes,
      primaryResetsAt: quota.primary?.resetsAt,
      secondaryUsedPercent: quota.secondary?.usedPercent,
      secondaryWindowMinutes: quota.secondary?.windowDurationMinutes,
      secondaryResetsAt: quota.secondary?.resetsAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<String>> listModels() async {
    if (!supported) return const [];
    await _ensureChatGptSubscription();
    return _withClient((client) => client.listModels());
  }

  @override
  Future<CodexHistoryBatch> readCodexHistory({bool fullRefresh = false}) async {
    if (!supported) {
      throw StateError('当前平台不支持 Codex 会话读取。');
    }
    await _ensureChatGptSubscription();

    final matchingThreads = <CodexThreadSummary>[];
    final exactCwd = historyCwd.trim();
    final List<String?> cwdFilters = exactCwd.isNotEmpty
        ? <String>[exactCwd]
        : (!fullRefresh && _resolvedHistoryCwds.isNotEmpty)
        ? _resolvedHistoryCwds.toList(growable: false)
        : const <String?>[null];
    for (final cwdFilter in cwdFilters) {
      String? cursor;
      while (true) {
        final page = await _withClient(
          (client) => client.listThreads(cursor: cursor, cwd: cwdFilter),
        );
        matchingThreads.addAll(page.threads.where(_isConfiguredHistoryThread));
        final next = page.nextCursor;
        if (next == null || next == cursor) break;
        cursor = next;
      }
    }
    _resolvedHistoryCwds
      ..clear()
      ..addAll(
        matchingThreads.map((item) => item.cwd).where((cwd) => cwd.isNotEmpty),
      );

    final changed = <CodexConversationRecord>[];
    for (final thread in matchingThreads) {
      final version = thread.updatedAt.toIso8601String();
      if (!fullRefresh && _knownThreadVersions[thread.id] == version) continue;
      final conversation = await _withClient(
        (client) => client.readStoredConversation(thread),
      );
      _knownThreadVersions[thread.id] = version;
      if (conversation.transcript.trim().isEmpty) continue;
      changed.add(
        CodexConversationRecord(
          externalId: thread.id,
          title: thread.title,
          transcript: conversation.transcript,
          updatedAt: thread.updatedAt,
          isComplete: conversation.isComplete,
          cwd: thread.cwd,
        ),
      );
    }

    final activeIds = matchingThreads.map((item) => item.id).toSet();
    _knownThreadVersions.removeWhere((id, _) => !activeIds.contains(id));
    return CodexHistoryBatch(
      folderName: historyCwd.trim().isEmpty
          ? historyFolderName.trim()
          : historyCwd.trim(),
      totalThreads: matchingThreads.length,
      changedConversations: changed,
      checkedAt: DateTime.now(),
    );
  }

  bool _isConfiguredHistoryThread(CodexThreadSummary thread) {
    final exactCwd = historyCwd.trim();
    if (exactCwd.isNotEmpty) {
      return p.normalize(thread.cwd).toLowerCase() ==
          p.normalize(exactCwd).toLowerCase();
    }
    final folder = historyFolderName.trim().toLowerCase();
    if (folder.isEmpty) return true;
    return p.basename(p.normalize(thread.cwd)).toLowerCase() == folder;
  }

  Future<T> _withClient<T>(
    Future<T> Function(CodexAppServerClient client) operation,
  ) async {
    final client = await _ensureClient();
    try {
      return await operation(client);
    } catch (_) {
      await _discardClient(client);
      rethrow;
    }
  }

  Future<void> _ensureChatGptSubscription() async {
    if (_chatGptSubscriptionVerified) return;
    final account = await _withClient((client) => client.readAccount());
    if (account.account?.isChatGpt != true) {
      throw StateError('请先使用 ChatGPT 订阅账号登录 Codex。');
    }
    _chatGptSubscriptionVerified = true;
  }

  Future<CodexAppServerClient> _ensureClient() async {
    if (_disposed) throw StateError('ChatGPT Codex 服务已关闭。');
    final current = _client;
    if (current != null && current.isInitialized) return current;
    final pending = _clientFuture;
    if (pending != null) return pending;
    final future = _startClient();
    _clientFuture = future;
    try {
      final started = await future;
      _client = started;
      return started;
    } finally {
      if (identical(_clientFuture, future)) _clientFuture = null;
    }
  }

  Future<CodexAppServerClient> _startClient() async {
    final client = CodexAppServerClient(
      executable: executable,
      arguments: arguments,
    );
    try {
      await client.start(experimentalApi: true);
      return client;
    } catch (_) {
      await client.dispose();
      rethrow;
    }
  }

  Future<void> _discardClient([CodexAppServerClient? expected]) async {
    final client = _client;
    if (expected != null && client != null && !identical(expected, client)) {
      return;
    }
    _client = null;
    _chatGptSubscriptionVerified = false;
    await client?.dispose();
  }

  ChatGptAuthState _mapAccountState(CodexAccountState state) {
    final account = state.account;
    if (account == null) {
      return ChatGptAuthState.signedOut(
        message: state.requiresOpenaiAuth ? '请先完成 ChatGPT 登录。' : null,
      );
    }
    if (!account.isChatGpt) {
      return const ChatGptAuthState.signedOut(
        message: '检测到 Codex API Key 登录；请切换为 ChatGPT 登录以使用订阅额度。',
      );
    }
    return ChatGptAuthState(
      available: true,
      authenticated: true,
      accountId: account.accountId,
      email: account.email,
      displayName: account.displayName,
      planType: account.planType,
      message: null,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _knownThreadVersions.clear();
    _resolvedHistoryCwds.clear();
    final pending = _clientFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The failed starter already disposed its client.
      }
    }
    await _discardClient();
  }
}
