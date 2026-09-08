// The injected transport intentionally initializes private lifecycle state;
// the null-aware map syntax is kept explicit for protocol readability.
// ignore_for_file: prefer_initializing_formals, use_null_aware_elements

import 'dart:async';
import 'dart:convert';
import 'dart:io';

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _stringValue(json[key]);
    if (value != null) return value;
  }
  return null;
}

String? _errorMessage(Object? value) {
  if (value == null) return null;
  if (value is String) return _stringValue(value);
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    return _stringValue(map['message']) ?? _stringValue(map['error']);
  }
  return null;
}

double? _numberValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _dateTimeValue(Object? value) {
  if (value is num) {
    final raw = value.toInt();
    final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}

String? _sourceLabel(Object? value) {
  if (value is String) return _stringValue(value);
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    return _firstString(map, const ['type', 'kind', 'name']);
  }
  return null;
}

String? _messageText(Object? value) {
  if (value is String) return _stringValue(value);
  if (value is List) {
    final pieces = <String>[];
    for (final item in value) {
      if (item is String) {
        final text = _stringValue(item);
        if (text != null) pieces.add(text);
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final type = _stringValue(map['type']);
        if (type == null || type == 'text' || type == 'inputText') {
          final text = _stringValue(map['text']);
          if (text != null) pieces.add(text);
        }
      }
    }
    return pieces.isEmpty ? null : pieces.join('\n');
  }
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    return _stringValue(map['text']);
  }
  return null;
}

class CodexThread {
  const CodexThread({required this.id});

  final String id;
}

class CodexTurnResult {
  const CodexTurnResult({
    required this.turnId,
    required this.status,
    required this.outputText,
    this.error,
  });

  final String turnId;
  final String status;
  final String outputText;
  final String? error;
}

class _ActiveTurnCapture {
  _ActiveTurnCapture(this.turnId);

  final String turnId;
  final StringBuffer buffer = StringBuffer();
  final Completer<CodexTurnResult> completer = Completer<CodexTurnResult>();

  bool get hasText => buffer.isNotEmpty;

  void append(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return;
    buffer.write(text);
  }
}

/// A protocol-level failure returned by Codex App Server or the local
/// transport.
///
/// The client intentionally keeps only the JSON-RPC error code and message.
/// It never stores or prints the raw JSON payload, which could contain
/// provider-sensitive data in a future protocol version.
class CodexAppServerException implements Exception {
  const CodexAppServerException(this.message, {this.method, this.code});

  final String message;
  final String? method;
  final int? code;

  @override
  String toString() {
    final prefix = method == null ? 'Codex App Server' : 'Codex $method';
    final suffix = code == null ? '' : ' (code $code)';
    return '$prefix$suffix: $message';
  }
}

/// The account metadata returned by `account/read`.
///
/// Managed ChatGPT credentials remain inside the Codex process. This model
/// deliberately contains no access token, refresh token, cookie, or raw
/// protocol payload.
class CodexAccount {
  const CodexAccount({
    required this.type,
    this.accountId,
    this.email,
    this.displayName,
    this.planType,
    this.credentialSource,
  });

  factory CodexAccount.fromJson(Map<String, dynamic> json) {
    return CodexAccount(
      type: _stringValue(json['type']) ?? 'unknown',
      accountId: _firstString(json, const ['accountId', 'id', 'subject']),
      email: _stringValue(json['email']),
      displayName: _firstString(json, const ['displayName', 'name']),
      planType: _stringValue(json['planType']),
      credentialSource: _stringValue(json['credentialSource']),
    );
  }

  final String type;
  final String? accountId;
  final String? email;
  final String? displayName;
  final String? planType;
  final String? credentialSource;

  /// `chatgpt` is the managed subscription mode documented by Codex.
  bool get isChatGpt => type == 'chatgpt';

  Map<String, Object?> toSafeMap() => {
    'type': type,
    if (accountId != null) 'accountId': accountId,
    if (email != null) 'email': email,
    if (displayName != null) 'displayName': displayName,
    if (planType != null) 'planType': planType,
    if (credentialSource != null) 'credentialSource': credentialSource,
  };
}

/// The safe result of `account/read`.
class CodexAccountState {
  const CodexAccountState({
    required this.account,
    required this.requiresOpenaiAuth,
  });

  factory CodexAccountState.fromJson(Map<String, dynamic> json) {
    final accountJson = json['account'];
    return CodexAccountState(
      account: accountJson is Map
          ? CodexAccount.fromJson(Map<String, dynamic>.from(accountJson))
          : null,
      requiresOpenaiAuth: json['requiresOpenaiAuth'] == true,
    );
  }

  final CodexAccount? account;
  final bool requiresOpenaiAuth;

  bool get authenticated => account != null;
  String? get authMode => account?.type;
}

