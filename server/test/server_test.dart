import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server/api/router.dart';
import 'package:server/core/ai/ai_service.dart';
import 'package:server/core/ai/deepseek_service.dart';
import 'package:server/core/ai/hybrid_ai_service.dart';
import 'package:server/core/ai/pending_word_enrichment.dart';
import 'package:server/core/codex/server_codex_gateway.dart';
import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:server/domain/models.dart';
import 'package:server/domain/word_parser.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late AppDatabase database;
  late Directory dataDirectory;
  late String host;
  late _RecordingDeepSeekService recordingDeepSeek;
  late _RecordingCodexGateway recordingCodex;

  setUpAll(() async {
    dataDirectory = await Directory.systemTemp.createTemp('ailo-server-test-');
    database = await AppDatabase.open(
      dataDirectory: dataDirectory,
      secretVault: SecretVault.forTesting(List<int>.filled(32, 41)),
    );
    recordingDeepSeek = _RecordingDeepSeekService();
    recordingCodex = _RecordingCodexGateway(database);
    final aiService = HybridAiService(deepSeekService: recordingDeepSeek);
    final processor = PendingWordEnrichmentProcessor(
      database,
      aiService,
      codexGateway: recordingCodex,
    );
    final api = ApiRouter(
      database,
      aiService,
      processor,
      codexGateway: recordingCodex,
    );
    final handler = Pipeline()
        .addMiddleware(corsHeaders())
        .addHandler(api.router.call);
    server = await serve(handler, InternetAddress.loopbackIPv4, 0);
    host = 'http://127.0.0.1:${server.port}';
  });

  tearDownAll(() async {
    await server.close(force: true);
    await database.close();
    if (await dataDirectory.exists()) {
      await dataDirectory.delete(recursive: true);
    }
  });

  test('health endpoint is available', () async {
    final response = await http.get(Uri.parse('$host/health'));
    expect(response.statusCode, 200);
    expect(response.body, 'OK');
  });

  test(
    'version advertises every implemented AI feature as dual-routed',
    () async {
      final response = await http.get(Uri.parse('$host/version'));
      expect(response.statusCode, 200);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        payload['ai_provider_switch'],
        'manual-or-explicit-codex-quota-auto-return',
      );
      expect(payload['codex_gateway_enabled'], isTrue);
      expect(payload['ai_features'], {
        'word_enrichment': 'selected_provider',
        'conversation_notes': 'selected_provider',
        'email_summaries': 'selected_provider',
        'feishu_summaries': 'selected_provider',
        'course_daily_plan': 'selected_provider',
        'ai_chat': 'selected_provider',
      });
    },
  );

  test(
    'AI keys are account-bound and stored/candidate tests never overwrite',
    () async {
      final first = await database.createUser(
        email: 'ai-owner-one@test.local',
        displayName: 'AI Owner One',
        passwordHash: '',
        passwordSalt: '',
      );
      final second = await database.createUser(
        email: 'ai-owner-two@test.local',
        displayName: 'AI Owner Two',
        passwordHash: '',
        passwordSalt: '',
      );
      await database.saveAiSettings(
        first.id,
        const AiConnectionSettings(
          enabled: true,
          apiKey: 'first-account-old-key',
          model: AiConnectionSettings.defaultModel,
        ),
      );
      await database.saveAiSettings(
        second.id,
        const AiConnectionSettings(
          enabled: true,
          apiKey: 'second-account-key',
          model: AiConnectionSettings.defaultModel,
        ),
      );
      final session = await database.createAuthSession(first.id);
      final headers = {'Authorization': 'Bearer ${session.token}'};

      final ownSettings = await http.get(
        Uri.parse('$host/api/users/${first.id}/settings/ai'),
        headers: headers,
      );
      expect(ownSettings.statusCode, 200);
      expect(ownSettings.body, isNot(contains('first-account-old-key')));
      expect(jsonDecode(ownSettings.body)['api_key_configured'], isTrue);

      final otherSettings = await http.get(
        Uri.parse('$host/api/users/${second.id}/settings/ai'),
        headers: headers,
      );
      expect(otherSettings.statusCode, 403);

      recordingDeepSeek.seenKeys.clear();
      final storedTest = await http.post(
        Uri.parse('$host/api/users/${first.id}/settings/ai/test'),
        headers: {'Content-Type': 'application/json', ...headers},
        body: jsonEncode({
          'enabled': true,
          'api_key': 'must-not-be-used-for-stored-test',
          'key_source': 'stored',
        }),
      );
      expect(storedTest.statusCode, 200);
      expect(recordingDeepSeek.seenKeys.last, 'first-account-old-key');

      final candidateTest = await http.post(
        Uri.parse('$host/api/users/${first.id}/settings/ai/test'),
        headers: {'Content-Type': 'application/json', ...headers},
        body: jsonEncode({
          'enabled': true,
          'api_key': 'new-candidate-key',
          'key_source': 'candidate',
        }),
      );
      expect(candidateTest.statusCode, 200);
      expect(recordingDeepSeek.seenKeys.last, 'new-candidate-key');
      expect(
        (await database.aiSettings(first.id)).apiKey,
        'first-account-old-key',
      );
      expect(
        (await database.aiSettings(second.id)).apiKey,
        'second-account-key',
      );
    },
  );

  test(
    'unknown words remain in the 30-second queue without an API key',
    () async {
      final email = 'queue-${DateTime.now().microsecondsSinceEpoch}@test.local';
      final userResponse = await http.post(
        Uri.parse('$host/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'display_name': 'Queue Test',
          'password_hash': '',
          'password_salt': '',
        }),
      );
      final userId = (jsonDecode(userResponse.body)['user']['id'] as num)
          .toInt();

      final importResponse = await http.post(
        Uri.parse('$host/api/words/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'words': [
            {
              'word': 'epistemology',
              'phonetic': '待生成',
              'part_of_speech': '待识别',
              'translation': '待 AI 翻译',
              'example_en': '',
              'example_zh': '',
            },
            {
              'word': 'taxonomy',
              'phonetic': '/tækˈsɒnəmi/',
              'part_of_speech': '',
              'translation': '分类学',
              'example_en': 'Taxonomy helps organize living things.',
              'example_zh': '分类学有助于组织生物。',
            },
          ],
        }),
      );
      expect(importResponse.statusCode, 200);

      final runResponse = await http.post(
        Uri.parse('$host/api/words/$userId/enrich-pending'),
      );
      expect(runResponse.statusCode, 200);
      final result = jsonDecode(runResponse.body) as Map<String, dynamic>;
      expect(result['status'], 'waiting_for_api_key');
      expect(result['pending_count'], 2);
      expect(result['retry_interval_seconds'], 30);
    },
  );

  test('AI chat uses only the account-selected provider', () async {
    final user = await database.createUser(
      email: 'routing-${DateTime.now().microsecondsSinceEpoch}@test.local',
      displayName: 'AI Routing Test',
      passwordHash: '',
      passwordSalt: '',
    );
    final session = await database.createAuthSession(user.id);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.token}',
    };

    await database.saveAiSettings(
      user.id,
      const AiConnectionSettings(
        enabled: true,
        apiKey: 'routing-deepseek-key',
        model: AiConnectionSettings.defaultModel,
        provider: AiProvider.deepSeek,
      ),
    );
    recordingDeepSeek.completedPrompts.clear();
    recordingCodex.completedPrompts.clear();
    final deepSeekResponse = await http.post(
      Uri.parse('$host/api/users/${user.id}/ai/chat'),
      headers: headers,
      body: jsonEncode({'prompt': 'route-deepseek'}),
    );
    expect(deepSeekResponse.statusCode, 200);
    expect(
      jsonDecode(deepSeekResponse.body)['result'],
      'deepseek:route-deepseek',
    );
    expect(recordingDeepSeek.completedPrompts, ['route-deepseek']);
    expect(recordingCodex.completedPrompts, isEmpty);

    await database.saveAiSettings(
      user.id,
      const AiConnectionSettings(
        enabled: true,
        apiKey: '',
        model: AiConnectionSettings.defaultModel,
        provider: AiProvider.codex,
        codexModel: AiConnectionSettings.defaultCodexModel,
      ),
    );
    final codexResponse = await http.post(
      Uri.parse('$host/api/users/${user.id}/ai/chat'),
      headers: headers,
      body: jsonEncode({'prompt': 'route-codex'}),
    );
    expect(codexResponse.statusCode, 200);
    expect(jsonDecode(codexResponse.body)['result'], 'codex:route-codex');
    expect(recordingDeepSeek.completedPrompts, ['route-deepseek']);
    expect(recordingCodex.completedPrompts, ['route-codex']);

    recordingCodex.failCompletion = true;
    final failedCodexResponse = await http.post(
      Uri.parse('$host/api/users/${user.id}/ai/chat'),
      headers: headers,
      body: jsonEncode({'prompt': 'do-not-fallback'}),
    );
    recordingCodex.failCompletion = false;
    expect(failedCodexResponse.statusCode, isNot(200));
    expect(recordingDeepSeek.completedPrompts, ['route-deepseek']);

    await database.saveAiSettings(
      user.id,
      const AiConnectionSettings(
        enabled: true,
        apiKey: '',
        model: AiConnectionSettings.defaultModel,
        provider: AiProvider.codex,
        autoReturnToCodex: true,
      ),
    );
    recordingCodex.failCompletion = true;
    recordingCodex.quotaFailure = true;
    final fallbackResponse = await http.post(
      Uri.parse('$host/api/users/${user.id}/ai/chat'),
      headers: headers,
      body: jsonEncode({'prompt': 'quota-fallback'}),
    );
    recordingCodex.failCompletion = false;
    recordingCodex.quotaFailure = false;
    expect(fallbackResponse.statusCode, 200);
    expect(
      jsonDecode(fallbackResponse.body)['result'],
      'deepseek:quota-fallback',
    );
    final fallbackSettings = await database.aiSettings(user.id);
    expect(fallbackSettings.provider, AiProvider.deepSeek);
    expect(fallbackSettings.codexResumeAt, isNotNull);

    final manualReturnResponse = await http.post(
      Uri.parse('$host/api/users/${user.id}/settings/ai'),
      headers: headers,
      body: jsonEncode({
        'enabled': true,
        'api_key': '',
        'model': AiConnectionSettings.defaultModel,
        'provider': 'codex',
        'codex_model': AiConnectionSettings.defaultCodexModel,
        'auto_return_to_codex': true,
      }),
    );
    expect(manualReturnResponse.statusCode, 200);
    final manualSettings = await database.aiSettings(user.id);
    expect(manualSettings.provider, AiProvider.codex);
    expect(manualSettings.codexResumeAt, isNull);
  });

  test(
    'idle word worker stops and wakes when a pending word is imported',
    () async {
      final workerDataDirectory = await Directory.systemTemp.createTemp(
        'ailo-worker-test-',
      );
      final workerDatabase = await AppDatabase.open(
        dataDirectory: workerDataDirectory,
        secretVault: SecretVault.forTesting(List<int>.filled(32, 53)),
      );
      final worker = PendingWordEnrichmentWorker(
        PendingWordEnrichmentProcessor(workerDatabase, HybridAiService()),
        interval: const Duration(hours: 1),
      );
      try {
        worker.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(worker.isRunning, isFalse);

        final user = await workerDatabase.createUser(
          email: 'worker-${DateTime.now().microsecondsSinceEpoch}@test.local',
          displayName: 'Worker Test',
          passwordHash: '',
          passwordSalt: '',
        );
        await workerDatabase.insertWords(
          userId: user.id,
          words: [
            const ParsedWord(
              word: 'distribution',
              phonetic: '待生成',
              partOfSpeech: '待识别',
              translation: '待 AI 翻译',
              exampleEnglish: '',
              exampleChinese: '',
            ),
          ],
        );

        worker.wakeUp();
        expect(worker.isRunning, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(worker.isRunning, isTrue);
      } finally {
        worker.stop();
        await workerDatabase.close();
        if (await workerDataDirectory.exists()) {
          await workerDataDirectory.delete(recursive: true);
        }
      }
    },
  );

  test(
    'Feishu URL verification and recording-ready callback contract',
    () async {
      final email =
          'feishu-${DateTime.now().microsecondsSinceEpoch}@test.local';
      final userResponse = await http.post(
        Uri.parse('$host/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'display_name': 'Feishu Test',
          'password_hash': '',
          'password_salt': '',
        }),
      );
      expect(userResponse.statusCode, 200);
      final userId = (jsonDecode(userResponse.body)['user']['id'] as num)
          .toInt();

      final challengeResponse = await http.post(
        Uri.parse('$host/api/feishu/$userId/webhook'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'url_verification',
          'token': 'feishu-console-token',
          'challenge': 'challenge-123',
        }),
      );
      expect(challengeResponse.statusCode, 200);
      expect(jsonDecode(challengeResponse.body)['challenge'], 'challenge-123');

      final eventResponse = await http.post(
        Uri.parse('$host/api/feishu/$userId/webhook'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'header': {
            'event_id': 'event-123',
            'event_type': 'vc.meeting.recording_ready_v1',
            'token': 'feishu-console-token',
          },
          'event': {'id': 'recording-123'},
        }),
      );
      expect(eventResponse.statusCode, 200);
      final event = jsonDecode(eventResponse.body) as Map<String, dynamic>;
      expect(event['ok'], true);
      expect(event['accepted'], false);
      expect(event['recording_id'], 'recording-123');
    },
  );

  test('unknown endpoint returns 404', () async {
    final response = await http.get(Uri.parse('$host/not-found'));
    expect(response.statusCode, 404);
  });

  test(
    'conversation inbox keeps newest first and exposes sync state',
    () async {
      final email = 'sync-${DateTime.now().microsecondsSinceEpoch}@test.local';
      final userResponse = await http.post(
        Uri.parse('$host/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'display_name': 'Sync Test',
          'password_hash': '',
          'password_salt': '',
        }),
      );
      expect(userResponse.statusCode, 200);
      final userId = (jsonDecode(userResponse.body)['user']['id'] as num)
          .toInt();

      final inboxResponse = await http.post(
        Uri.parse('$host/api/conversation-sync/$userId/inbox'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'conversations': [
            {
              'external_id': 'chat-previous',
              'title': 'Previous',
              'transcript': 'User: previous',
              'updated_at': '2026-08-27T08:00:00.000Z',
              'is_complete': true,
            },
            {
              'external_id': 'chat-newest',
              'title': 'Newest',
              'transcript': 'User: newest',
              'updated_at': '2026-08-27T08:10:00.000Z',
              'is_complete': false,
            },
          ],
        }),
      );
      expect(inboxResponse.statusCode, 200);

      final stateResponse = await http.get(
        Uri.parse('$host/api/conversation-sync/$userId'),
      );
      expect(stateResponse.statusCode, 200);
      final initialState = jsonDecode(stateResponse.body)['state'];
      expect(initialState['interval_minutes'], 15);
      expect(initialState['enabled'], false);
      expect(initialState['schedule_configured'], false);

      final scheduleResponse = await http.post(
        Uri.parse('$host/api/conversation-sync/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'enabled': false,
          'schedule_configured': true,
          'last_nightly_run_at': '2026-08-27T23:00:00.000',
        }),
      );
      expect(scheduleResponse.statusCode, 200);
      final savedSchedule = jsonDecode(scheduleResponse.body)['state'];
      expect(savedSchedule['schedule_configured'], true);
      expect(savedSchedule['last_nightly_run_at'], '2026-08-27T23:00:00.000');

      final readResponse = await http.get(
        Uri.parse('$host/api/conversation-sync/$userId/inbox'),
      );
      final conversations = jsonDecode(readResponse.body) as List<dynamic>;
      expect(conversations.first['external_id'], 'chat-newest');
      expect(conversations[1]['external_id'], 'chat-previous');
      expect(conversations.first['is_complete'], false);

      final emailResponse = await http.post(
        Uri.parse('$host/api/email-sync/$userId/qq/inbox'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': [
            {
              'external_id': 'qq-message-1',
              'subject': 'Learning update',
              'sender': 'teacher@example.com',
              'recipients': email,
              'body': 'Please review the new vocabulary list.',
              'received_at': '2026-08-27T08:20:00.000Z',
              'is_complete': true,
            },
          ],
        }),
      );
      expect(emailResponse.statusCode, 200);
      final emailInboxResponse = await http.get(
        Uri.parse('$host/api/email-sync/$userId/qq/inbox'),
      );
      final emails = jsonDecode(emailInboxResponse.body) as List<dynamic>;
      expect(emails.single['external_id'], 'qq-message-1');

      final obsidianResponse = await http.post(
        Uri.parse('$host/api/obsidian/entries/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Learning update',
          'content_en': 'Review the new vocabulary list.',
          'content_zh': '复习新的词汇表。',
          'source': 'QQ 邮箱自动同步',
          'category': 'Learning',
          'tags': ['vocabulary', 'qq'],
          'source_id': 'qq-qq-message-1',
          'updated_at': '2026-08-27T08:20:00.000Z',
        }),
      );
      expect(obsidianResponse.statusCode, 200);
    },
  );

  test('course chapters unlock in order and quizzes persist mastery', () async {
    final email = 'course-${DateTime.now().microsecondsSinceEpoch}@test.local';
    final userResponse = await http.post(
      Uri.parse('$host/api/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'display_name': 'Course Test',
        'password_hash': '',
        'password_salt': '',
      }),
    );
    expect(userResponse.statusCode, 200);
    final userId = (jsonDecode(userResponse.body)['user']['id'] as num).toInt();

    final initialResponse = await http.get(
      Uri.parse('$host/api/course/$userId'),
    );
    expect(initialResponse.statusCode, 200);
    final initial = jsonDecode(initialResponse.body) as List<dynamic>;
    expect(initial.length, greaterThanOrEqualTo(3));
    expect(initial.first['status'], 'available');
    expect(initial[1]['status'], 'locked');
    expect(initial.first['questions'].first['correct_index'], isNull);

    final dailyPlanResponse = await http.get(
      Uri.parse('$host/api/course/$userId/daily-plan'),
    );
    expect(dailyPlanResponse.statusCode, 200);
    final dailyPlan = jsonDecode(dailyPlanResponse.body);
    expect(dailyPlan['chapter_id'], 'statistics.data.01');
    expect(dailyPlan['tasks'], isA<List<dynamic>>());
    expect(dailyPlan['ai_generated'], false);

    final feishuChallengeResponse = await http.post(
      Uri.parse('$host/api/feishu/$userId/webhook'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'url_verification',
        'challenge': 'challenge-123',
      }),
    );
    expect(feishuChallengeResponse.statusCode, 200);
    expect(
      jsonDecode(feishuChallengeResponse.body)['challenge'],
      'challenge-123',
    );

    final feishuEventResponse = await http.post(
      Uri.parse('$host/api/feishu/$userId/webhook'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event': {'id': 'recording-123'},
      }),
    );
    expect(feishuEventResponse.statusCode, 200);
    expect(jsonDecode(feishuEventResponse.body)['accepted'], false);

    final failedResponse = await http.post(
      Uri.parse('$host/api/course/$userId/statistics.data.01/attempt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'answers': {'q1': 0, 'q2': 0, 'q3': 0},
      }),
    );
    expect(failedResponse.statusCode, 200);
    expect(jsonDecode(failedResponse.body)['passed'], false);

    final passedResponse = await http.post(
      Uri.parse('$host/api/course/$userId/statistics.data.01/attempt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'answers': {'q1': 1, 'q2': 1, 'q3': 1},
      }),
    );
    expect(passedResponse.statusCode, 200);
    final passed = jsonDecode(passedResponse.body) as Map<String, dynamic>;
    expect(passed['passed'], true);
    expect(passed['next_chapter_id'], 'statistics.summary.01');

    final afterResponse = await http.get(Uri.parse('$host/api/course/$userId'));
    final after = jsonDecode(afterResponse.body) as List<dynamic>;
    expect(after.first['status'], 'completed');
    expect(after[1]['status'], 'available');
    expect(after.first['attempts'], 2);
  });
}

