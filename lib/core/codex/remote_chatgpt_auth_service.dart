import '../../data/app_database.dart';
import 'chatgpt_auth_service.dart';

/// Mobile implementation of the Codex login contract. It uses only the
/// application's authenticated HTTPS API; the Codex App Server process and
/// ChatGPT credentials stay on the trusted server.
class RemoteCodexChatGptAuthService extends ChatGptAuthService {
  RemoteCodexChatGptAuthService(this._database);

  final AppDatabase _database;
  final Map<String, String> _attemptSecrets = {};

  @override
  bool get supported => true;

  @override
  bool get usesRemoteGateway => true;

  @override
  Future<ChatGptAuthState> read() async {
    try {
      return _authFromMap(await _database.codexAccount());
    } catch (error) {
      return ChatGptAuthState.unavailable('Codex 网关暂不可用：$error');
    }
  }

  @override
  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false}) async {
    final response = await _database.startChatGptDeviceLogin();
    final attemptId = response['attempt_id']?.toString().trim() ?? '';
    final secret = response['attempt_secret']?.toString().trim() ?? '';
    final verificationUrl = response['verification_url']?.toString().trim();
    final userCode = response['user_code']?.toString().trim();
    if (attemptId.isEmpty ||
        secret.isEmpty ||
        verificationUrl == null ||
        verificationUrl.isEmpty ||
        userCode == null ||
        userCode.isEmpty) {
      throw StateError('服务器返回的 ChatGPT 设备码登录信息不完整。');
    }
    _attemptSecrets[attemptId] = secret;
    return ChatGptLoginChallenge(
      loginId: attemptId,
      verificationUrl: Uri.parse(verificationUrl),
      userCode: userCode,
    );
  }

  @override
  Future<ChatGptAuthState> completeLogin(
    ChatGptLoginChallenge challenge,
  ) async {
    final secret = _attemptSecrets[challenge.loginId];
    if (secret == null) throw StateError('登录请求已过期，请重新开始。');
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    var networkFailures = 0;
    try {
      while (DateTime.now().isBefore(deadline)) {
        Map<String, dynamic> response;
        try {
          response = await _database.completeChatGptDeviceLogin(
            attemptId: challenge.loginId,
            attemptSecret: secret,
          );
          networkFailures = 0;
        } on ServerConnectionException {
          if (++networkFailures >= 5) rethrow;
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        if (response['pending'] != true) {
          final auth = response['auth'];
          if (auth is! Map) {
            throw StateError('服务器没有返回 ChatGPT 登录状态。');
          }
          return _authFromMap(Map<String, dynamic>.from(auth));
        }
        final seconds = _integer(response['retry_after_seconds']) ?? 2;
        await Future<void>.delayed(Duration(seconds: seconds.clamp(1, 10)));
      }
      throw StateError('设备码已过期，请重新开始 ChatGPT 登录。');
    } finally {
      _attemptSecrets.remove(challenge.loginId);
    }
  }

  @override
  Future<void> cancelLogin(String loginId) async {
    final secret = _attemptSecrets.remove(loginId);
    if (secret == null) return;
    await _database.cancelChatGptDeviceLogin(
      attemptId: loginId,
      attemptSecret: secret,
    );
  }

  @override
  Future<void> logout() => _database.logoutCodex();

  @override
  Future<ChatGptCodexQuotaState> readQuota() async {
    try {
      final data = await _database.codexQuota();
      return ChatGptCodexQuotaState(
        available: data['available'] == true,
        planType: data['plan_type']?.toString(),
        primaryUsedPercent: _number(data['primary_used_percent']),
        primaryWindowMinutes: _integer(data['primary_window_minutes']),
        primaryResetsAt: _date(data['primary_resets_at']),
        secondaryUsedPercent: _number(data['secondary_used_percent']),
        secondaryWindowMinutes: _integer(data['secondary_window_minutes']),
        secondaryResetsAt: _date(data['secondary_resets_at']),
        updatedAt: _date(data['updated_at']) ?? DateTime.now(),
      );
    } catch (error) {
      return ChatGptCodexQuotaState.unavailable('Codex 额度读取失败：$error');
    }
  }

  @override
  Future<List<String>> listModels() => _database.codexModels();

  @override
  Future<CodexHistoryBatch> readCodexHistory({bool fullRefresh = false}) async {
    final data = await _database.codexHistory(fullRefresh: fullRefresh);
    final changed = data['changed_conversations'];
    return CodexHistoryBatch(
      folderName: data['folder_name']?.toString() ?? 'OSS',
      totalThreads: _integer(data['total_threads']) ?? 0,
      checkedAt: _date(data['checked_at']) ?? DateTime.now(),
      changedConversations:
          [
                if (changed is List)
                  for (final item in changed)
                    if (item is Map)
                      CodexConversationRecord(
                        externalId: item['external_id']?.toString() ?? '',
                        title: item['title']?.toString() ?? 'Codex 对话',
                        transcript: item['transcript']?.toString() ?? '',
                        updatedAt: _date(item['updated_at']) ?? DateTime.now(),
                        isComplete: item['is_complete'] == true,
                        cwd: item['cwd']?.toString() ?? '',
                      ),
              ]
              .where(
                (item) =>
                    item.externalId.isNotEmpty && item.transcript.isNotEmpty,
              )
              .toList(growable: false),
    );
  }

  @override
  Future<void> dispose() async {
    _attemptSecrets.clear();
  }

  static ChatGptAuthState _authFromMap(Map<String, dynamic> data) {
    if (data['available'] != true) {
      return ChatGptAuthState.unavailable(data['message']?.toString());
    }
    if (data['authenticated'] != true) {
      return ChatGptAuthState.signedOut(message: data['message']?.toString());
    }
    return ChatGptAuthState(
      available: true,
      authenticated: true,
      accountId: data['account_id']?.toString(),
      email: data['email']?.toString(),
      displayName: data['display_name']?.toString(),
      planType: data['plan_type']?.toString(),
      message: data['message']?.toString(),
    );
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
}