/// Browser or device-code challenge returned by `account/login/start`.
///
/// The challenge is short-lived UI data. It is not an OAuth credential and is
/// not persisted by this client.
class CodexChatGptLogin {
  const CodexChatGptLogin({
    required this.loginId,
    this.authUrl,
    this.verificationUrl,
    this.userCode,
  });

  final String loginId;
  final Uri? authUrl;
  final Uri? verificationUrl;
  final String? userCode;

  bool get isBrowserFlow => authUrl != null;
  bool get isDeviceCodeFlow => verificationUrl != null && userCode != null;
}

/// Safe representation of `account/login/completed`.
class CodexLoginCompleted {
  const CodexLoginCompleted({
    required this.loginId,
    required this.success,
    this.error,
  });

  factory CodexLoginCompleted.fromJson(Map<String, dynamic> json) {
    return CodexLoginCompleted(
      loginId: _stringValue(json['loginId']),
      success: json['success'] == true,
      error: _errorMessage(json['error']),
    );
  }

  /// API-key logins use a null login id; managed ChatGPT logins normally have
  /// a UUID-like id.
  final String? loginId;
  final bool success;
  final String? error;
}

/// Safe representation of `account/updated`.
class CodexAccountUpdated {
  const CodexAccountUpdated({this.authMode, this.planType});

  factory CodexAccountUpdated.fromJson(Map<String, dynamic> json) {
    return CodexAccountUpdated(
      authMode: _stringValue(json['authMode']),
      planType: _stringValue(json['planType']),
    );
  }

  final String? authMode;
  final String? planType;
}

class CodexRateLimitWindow {
  const CodexRateLimitWindow({
    required this.usedPercent,
    this.windowDurationMinutes,
    this.resetsAt,
  });

  factory CodexRateLimitWindow.fromJson(Map<String, dynamic> json) {
    final resetValue = json['resetsAt'] ?? json['resetAt'];
    return CodexRateLimitWindow(
      usedPercent: _numberValue(json['usedPercent']) ?? 0,
      windowDurationMinutes:
          (_numberValue(json['windowDurationMins']) ??
                  _numberValue(json['windowDurationMinutes']))
              ?.round(),
      resetsAt: _dateTimeValue(resetValue),
    );
  }

  final double usedPercent;
  final int? windowDurationMinutes;
  final DateTime? resetsAt;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class CodexQuota {
  const CodexQuota({
    required this.planType,
    required this.limitId,
    this.limitName,
    this.primary,
    this.secondary,
    this.hasCredits = false,
    this.creditBalance,
    this.unlimitedCredits = false,
  });

  factory CodexQuota.fromJson(Map<String, dynamic> json) {
    final rateLimitsValue = json['rateLimits'] ?? json['rate_limits'] ?? json;
    final rateLimits = rateLimitsValue is Map
        ? Map<String, dynamic>.from(rateLimitsValue)
        : const <String, dynamic>{};
    final creditsValue = json['credits'];
    final credits = creditsValue is Map
        ? Map<String, dynamic>.from(creditsValue)
        : const <String, dynamic>{};
    final primaryValue = rateLimits['primary'];
    final secondaryValue = rateLimits['secondary'];
    return CodexQuota(
      planType:
          _stringValue(json['planType']) ??
          _stringValue(rateLimits['planType']) ??
          'chatgpt',
      limitId: _stringValue(rateLimits['limitId']) ?? 'codex',
      limitName: _stringValue(rateLimits['limitName']),
      primary: primaryValue is Map
          ? CodexRateLimitWindow.fromJson(
              Map<String, dynamic>.from(primaryValue),
            )
          : null,
      secondary: secondaryValue is Map
          ? CodexRateLimitWindow.fromJson(
              Map<String, dynamic>.from(secondaryValue),
            )
          : null,
      hasCredits: credits['hasCredits'] == true,
      creditBalance: _numberValue(credits['balance']),
      unlimitedCredits: credits['unlimited'] == true,
    );
  }

  final String planType;
  final String limitId;
  final String? limitName;
  final CodexRateLimitWindow? primary;
  final CodexRateLimitWindow? secondary;
  final bool hasCredits;
  final double? creditBalance;
  final bool unlimitedCredits;
}

class CodexThreadSummary {
  const CodexThreadSummary({
    required this.id,
    required this.title,
    required this.cwd,
    required this.updatedAt,
    this.createdAt,
    this.source,
  });

  factory CodexThreadSummary.fromJson(Map<String, dynamic> json) {
    final id = _stringValue(json['id']);
    if (id == null) {
      throw const CodexAppServerException('thread/list 返回的 thread 缺少 id。');
    }
    return CodexThreadSummary(
      id: id,
      title:
          _firstString(json, const ['name', 'title', 'preview']) ?? 'Codex 对话',
      cwd: _stringValue(json['cwd']) ?? '',
      updatedAt:
          _dateTimeValue(
            json['updatedAt'] ?? json['updated_at'] ?? json['recencyAt'],
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      createdAt: _dateTimeValue(json['createdAt'] ?? json['created_at']),
      source: _sourceLabel(json['source']),
    );
  }

  final String id;
  final String title;
  final String cwd;
  final DateTime updatedAt;
  final DateTime? createdAt;
  final String? source;
}

class CodexThreadPage {
  const CodexThreadPage({required this.threads, this.nextCursor});