class _RecordingDeepSeekService extends DeepSeekService {
  final List<String> seenKeys = [];
  final List<String> completedPrompts = [];

  @override
  Future<String> completeText({
    required AiConnectionSettings settings,
    required String prompt,
  }) async {
    completedPrompts.add(prompt);
    return 'deepseek:$prompt';
  }

  @override
  Future<AiConnectionProbe> testConnection(
    AiConnectionSettings settings,
  ) async {
    seenKeys.add(settings.apiKey);
    return const AiConnectionProbe(ok: true, message: 'ok');
  }
}

class _RecordingCodexGateway extends ServerCodexGateway {
  _RecordingCodexGateway(this.database) : super(database);

  final AppDatabase database;

  final List<String> completedPrompts = [];
  bool failCompletion = false;
  bool quotaFailure = false;

  @override
  bool get enabled => true;

  @override
  Future<String> completeText(
    AppUser user, {
    required AiConnectionSettings settings,
    required String prompt,
  }) async {
    completedPrompts.add(prompt);
    if (failCompletion) {
      throw StateError(
        quotaFailure ? 'Codex quota exhausted (429)' : 'Codex test failure',
      );
    }
    return 'codex:$prompt';
  }

  @override
  Future<DateTime> scheduleReturnAfterQuotaReset(AppUser user) async {
    final resumeAt = DateTime.now().toUtc().add(const Duration(hours: 5));
    await database.scheduleCodexReturn(user.id, resumeAt);
    return resumeAt;
  }
}
