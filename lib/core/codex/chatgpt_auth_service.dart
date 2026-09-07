// Models and platform-neutral contract for the official Codex App Server
// ChatGPT sign-in flow.
//
// The app deliberately keeps provider access tokens inside Codex App Server.
// These objects contain only display-safe account metadata and the short-lived
// browser/device-code challenge needed to complete sign-in.

class ChatGptAuthState {
  const ChatGptAuthState({
    required this.available,
    required this.authenticated,
    this.accountId,
    this.email,
    this.displayName,
    this.planType,
    this.message,
  });

  const ChatGptAuthState.unavailable([String? message])
    : available = false,
      authenticated = false,
      accountId = null,
      email = null,
      displayName = null,
      planType = null,
      message = message ?? '当前平台没有可用的 Codex App Server。';

  const ChatGptAuthState.signedOut({this.message})
    : available = true,
      authenticated = false,
      accountId = null,
      email = null,
      displayName = null,
      planType = null;

  final bool available;
  final bool authenticated;
  final String? accountId;
  final String? email;
  final String? displayName;
  final String? planType;
  final String? message;

  String get planLabel {
    final value = planType?.trim();
    if (value == null || value.isEmpty) return 'ChatGPT';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class ChatGptLoginChallenge {
  const ChatGptLoginChallenge({
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

class ChatGptCodexQuotaState {
  const ChatGptCodexQuotaState({
    required this.available,
    this.planType,
    this.primaryUsedPercent,
    this.primaryWindowMinutes,
    this.primaryResetsAt,
    this.secondaryUsedPercent,
    this.secondaryWindowMinutes,
    this.secondaryResetsAt,
    this.message,
    this.updatedAt,
  });

  const ChatGptCodexQuotaState.unavailable([this.message])
    : available = false,
      planType = null,
      primaryUsedPercent = null,
      primaryWindowMinutes = null,
      primaryResetsAt = null,
      secondaryUsedPercent = null,
      secondaryWindowMinutes = null,
      secondaryResetsAt = null,
      updatedAt = null;

  final bool available;
  final String? planType;
  final double? primaryUsedPercent;
  final int? primaryWindowMinutes;
  final DateTime? primaryResetsAt;
  final double? secondaryUsedPercent;
  final int? secondaryWindowMinutes;
  final DateTime? secondaryResetsAt;
  final String? message;
  final DateTime? updatedAt;

  double? get primaryRemainingPercent => primaryUsedPercent == null
      ? null
      : (100 - primaryUsedPercent!).clamp(0, 100);
  double? get secondaryRemainingPercent => secondaryUsedPercent == null
      ? null
      : (100 - secondaryUsedPercent!).clamp(0, 100);
}

class CodexConversationRecord {
  const CodexConversationRecord({
    required this.externalId,
    required this.title,
    required this.transcript,
    required this.updatedAt,
    required this.isComplete,
    required this.cwd,
  });

  final String externalId;
  final String title;
  final String transcript;
  final DateTime updatedAt;
  final bool isComplete;
  final String cwd;
}

class CodexHistoryBatch {
  const CodexHistoryBatch({
    required this.folderName,
    required this.totalThreads,
    required this.changedConversations,
    required this.checkedAt,
  });

  final String folderName;
  final int totalThreads;
  final List<CodexConversationRecord> changedConversations;
  final DateTime checkedAt;
}

class CodexHistorySyncState {
  const CodexHistorySyncState({
    required this.running,
    required this.folderName,
    required this.threadCount,
    this.lastReadAt,
    this.lastError,
  });

  const CodexHistorySyncState.idle()
    : running = false,
      folderName = 'OSS',
      threadCount = 0,
      lastReadAt = null,
      lastError = null;

  final bool running;
  final String folderName;
  final int threadCount;
  final DateTime? lastReadAt;
  final String? lastError;
}

abstract class ChatGptAuthService {
  const ChatGptAuthService();

  bool get supported;

  /// True only when Codex work must be performed by the application's trusted
  /// HTTPS gateway instead of a local Codex process.
  bool get usesRemoteGateway => false;

  Future<ChatGptAuthState> read();

  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false});

  Future<ChatGptAuthState> completeLogin(ChatGptLoginChallenge challenge);

  Future<void> cancelLogin(String loginId);

  Future<void> logout();

  Future<ChatGptCodexQuotaState> readQuota();

  /// Returns the exact model ids advertised by the active Codex App Server.
  Future<List<String>> listModels();

  Future<CodexHistoryBatch> readCodexHistory({bool fullRefresh = false});

  Future<void> dispose();
}

class NoopChatGptAuthService extends ChatGptAuthService {
  const NoopChatGptAuthService();

  @override
  bool get supported => false;

  @override
  Future<ChatGptAuthState> read() async => const ChatGptAuthState.unavailable();

  @override
  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false}) {
    return Future<ChatGptLoginChallenge>.error(
      StateError('Codex App Server 在此平台不可用。'),
    );
  }

  @override
  Future<ChatGptAuthState> completeLogin(ChatGptLoginChallenge challenge) {
    return Future<ChatGptAuthState>.error(
      StateError('Codex App Server 在此平台不可用。'),
    );
  }

  @override
  Future<void> cancelLogin(String loginId) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<ChatGptCodexQuotaState> readQuota() async =>
      const ChatGptCodexQuotaState.unavailable('当前平台不支持 Codex 额度读取。');

  @override
  Future<List<String>> listModels() async => const [];

  @override
  Future<CodexHistoryBatch> readCodexHistory({bool fullRefresh = false}) {
    return Future<CodexHistoryBatch>.error(StateError('当前平台不支持 Codex 会话读取。'));
  }

  @override
  Future<void> dispose() async {}
}