  final List<CodexThreadSummary> threads;
  final String? nextCursor;
}

class CodexStoredConversation {
  const CodexStoredConversation({
    required this.thread,
    required this.transcript,
    required this.isComplete,
    required this.turnCount,
  });

  final CodexThreadSummary thread;
  final String transcript;
  final bool isComplete;
  final int turnCount;
}

/// Bidirectional JSONL transport used by [CodexAppServerClient].
///
/// A custom implementation is useful for integration tests or for a host
/// that already launched `codex app-server`. Implementations must emit one
/// complete JSON object per line and must not add logging around credential
/// payloads.
abstract interface class CodexJsonlTransport {
  Stream<String> get lines;

  Future<void> writeLine(String line);

  /// Completes when the underlying transport exits. A custom transport may
  /// return a never-completing future while it remains connected.
  Future<void> get done;

  Future<void> close();
}

/// A stdio transport backed by a locally installed Codex executable.
///
/// This is the transport used on Windows by default. The executable is not
/// bundled or downloaded by this class; callers should provide a trusted,
/// version-pinned path when shipping an installer.
class ProcessCodexJsonlTransport implements CodexJsonlTransport {
  ProcessCodexJsonlTransport._(this._process) {
    _lines = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    // Always drain stderr so a verbose child process cannot block on a full
    // pipe. We intentionally do not expose or log its contents.
    unawaited(_process.stderr.drain<void>().catchError((Object _) {}));
  }

  /// Starts `executable arguments` and connects its stdin/stdout as JSONL.
  static Future<ProcessCodexJsonlTransport> start({
    String executable = 'codex',
    List<String> arguments = const ['app-server'],
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool? runInShell,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      // A Windows npm installation can expose codex.cmd rather than codex.exe.
      // Shell execution is opt-in on other platforms and can be disabled by
      // callers that resolve an absolute executable path.
      runInShell: runInShell ?? Platform.isWindows,
    );
    return ProcessCodexJsonlTransport._(process);
  }

  final Process _process;
  late final Stream<String> _lines;
  bool _closed = false;

  @override
  Stream<String> get lines => _lines;

  @override
  Future<void> get done async {
    await _process.exitCode;
  }

  @override
  Future<void> writeLine(String line) async {
    if (_closed) {
      throw const CodexAppServerException('Codex App Server transport 已关闭。');
    }
    _process.stdin.write('$line\n');
    await _process.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Kill first so a child waiting for another request cannot keep shutdown
    // pending indefinitely. Closing stdin is still attempted to release the
    // pipe cleanly on platforms where the process already exited.
    _process.kill();
    try {
      await _process.stdin.close();
    } catch (_) {
      // The process may have closed stdin concurrently.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // The OS will reap the process after kill; there is no credential data
      // to retain in this transport.
    } catch (_) {
      // Exit errors are not actionable during best-effort shutdown.
    }
  }
}

/// Minimal JSONL client for the Codex App Server protocol.
///
/// The client owns only the subprocess/connection and protocol state. For
/// managed ChatGPT sign-in, Codex owns the OAuth browser callback and token
/// persistence. This class never reads `auth.json`, browser cookies, or token
/// fields, and it never writes credentials to the Flutter app database.
class CodexAppServerClient {
  CodexAppServerClient({
    this.executable = 'codex',
    this.arguments = const ['app-server'],
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    bool? runInShell,
    this.requestTimeout = const Duration(seconds: 30),
    // A public injection point keeps protocol tests and remote hosts
    // independent from the local process launcher.
    CodexJsonlTransport? transport,
  }) : runInShell = runInShell ?? Platform.isWindows,
       _transport = transport;

  /// Executable name or absolute path used by [start] when no transport was
  /// injected. On Windows this can be `codex.exe` or a trusted `codex.cmd`.
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;
  final Duration requestTimeout;

  CodexJsonlTransport? _transport;
  StreamSubscription<String>? _lineSubscription;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<String, _ActiveTurnCapture> _activeTurns =
      <String, _ActiveTurnCapture>{};
  final Map<String, CodexLoginCompleted> _completedLoginCache =
      <String, CodexLoginCompleted>{};
  final StreamController<CodexLoginCompleted> _loginCompletions =
      StreamController<CodexLoginCompleted>.broadcast();
  final StreamController<CodexAccountUpdated> _accountUpdates =
      StreamController<CodexAccountUpdated>.broadcast();

  Future<void> _writeTail = Future<void>.value();
  int _nextRequestId = 1;
  bool _started = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _transportEnded = false;

