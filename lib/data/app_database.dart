import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/learning_engine.dart';
import '../domain/models.dart';
import '../domain/security_policy.dart';
import '../domain/word_parser.dart';

/// HTTP-backed data source shared by Android and Windows builds.
class AppDatabase {
  AppDatabase._(this.apiUrl, this._sessionStore) : _client = http.Client();
  final String apiUrl;
  final http.Client _client;
  final _ServerSessionStore _sessionStore;
  static const _defaultApiUrl = 'https://os.georgehan0514.top';

  static Future<AppDatabase> open() async {
    const configured = String.fromEnvironment('AI_STUDY_OS_API_URL');
    final url = (configured.trim().isEmpty ? _defaultApiUrl : configured)
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');
    return AppDatabase._(url, _ServerSessionStore());
  }

  /// Called only by the real application bootstrap. Keeping this explicit
  /// avoids initializing a platform credential plug-in in pure widget tests.
  Future<void> restoreSession() async {
    _bearerToken = await _sessionStore.read();
  }

  String? _bearerToken;

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = http.Request(method, Uri.parse('$apiUrl$path'))
      ..headers['Accept'] = 'application/json';
    final token = _bearerToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    late http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } catch (error) {
      throw ServerConnectionException('服务器连接失败（$apiUrl）：$error');
    }
    dynamic decoded;
    try {
      decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['error'] ?? decoded['message']
          : null;
      final action = decoded is Map ? decoded['action']?.toString().trim() : '';
      throw StateError(
        [
          message?.toString() ?? '服务器返回 HTTP ${response.statusCode}',
          if (action != null && action.isNotEmpty) action,
        ].join(' '),
      );
    }
    return decoded;
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _adoptSession(Map<String, dynamic> response) async {
    final token = response['session_token']?.toString().trim() ?? '';
    if (token.isEmpty) return;
    _bearerToken = token;
    await _sessionStore.write(token);
  }

  Future<AppUser?> currentUser() async {
    try {
      final user = _map(await _request('GET', '/api/users/current'))['user'];
      return user is Map ? AppUser.fromMap(_map(user)) : null;
    } on StateError catch (error) {
      // Older deployed servers used to throw when no session existed. Treat
      // that response as a signed-out state so the app can still show login.
      if (error.message.toLowerCase().contains('no current user')) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> canvasConnection() async =>
      _map(await _request('GET', '/api/integrations/canvas/connection'));

  Future<Map<String, dynamic>> connectCanvas(
    String baseUrl,
    String token,
  ) async => _map(
    await _request(
      'PUT',
      '/api/integrations/canvas/connection',
      body: {'base_url': baseUrl.trim(), 'token': token.trim()},
    ),
  );

  Future<void> disconnectCanvas() async {
    await _request('DELETE', '/api/integrations/canvas/connection');
  }

  Future<Map<String, dynamic>> canvasCourses({String? cursor}) async => _map(
    await _request(
      'GET',
      '/api/integrations/canvas/courses${_canvasCursor(cursor)}',
    ),
  );

  Future<Map<String, dynamic>> canvasAssignments(
    String courseId, {
    String? cursor,
  }) async => _map(
    await _request(
      'GET',
      '/api/integrations/canvas/courses/${Uri.encodeComponent(courseId)}/assignments${_canvasCursor(cursor)}',
    ),
  );

  String _canvasCursor(String? cursor) =>
      cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}';

  /// Compatibility method for old callers. Do not use this for new login UI:
  /// password verification belongs on the server.
  Future<StoredCredential?> credentialForEmail(String email) async {
    final data = _map(
      await _request(
        'GET',
        '/api/users/credential?email=${Uri.encodeQueryComponent(email.trim())}',
      ),
    );
    final user = data['user'];
    if (user is! Map ||
        data['password_hash'] is! String ||
        data['password_salt'] is! String) {
      return null;
    }
    return StoredCredential(
      user: AppUser.fromMap(_map(user)),
      passwordHash: data['password_hash'] as String,
      passwordSalt: data['password_salt'] as String,
    );
  }

  Future<AppUser?> userForEmail(String email) async {
    final user = _map(
      await _request(
        'GET',
        '/api/users/by-email?email=${Uri.encodeQueryComponent(email.trim())}',
      ),
    )['user'];
    return user is Map ? AppUser.fromMap(_map(user)) : null;
  }

  Future<AppUser> authenticate({
    required String email,
    required String password,
  }) async {
    final response = _map(
      await _request(
        'POST',
        '/api/auth/login',
        body: {'email': email, 'password': password},
      ),
    );
    await _adoptSession(response);
    final user = response['user'];
    if (user is! Map) throw StateError('服务器登录响应缺少用户信息。');
    return AppUser.fromMap(_map(user));
  }

  Future<LoginSecurityState> loginSecurityForEmail(String email) async =>
      LoginSecurityState.fromMap(
        _map(
          await _request(
            'GET',
            '/api/login-security/${Uri.encodeComponent(email.trim())}',
          ),
        ),
      );
  Future<LoginSecurityState> recordFailedLogin(String email) async =>
      LoginSecurityState.fromMap(
        _map(
          await _request(
            'POST',
            '/api/login-security/${Uri.encodeComponent(email.trim())}/failed',
          ),
        ),
      );
  Future<void> clearFailedLogins(String email) async {
    await _request(
      'POST',
      '/api/login-security/${Uri.encodeComponent(email.trim())}/clear',
    );
  }

  Future<AiConnectionSettings> aiSettings(int userId) async {
    final data = _map(await _request('GET', '/api/users/$userId/settings/ai'));
    final model = _normalizeDeepSeekModel(data['model'] as String? ?? '');
    return AiConnectionSettings(
      enabled: data['enabled'] == true,
      // Provider keys are decrypted only for server-side AI jobs and are
      // never returned to Android or Windows.
      apiKey: '',
      model: model,
      provider: AiProvider.fromApiValue(data['provider']),
      codexModel: (data['codex_model'] as String? ?? '').trim().isEmpty
          ? AiConnectionSettings.defaultCodexModel
          : (data['codex_model'] as String).trim(),
      apiKeyConfigured: data['api_key_configured'] == true,
      apiKeyHint: data['api_key_hint']?.toString(),
      serverEncryptionReady: data['encryption_ready'] == true,
    );
  }

  Future<void> saveAiSettings(int userId, AiConnectionSettings settings) async {
    await _request(
      'POST',
      '/api/users/$userId/settings/ai',
      body: {
        'enabled': settings.enabled,
        'api_key': settings.apiKey,
        'model': settings.model,
        'provider': settings.provider.apiValue,
        'codex_model': settings.codexModel,
      },
    );
  }

  Future<String?> testAiConnection(
    int userId,
    AiConnectionSettings settings, {
    required AiApiKeyTestSource keySource,
  }) async {
    final data = _map(
      await _request(
        'POST',
        '/api/users/$userId/settings/ai/test',
        body: {
          'enabled': settings.enabled,
          'api_key': settings.apiKey,
          'model': settings.model,
          'provider': settings.provider.apiValue,
          'codex_model': settings.codexModel,
          'key_source': keySource.apiValue,
        },
      ),
    );
    return data['ok'] == true
        ? null
        : data['message']?.toString() ?? 'DeepSeek 连接测试失败。';
  }

  Future<Map<String, dynamic>> analyzeConversation(
    int userId,
    String transcript,
  ) async => _map(
    await _request(
      'POST',
      '/api/users/$userId/ai/analyze-conversation',
      body: {'transcript': transcript},
    ),
  );

  Future<AppUser> createUser({
    required String email,
    required String displayName,
    required String passwordHash,
    required String passwordSalt,
  }) async {
    final response = _map(
      await _request(
        'POST',
        '/api/users',
        body: {
          'email': email,
          'display_name': displayName,
          'password_hash': passwordHash,
          'password_salt': passwordSalt,
        },
      ),
    );
    await _adoptSession(response);
    final user = response['user'];
    return AppUser.fromMap(_map(user));
  }

  Future<AppUser?> userForExternalAccount({
    required String provider,
    required String subject,
  }) async {
    final user = _map(
      await _request(
        'GET',
        '/api/users/external?provider=${Uri.encodeQueryComponent(provider)}&subject=${Uri.encodeQueryComponent(subject)}',
      ),
    )['user'];
    return user is Map ? AppUser.fromMap(_map(user)) : null;
  }

  Future<AppUser> createExternalUser({
    required String provider,
    required String subject,
    required String email,
    required String displayName,
  }) async {
    final response = _map(
      await _request(
        'POST',
        '/api/users/external',
        body: {
          'provider': provider,
          'subject': subject,
          'email': email,
          'display_name': displayName,
        },
      ),
    );
    await _adoptSession(response);
    final user = response['user'];
    return AppUser.fromMap(_map(user));
  }

  Future<void> setCurrentUser(int userId) async {
    final current = await currentUser();
    if (current?.id == userId) return;
    throw StateError('服务器会话与要使用的账号不一致，请重新登录。');
  }

  Future<void> clearSession() async {
    try {
      await _request('POST', '/api/session/clear');
    } finally {
      _bearerToken = null;
      await _sessionStore.clear();
    }
  }

  Future<Map<String, dynamic>> startChatGptDeviceLogin() async => _map(
    await _request(
      'POST',
      '/api/auth/chatgpt/device/start',
      timeout: const Duration(seconds: 90),
    ),
  );

  Future<Map<String, dynamic>> completeChatGptDeviceLogin({
    required String attemptId,
    required String attemptSecret,
  }) async {
    final response = _map(
      await _request(
        'POST',
        '/api/auth/chatgpt/device/${Uri.encodeComponent(attemptId)}/complete',
        body: {'attempt_secret': attemptSecret},
      ),
    );
    await _adoptSession(response);
    return response;
  }

  Future<void> cancelChatGptDeviceLogin({
    required String attemptId,
    required String attemptSecret,
  }) async {
    await _request(
      'DELETE',
      '/api/auth/chatgpt/device/${Uri.encodeComponent(attemptId)}',
      body: {'attempt_secret': attemptSecret},
    );
  }

  Future<Map<String, dynamic>> codexAccount() async =>
      _map(await _request('GET', '/api/codex/account'));

  Future<List<String>> codexModels() async {
    final values = _map(await _request('GET', '/api/codex/models'))['models'];
    return values is List
        ? values
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const [];
  }

  Future<Map<String, dynamic>> codexQuota() async =>
      _map(await _request('GET', '/api/codex/quota'));

  Future<Map<String, dynamic>> codexHistory({
    required bool fullRefresh,
  }) async => _map(
    await _request(
      'GET',
      '/api/codex/history${fullRefresh ? '?full_refresh=1' : ''}',
    ),
  );

  Future<void> logoutCodex() async {
    await _request('DELETE', '/api/codex/session');
  }

  Future<void> seedStarterData(int userId) async {
    await _request('POST', '/api/users/$userId/seed');
  }

  Future<List<StudyWord>> wordsForUser(int userId) async {
    final data = await _request('GET', '/api/words/$userId');
    return (data is List ? data : const [])
        .map((item) => StudyWord.fromMap(_map(item)))
        .toList(growable: false);
  }

  Future<int> insertWords({
    required int userId,
    required List<ParsedWord> words,
  }) async {
    final data = _map(
      await _request(
        'POST',
        '/api/words/$userId',
        body: {
          'words': [
            for (final word in words)
              {
                'word': word.word,
                'phonetic': word.phonetic,
                'part_of_speech': word.partOfSpeech,
                'translation': word.translation,
                'example_en': word.exampleEnglish,
                'example_zh': word.exampleChinese,
              },
          ],
        },
      ),
    );
    return (data['inserted'] as num?)?.toInt() ?? 0;
  }

  Future<PendingWordEnrichmentState> enrichPendingWords(int userId) async {
    final data = _map(
      await _request(
        'POST',
        '/api/words/$userId/enrich-pending',
        body: {'background': true},
      ),
    );
    return PendingWordEnrichmentState.fromMap(data);
  }

  Future<int> applyWordEnrichments({
    required int userId,
    required List<ParsedWord> words,
  }) async {
    final data = _map(
      await _request(
        'POST',
        '/api/words/$userId/apply-enrichment',
        body: {
          'words': [
            for (final word in words)
              {
                'word': word.word,
                'phonetic': word.phonetic,
                'part_of_speech': word.partOfSpeech,
                'translation': word.translation,
                'example_en': word.exampleEnglish,
                'example_zh': word.exampleChinese,
              },
          ],
        },
      ),
    );
    return (data['updated'] as num?)?.toInt() ?? 0;
  }

  Future<void> recordReview({
    required int userId,
    required StudyWord word,
    required ReviewRating rating,
    required ReviewSchedule schedule,
  }) async {
    await _request(
      'POST',
      '/api/words/$userId/review',
      body: {
        'word': word.toMap(),
        'rating': rating.index,
        'schedule': {
          'interval_days': schedule.intervalDays,
          'mastery': schedule.mastery,
          'due_at': schedule.dueAt.toIso8601String(),
        },
      },
    );
  }

  Future<List<StudyNote>> notesForUser(int userId) async {
    final data = await _request('GET', '/api/notes/$userId');
    return (data is List ? data : const [])
        .map((item) => StudyNote.fromMap(_map(item)))
        .toList(growable: false);
  }

  Future<void> addNote({
    required int userId,
    required String title,
    required String contentEnglish,
    required String contentChinese,
    required String source,
  }) async {
    await _request(
      'POST',
      '/api/notes/$userId',
      body: {
        'title': title,
        'content_en': contentEnglish,
        'content_zh': contentChinese,
        'source': source,
      },
    );
  }

  Future<List<CourseChapter>> courseChapters(int userId) async {
    final data = await _request('GET', '/api/course/$userId');
    return (data is List ? data : const [])
        .map((item) => CourseChapter.fromMap(_map(item)))
        .toList(growable: false);
  }

  Future<CourseDailyPlan> courseDailyPlan(int userId) async {
    final data = _map(await _request('GET', '/api/course/$userId/daily-plan'));
    return CourseDailyPlan.fromMap(data);
  }

  Future<CourseAttemptResult> submitCourseAttempt({
    required int userId,
    required String chapterId,
    required Map<String, int> answers,
  }) async {
    final data = _map(
      await _request(
        'POST',
        '/api/course/$userId/$chapterId/attempt',
        body: {'answers': answers},
      ),
    );
    return CourseAttemptResult.fromMap(data);
  }

  Future<ConversationSyncState> conversationSyncState(int userId) async {
    final data = _map(await _request('GET', '/api/conversation-sync/$userId'));
    final state = data['state'];
    return ConversationSyncState.fromMap(
      state is Map ? _map(state) : ConversationSyncState.defaultState.toMap(),
    );
  }

  Future<void> saveConversationSyncState({
    required int userId,
    required ConversationSyncState state,
  }) async {
    await _request(
      'POST',
      '/api/conversation-sync/$userId',
      body: state.toMap(),
    );
  }

  Future<List<ChatGptConversationSnapshot>> conversationInbox(
    int userId,
  ) async {
    final data = await _request('GET', '/api/conversation-sync/$userId/inbox');
    return (data is List ? data : const [])
        .map((item) => ChatGptConversationSnapshot.fromMap(_map(item)))
        .toList(growable: false);
  }

  Future<int> ingestConversationInbox({
    required int userId,
    required List<ChatGptConversationSnapshot> conversations,
  }) async {
    final data = _map(
      await _request(
        'POST',
        '/api/conversation-sync/$userId/inbox',
        body: {
          'conversations': [
            for (final conversation in conversations) conversation.toMap(),
          ],
        },
      ),
    );
    return (data['accepted'] as num?)?.toInt() ?? 0;
  }

  Future<void> markConversationSynced({
    required int userId,
    required String conversationId,
    required String title,
    required DateTime syncedAt,
  }) async {
    await _request(
      'POST',
      '/api/conversation-sync/$userId/complete',
      body: {
        'conversation_id': conversationId,
        'title': title,
        'synced_at': syncedAt.toIso8601String(),
      },
    );
  }

  Future<void> saveObsidianEntry({
    required int userId,
    required String title,
    required String contentEnglish,
    required String contentChinese,
    required String source,
    required String category,
    required List<String> tags,
    required String sourceId,
    required DateTime updatedAt,
  }) async {
    await _request(
      'POST',
      '/api/obsidian/entries/$userId',
      body: {
        'title': title,
        'content_en': contentEnglish,
        'content_zh': contentChinese,
        'source': source,
        'category': category,
        'tags': tags,
        'source_id': sourceId,
        'updated_at': updatedAt.toIso8601String(),
      },
    );
  }

  Future<EmailSyncState> emailSyncState({
    required int userId,
    required EmailProvider provider,
  }) async {
    final data = _map(
      await _request('GET', '/api/email-sync/$userId/${provider.apiValue}'),
    );
    final state = data['state'];
    return EmailSyncState.fromMap(
      provider,
      state is Map ? _map(state) : EmailSyncState.defaultFor(provider).toMap(),
    );
  }

  Future<void> saveEmailSyncState({
    required int userId,
    required EmailSyncState state,
  }) async {
    await _request(
      'POST',
      '/api/email-sync/$userId/${state.provider.apiValue}',
      body: state.toMap(),
    );
  }

  Future<List<EmailMessageSnapshot>> emailInbox({
    required int userId,
    required EmailProvider provider,
  }) async {
    final data = await _request(
      'GET',
      '/api/email-sync/$userId/${provider.apiValue}/inbox',
    );
    return (data is List ? data : const [])
        .map((item) => EmailMessageSnapshot.fromMap(_map(item)))
        .toList(growable: false);
  }

  Future<int> ingestEmailInbox({
    required int userId,
    required EmailProvider provider,
    required List<EmailMessageSnapshot> messages,
  }) async {
    final data = _map(
      await _request(
        'POST',
        '/api/email-sync/$userId/${provider.apiValue}/inbox',
        body: {
          'messages': [for (final message in messages) message.toMap()],
        },
      ),
    );
    return (data['accepted'] as num?)?.toInt() ?? 0;
  }

  Future<void> markEmailSynced({
    required int userId,
    required EmailProvider provider,
    required String messageId,
    required String subject,
    required DateTime syncedAt,
  }) async {
    await _request(
      'POST',
      '/api/email-sync/$userId/${provider.apiValue}/complete',
      body: {
        'message_id': messageId,
        'subject': subject,
        'synced_at': syncedAt.toIso8601String(),
      },
    );
  }

  Future<List<CapturedDocument>> capturesForUser(int userId) async {
    final data = await _request('GET', '/api/captures/$userId');
    return (data is List ? data : const [])
        .map((item) => CapturedDocument.fromMap(_map(item)))
        .toList(growable: false);
  }

  Future<void> addCapture({
    required int userId,
    required String fileName,
    required String filePath,
    required String kind,
  }) async {
    await _request(
      'POST',
      '/api/captures/$userId',
      body: {'file_name': fileName, 'file_path': filePath, 'kind': kind},
    );
  }

  Future<TodayStats> todayStats(int userId) async => TodayStats.fromMap(
    _map(await _request('GET', '/api/stats/$userId/today')),
  );
  Future<void> markCheckedIn(int userId) async {
    await _request('POST', '/api/stats/$userId/checkin');
  }

  Future<void> close() async => _client.close();

  static String _normalizeDeepSeekModel(String value) {
    final model = value.trim();
    if (model.isEmpty || model.toLowerCase() == 'deepseek-v4-flash') {
      return AiConnectionSettings.defaultModel;
    }
    if (model.toLowerCase() == 'deepseek-v4-pro') return 'deepseek-v4-pro';
    return model;
  }
}

/// A retryable failure to receive an HTTP response from the backend.
class ServerConnectionException implements Exception {
  const ServerConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps only the AILearningOS device bearer on the device. Provider
/// credentials remain inside the server's per-account CODEX_HOME directory.
class _ServerSessionStore {
  static const _key = 'ailo.server_session_bearer.v1';
  static const _storage = FlutterSecureStorage();
  String? _memoryFallback;

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key) ?? _memoryFallback;
    } catch (_) {
      // Widget tests and unsupported desktop key stores still work for the
      // current process; production Android/Windows use the secure backend.
      return _memoryFallback;
    }
  }

  Future<void> write(String value) async {
    _memoryFallback = value;
    try {
      await _storage.write(key: _key, value: value);
    } catch (_) {
      // See read(): do not persist insecurely as a fallback.
    }
  }

  Future<void> clear() async {
    _memoryFallback = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Best-effort when no platform key store is available.
    }
  }
}