  /// True when this Dart VM can launch a local process. Android/iOS builds
  /// should inject a supported remote transport instead; no Codex binary is
  /// assumed to exist inside an APK.
  bool get canLaunchLocalProcess =>
      !Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia;

  bool get isStarted => _started && !_disposed;
  bool get isInitialized => _initialized && !_disposed && !_transportEnded;

  Stream<CodexLoginCompleted> get loginCompletions => _loginCompletions.stream;

  Stream<CodexAccountUpdated> get accountUpdates => _accountUpdates.stream;

  /// Starts the local `codex app-server` process (Windows by default) or
  /// attaches to the injected [CodexJsonlTransport], then performs the
  /// required initialize/initialized handshake.
  Future<void> start({
    String clientName = 'ai_study_os',
    String clientTitle = 'AILearningOS',
    String clientVersion = '0.1.0',
    bool experimentalApi = false,
  }) async {
    _ensureNotDisposed();
    if (_started) return;

    final selectedTransport = await _ensureTransport();
    _started = true;
    _lineSubscription = selectedTransport.lines.listen(
      _handleLine,
      onError: _handleTransportError,
      onDone: _handleTransportDone,
      cancelOnError: false,
    );
    // Some custom transports do not close their line stream when the process
    // exits, so also observe the explicit completion future when available.
    selectedTransport.done.then<void>(
      (_) => _handleTransportDone(),
      onError: (Object error, StackTrace stack) {
        _handleTransportError(error, stack);
      },
    );

    final normalizedName = clientName.trim();
    final normalizedTitle = clientTitle.trim();
    final normalizedVersion = clientVersion.trim();
    if (normalizedName.isEmpty || normalizedVersion.isEmpty) {
      throw ArgumentError('clientName 和 clientVersion 不能为空。');
    }

    final params = <String, Object?>{
      'clientInfo': {
        'name': normalizedName,
        if (normalizedTitle.isNotEmpty) 'title': normalizedTitle,
        'version': normalizedVersion,
      },
    };
    if (experimentalApi) {
      params['capabilities'] = const {'experimentalApi': true};
    }

    try {
      await _request('initialize', params: params);
      _initialized = true;
      await _sendMessage(const {
        'method': 'initialized',
        'params': <String, Object?>{},
      });
    } catch (_) {
      // A failed handshake must not leave a child process running in the
      // background. Dispose also fails any pending requests safely.
      await dispose();
      rethrow;
    }
  }

  /// Reads account metadata without exposing managed credentials.
  Future<CodexAccountState> readAccount({bool refreshToken = false}) async {
    _ensureInitialized();
    final result = await _request(
      'account/read',
      params: {'refreshToken': refreshToken},
    );
    return CodexAccountState.fromJson(_resultMap(result, 'account/read'));
  }

  /// Starts the documented browser-based ChatGPT login flow.
  Future<CodexChatGptLogin> startChatGptLogin({
    bool useHostedLoginSuccessPage = true,
    String appBrand = 'chatgpt',
  }) async {
    _ensureInitialized();
    final normalizedBrand = appBrand.trim();
    if (normalizedBrand != 'chatgpt' && normalizedBrand != 'codex') {
      throw ArgumentError('appBrand 只能是 chatgpt 或 codex。');
    }
    final result = await _request(
      'account/login/start',
      params: {
        'type': 'chatgpt',
        'useHostedLoginSuccessPage': useHostedLoginSuccessPage,
        'appBrand': normalizedBrand,
      },
    );
    return _parseBrowserLogin(_resultMap(result, 'account/login/start'));
  }

  /// Starts the documented ChatGPT device-code login flow.
  Future<CodexChatGptLogin> startChatGptDeviceCodeLogin() async {
    _ensureInitialized();
    final result = await _request(
      'account/login/start',
      params: const {'type': 'chatgptDeviceCode'},
    );
    return _parseDeviceCodeLogin(_resultMap(result, 'account/login/start'));
  }

  /// Waits for the server's `account/login/completed` notification for a
  /// managed login. The recent-result cache closes the race where a fast
  /// device-code login completes before the caller starts waiting.
  Future<CodexLoginCompleted> waitForLoginCompletion(
    String loginId, {
    Duration? timeout,
  }) {
    final normalizedId = loginId.trim();
    if (normalizedId.isEmpty) {
      return Future<CodexLoginCompleted>.error(
        ArgumentError.value(loginId, 'loginId', '不能为空。'),
      );
    }
    final cached = _completedLoginCache[normalizedId];
    if (cached != null) return Future<CodexLoginCompleted>.value(cached);

    var future = loginCompletions.firstWhere(
      (event) => event.loginId == normalizedId,
    );
    if (timeout != null) future = future.timeout(timeout);
    return future;
  }

  /// Waits for completion and then reads the safe account state. No token is
  /// returned or persisted.
  Future<CodexAccountState> completeChatGptLogin(
    CodexChatGptLogin challenge, {
    Duration? timeout,
  }) async {
    final completion = await waitForLoginCompletion(
      challenge.loginId,
      timeout: timeout,
    );
    if (!completion.success) {
      throw CodexAppServerException(
        completion.error ?? 'ChatGPT 登录未完成。',
        method: 'account/login/completed',
      );
    }
    return readAccount();
  }

  Future<void> cancelLogin(String loginId) async {
    _ensureInitialized();
    final normalizedId = loginId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(loginId, 'loginId', '不能为空。');
    }
    await _request('account/login/cancel', params: {'loginId': normalizedId});
  }

  Future<void> logout() async {
    _ensureInitialized();
    await _request('account/logout');
  }

  Future<List<String>> listModels() async {
    _ensureInitialized();
    final modelIds = <String>{};
    String? cursor;
    do {
      final result = await _request(
        'model/list',
        params: {'limit': 100, 'includeHidden': false, 'cursor': ?cursor},
      );
      final map = _resultMap(result, 'model/list');
      // App Server's public protocol returns the model collection in `data`.
      // Keep the legacy key for compatibility with older local builds.
      final models = map['data'] ?? map['models'];
      if (models is List) {
        for (final model in models) {
          if (model is! Map) continue;
          final id =
              _stringValue(model['id']) ??
              _stringValue(model['model']) ??
              _stringValue(model['name']) ??
              _stringValue(model['slug']);
          if (id != null) modelIds.add(id);
        }
      }
      final next = _stringValue(map['nextCursor']);
      if (next == null || next == cursor) break;
      cursor = next;
    } while (true);
    return modelIds.toList(growable: false);
  }

  /// Reads the current ChatGPT Codex usage windows. This is subscription
  /// metadata only; no bearer token or billing credential is returned.
  Future<CodexQuota> readRateLimits() async {
    _ensureInitialized();
    final result = await _request('account/rateLimits/read');
    return CodexQuota.fromJson(_resultMap(result, 'account/rateLimits/read'));
  }

  /// Lists persisted Codex threads using the public App Server protocol.
  Future<CodexThreadPage> listThreads({
    String? cursor,
    int limit = 100,
    String? cwd,
  }) async {
    _ensureInitialized();
    final params = <String, Object?>{
      'limit': limit.clamp(1, 100),
      'sortKey': 'updated_at',
      'sourceKinds': const <String>[
        'cli',
        'vscode',
        'exec',
        'appServer',
        'subAgent',
        'subAgentReview',
        'subAgentCompact',
        'subAgentThreadSpawn',
        'subAgentOther',
        'unknown',
      ],
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      params['cursor'] = normalizedCursor;
    }
    final normalizedCwd = cwd?.trim();
    if (normalizedCwd != null && normalizedCwd.isNotEmpty) {
      params['cwd'] = normalizedCwd;
    }
    final result = await _request('thread/list', params: params);
    final map = _resultMap(result, 'thread/list');
    final data = map['data'];
    return CodexThreadPage(
      threads: [
        if (data is List)
          for (final value in data)
            if (value is Map)
              CodexThreadSummary.fromJson(Map<String, dynamic>.from(value)),
      ],
      nextCursor: _stringValue(map['nextCursor']),
    );
  }

  /// Reads user and assistant messages from a stored Codex thread.
  /// Reasoning, command execution, tool output and file-change items are
  /// intentionally excluded from the transcript.
  Future<CodexStoredConversation> readStoredConversation(
    CodexThreadSummary thread, {
    int? maxTurns,
  }) async {
    _ensureInitialized();
    final turns = <Map<String, dynamic>>[];
    String? cursor;
    var newestTurnComplete = false;
    var sawNewestTurn = false;

    while (maxTurns == null || turns.length < maxTurns) {
      final remaining = maxTurns == null ? 100 : maxTurns - turns.length;
      final params = <String, Object?>{
        'threadId': thread.id,
        'limit': remaining.clamp(1, 100),
        'sortDirection': 'desc',
        'itemsView': 'full',
        if (cursor case final cursorValue?) 'cursor': cursorValue,
      };
      final result = await _request('thread/turns/list', params: params);
      final map = _resultMap(result, 'thread/turns/list');
      final data = map['data'];
      if (data is! List || data.isEmpty) break;
      for (final value in data) {
        if (value is! Map || (maxTurns != null && turns.length >= maxTurns)) {
          continue;
        }
        final turn = Map<String, dynamic>.from(value);
        if (!sawNewestTurn) {
          sawNewestTurn = true;
          final status = _stringValue(turn['status']) ?? '';
          newestTurnComplete =
              status == 'completed' ||
              status == 'failed' ||
              status == 'interrupted';
        }
        turns.add(turn);
      }
      final next = _stringValue(map['nextCursor']);
      if (next == null || next == cursor) break;
      cursor = next;
    }

    turns.sort((left, right) {
      final leftAt =
          _dateTimeValue(left['startedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final rightAt =
          _dateTimeValue(right['startedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return leftAt.compareTo(rightAt);
    });
    final messages = <String>[];
    for (final turn in turns) {
      final items = turn['items'];
      if (items is! List) continue;
      for (final value in items) {
        if (value is! Map) continue;
        final item = Map<String, dynamic>.from(value);
        final type = _stringValue(item['type']);
        if (type == 'userMessage') {
          final text = _messageText(item['content']);
          if (text != null) messages.add('User:\n$text');
        } else if (type == 'agentMessage') {
          final text = _messageText(item['text'] ?? item['content']);
          if (text != null) messages.add('Assistant:\n$text');
        }
      }
    }
    final transcript = messages.join('\n\n').trim();
    return CodexStoredConversation(
      thread: thread,
      transcript: transcript,
      isComplete: sawNewestTurn && newestTurnComplete,
      turnCount: turns.length,
    );
  }

  Future<CodexThread> startThread({String? model}) async {
    _ensureInitialized();
    final params = <String, Object?>{};
    final normalizedModel = model?.trim();
    if (normalizedModel != null && normalizedModel.isNotEmpty) {
      params['model'] = normalizedModel;
    }
    final result = await _request('thread/start', params: params);
    final map = _resultMap(result, 'thread/start');
    final thread = map['thread'];
    if (thread is! Map) {
      throw const CodexAppServerException('thread/start 没有返回有效的 thread。');
    }
    final threadId = _stringValue(thread['id']);
    if (threadId == null) {
      throw const CodexAppServerException('thread/start 返回的 thread 缺少 id。');
    }
    return CodexThread(id: threadId);
  }

  Future<CodexTurnResult> runTurn({
    required String threadId,
    required String prompt,
    String? model,
    Map<String, Object?>? outputSchema,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    _ensureInitialized();
    final normalizedThreadId = threadId.trim();
    if (normalizedThreadId.isEmpty) {
      throw ArgumentError.value(threadId, 'threadId', '不能为空。');
    }
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', '不能为空。');
    }

    final params = <String, Object?>{
      'threadId': normalizedThreadId,
      'input': [
        {'type': 'text', 'text': normalizedPrompt},
      ],
      'approvalPolicy': 'never',
      'summary': 'concise',
      'personality': 'friendly',
    };
    final normalizedModel = model?.trim();
    if (normalizedModel != null && normalizedModel.isNotEmpty) {
      params['model'] = normalizedModel;
    }
    if (outputSchema != null) {
      params['outputSchema'] = outputSchema;
    }

    final result = await _request('turn/start', params: params);
    final map = _resultMap(result, 'turn/start');
    final turn = map['turn'];
    if (turn is! Map) {
      throw const CodexAppServerException('turn/start 没有返回有效的 turn。');
    }
    final turnId = _stringValue(turn['id']);
    if (turnId == null) {
      throw const CodexAppServerException('turn/start 返回的 turn 缺少 id。');
    }

    final capture = _ActiveTurnCapture(turnId);
    _activeTurns[turnId] = capture;
    try {
      return await capture.completer.future.timeout(
        timeout,
        onTimeout: () {
          _activeTurns.remove(turnId);
          throw CodexAppServerException(
            'turn/start 等待结果超时。',
            method: 'turn/start',
          );
        },
      );
    } finally {
      _activeTurns.remove(turnId);
    }
  }

  /// Closes the transport and completes all pending requests with an error.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _initialized = false;
    final error = const CodexAppServerException('Codex App Server 客户端已关闭。');
    _failPending(error);
    await _lineSubscription?.cancel();
    _lineSubscription = null;
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      await transport.close();
    }
    await _loginCompletions.close();
    await _accountUpdates.close();
  }

  Future<CodexJsonlTransport> _ensureTransport() async {
    final existing = _transport;
    if (existing != null) return existing;
    if (!canLaunchLocalProcess) {
      throw const CodexAppServerException(
        '此移动平台不能在 APK 内启动 codex app-server；请注入受信任的远程传输或使用 API 服务。',
      );
    }
    try {
      final processTransport = await ProcessCodexJsonlTransport.start(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: runInShell,
      );
      _transport = processTransport;
      return processTransport;
    } on Object catch (error) {
      throw CodexAppServerException(
        '无法启动 Codex App Server（请确认 codex 已安装且可执行）：$error',
      );
    }
  }

  Future<Object?> _request(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    _ensureNotDisposed();
    if (!_started) {
      throw StateError('请先调用 CodexAppServerClient.start()。');
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    final request = <String, Object?>{
      'method': method,
      'id': id,
      'params': params,
    };
    final writeFuture = _sendMessage(request);
    writeFuture.catchError((Object error, StackTrace stack) {
      final pending = _pending.remove(id);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          CodexAppServerException('发送 $method 请求失败：$error', method: method),
          stack,
        );
      }
    });

    var future = completer.future;
    if (requestTimeout > Duration.zero) {
      future = future.timeout(
        requestTimeout,
        onTimeout: () {
          _pending.remove(id);
          throw CodexAppServerException('$method 请求超时。', method: method);
        },
      );
    }
    return future;
  }

  Future<void> _sendMessage(Map<String, Object?> message) {
    final transport = _transport;
    if (transport == null || _disposed) {
      return Future<void>.error(
        const CodexAppServerException('Codex App Server transport 不可用。'),
      );
    }
    final encoded = jsonEncode(message);
    final write = _writeTail.then<void>(
      (_) => transport.writeLine(encoded),
      onError: (_, _) => transport.writeLine(encoded),
    );
    // Keep the queue alive after an individual failed write so a later
    // dispose/error path cannot create an unhandled chain rejection.
    _writeTail = write.then<void>((_) {}, onError: (_, _) {});
    return write;
  }

  void _handleLine(String line) {
    if (_disposed || _transportEnded || line.trim().isEmpty) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on Object {
      _handleProtocolError(
        const CodexAppServerException('Codex App Server 返回了无效 JSON。'),
      );
      return;
    }
    if (decoded is! Map) {
      _handleProtocolError(
        const CodexAppServerException('Codex App Server 返回的消息不是 JSON 对象。'),
      );
      return;
    }
    final Map<String, dynamic> message;
    try {
      message = Map<String, dynamic>.from(decoded);
    } on Object {
      _handleProtocolError(
        const CodexAppServerException('Codex App Server 消息字段无效。'),
      );
      return;
    }

    final rawId = message['id'];
    final id = _requestId(rawId);
    if (id != null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      final errorJson = message['error'];
      if (errorJson is Map) {
        final errorMap = Map<String, dynamic>.from(errorJson);
        final codeValue = errorMap['code'];
        final code = codeValue is num ? codeValue.toInt() : null;
        final errorMessage =
            _stringValue(errorMap['message']) ?? 'Codex App Server 请求失败。';
        completer.completeError(
          CodexAppServerException(errorMessage, code: code),
        );
      } else {
        completer.complete(message['result']);
      }
      return;
    }

    final method = _stringValue(message['method']);
    if (method == null) return;
    final paramsJson = message['params'];
    final params = paramsJson is Map
        ? Map<String, dynamic>.from(paramsJson)
        : const <String, dynamic>{};
    _handleTurnNotification(method, params);
    switch (method) {
      case 'account/login/completed':
        final completion = CodexLoginCompleted.fromJson(params);
        final loginId = completion.loginId;
        if (loginId != null && loginId.isNotEmpty) {
          // Keep a small bounded cache so callers cannot miss a very fast
          // completion notification. Values are display-safe metadata only.
          _completedLoginCache[loginId] = completion;
          while (_completedLoginCache.length > 32) {
            _completedLoginCache.remove(_completedLoginCache.keys.first);
          }
        }
        if (!_loginCompletions.isClosed) _loginCompletions.add(completion);
      case 'account/updated':
        if (!_accountUpdates.isClosed) {
          _accountUpdates.add(CodexAccountUpdated.fromJson(params));
        }
    }
  }

  void _handleTransportError(Object error, [StackTrace? stack]) {
    if (_disposed) return;
    final exception = error is CodexAppServerException
        ? error
        : CodexAppServerException('Codex App Server transport 出错：$error');
    _handleProtocolError(exception, stack);
  }

  void _handleTransportDone() {
    if (_disposed || _transportEnded) return;
    _transportEnded = true;
    _failPending(const CodexAppServerException('Codex App Server 进程已退出。'));
  }

  void _handleProtocolError(
    CodexAppServerException error, [
    StackTrace? stack,
  ]) {
    _transportEnded = true;
    _failPending(error, stack);
  }

  void _failPending(CodexAppServerException error, [StackTrace? stack]) {
    final pending = List<Completer<Object?>>.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }
    final activeTurns = List<_ActiveTurnCapture>.of(_activeTurns.values);
    _activeTurns.clear();
    for (final capture in activeTurns) {
      if (!capture.completer.isCompleted) {
        capture.completer.completeError(error, stack);
      }
    }
  }

  void _handleTurnNotification(String method, Map<String, dynamic> params) {
    final turnId = _turnIdFromParams(params);
    if (turnId == null) return;
    final capture = _activeTurns[turnId];
    if (capture == null || capture.completer.isCompleted) return;

    if (method == 'item/agentMessage/delta') {
      capture.append(_extractAgentDeltaText(params));
      return;
    }

    if (method == 'item/completed' && !capture.hasText) {
      capture.append(_extractAgentItemText(params));
      return;
    }

    if (method != 'turn/completed') return;

    final turnMap = params['turn'] is Map
        ? Map<String, dynamic>.from(params['turn'] as Map)
        : params;
    if (!capture.hasText) {
      capture.append(_extractFinalTurnText(turnMap));
    }
    final status = _stringValue(turnMap['status']) ?? 'completed';
    final error = _errorMessage(turnMap['error']);
    capture.completer.complete(
      CodexTurnResult(
        turnId: turnId,
        status: status,
        outputText: capture.buffer.toString().trim(),
        error: error,
      ),
    );
  }

  static Map<String, dynamic> _resultMap(Object? result, String method) {
    if (result is Map) return Map<String, dynamic>.from(result);
    throw CodexAppServerException('$method 返回结果格式无效。', method: method);
  }

  static CodexChatGptLogin _parseBrowserLogin(Map<String, dynamic> result) {
    final loginId = _requiredString(result['loginId'], 'loginId');
    final authUrl = _safeUri(result['authUrl'], 'authUrl');
    return CodexChatGptLogin(loginId: loginId, authUrl: authUrl);
  }

  static CodexChatGptLogin _parseDeviceCodeLogin(Map<String, dynamic> result) {
    final loginId = _requiredString(result['loginId'], 'loginId');
    final verificationUrl = _safeUri(
      result['verificationUrl'],
      'verificationUrl',
    );
    final userCode = _requiredString(result['userCode'], 'userCode');
    return CodexChatGptLogin(
      loginId: loginId,
      verificationUrl: verificationUrl,
      userCode: userCode,
    );
  }

  static Uri _safeUri(Object? value, String field) {
    final raw = _requiredString(value, field);
    final uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw CodexAppServerException('$field 不是有效的 HTTP(S) 地址。');
    }
    return uri;
  }

  static String _requiredString(Object? value, String field) {
    final string = _stringValue(value);
    if (string == null || string.isEmpty) {
      throw CodexAppServerException('登录响应缺少 $field。');
    }
    return string;
  }

  static String? _stringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _errorMessage(Object? value) {
    if (value == null) return null;
    if (value is String) return _stringValue(value);
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return _stringValue(map['message']) ?? _stringValue(map['error']);
    }
    return null;
  }

  static int? _requestId(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _turnIdFromParams(Map<String, dynamic> params) {
    final direct = _stringValue(params['turnId']);
    if (direct != null) return direct;

    final turn = params['turn'];
    if (turn is Map) {
      final turnId = _stringValue(turn['id']);
      if (turnId != null) return turnId;
    }

    final item = params['item'];
    if (item is Map) {
      final itemTurnId = _firstNestedString(
        Map<String, dynamic>.from(item),
        const ['turnId', 'turn_id'],
      );
      if (itemTurnId != null) return itemTurnId;
    }
    return _firstNestedString(params, const ['turnId', 'turn_id']);
  }

  static String? _extractAgentDeltaText(Map<String, dynamic> params) {
    final direct = _extractText(params['delta']);
    if (direct != null) return direct;
    return _extractAgentItemText(params);
  }

  static String? _extractAgentItemText(Map<String, dynamic> params) {
    final item = params['item'];
    if (item is! Map) return null;
    final itemMap = Map<String, dynamic>.from(item);
    final type = _stringValue(itemMap['type']);
    if (type != null &&
        type != 'agentMessage' &&
        type != 'assistant' &&
        type != 'message') {
      return null;
    }
    return _extractText(itemMap);
  }

  static String? _extractFinalTurnText(Map<String, dynamic> turn) {
    final items = turn['items'];
    if (items is List) {
      for (final item in items.reversed) {
        if (item is! Map) continue;
        final text = _extractAgentItemText({
          'item': Map<String, dynamic>.from(item),
        });
        if (text != null && text.trim().isNotEmpty) return text;
      }
    }
    return _extractText(turn['output']) ?? _extractText(turn['result']);
  }

  static String? _extractText(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is List) {
      final pieces = [
        for (final item in value)
          if ((_extractText(item) ?? '').isNotEmpty) _extractText(item)!,
      ];
      if (pieces.isEmpty) return null;
      return pieces.join();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in const [
        'text',
        'content',
        'delta',
        'message',
        'outputText',
        'value',
      ]) {
        final candidate = _extractText(map[key]);
        if (candidate != null) return candidate;
      }
      for (final entry in map.values) {
        final candidate = _extractText(entry);
        if (candidate != null) return candidate;
      }
    }
    return null;
  }

  static String? _firstNestedString(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final direct = _stringValue(map[key]);
      if (direct != null) return direct;
    }
    for (final value in map.values) {
      if (value is Map) {
        final nested = _firstNestedString(
          Map<String, dynamic>.from(value),
          keys,
        );
        if (nested != null) return nested;
      } else if (value is List) {
        for (final item in value) {
          if (item is! Map) continue;
          final nested = _firstNestedString(
            Map<String, dynamic>.from(item),
            keys,
          );
          if (nested != null) return nested;
        }
      }
    }
    return null;
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('CodexAppServerClient 已关闭。');
  }

  void _ensureInitialized() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw StateError('请先完成 Codex App Server initialize 握手。');
    }
  }
}
