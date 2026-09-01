import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../data/app_database.dart';
import '../core/ai/hybrid_ai_service.dart';
import '../core/ai/pending_word_enrichment.dart';
import '../domain/models.dart';
import '../domain/learning_engine.dart';
import '../domain/word_parser.dart';
import '../core/security/password_hasher.dart';

class ApiRouter {
  final AppDatabase db;
  final HybridAiService aiService;
  final PendingWordEnrichmentProcessor pendingWordProcessor;
  final PendingWordEnrichmentWorker? pendingWordWorker;
  final PasswordHasher _passwordHasher = PasswordHasher();

  ApiRouter(
    this.db,
    this.aiService,
    this.pendingWordProcessor, {
    this.pendingWordWorker,
  });

  Router get router {
    final router = Router();

    router.get('/health', (Request request) {
      return Response.ok('OK');
    });

    router.get('/version', (Request request) {
      return _json({
        'name': 'AILearningOS server',
        'build': '2026-08-31-ai-key-vault-word-queue-v3',
        'auth': 'server-pbkdf2-login',
        'conversation_sync': '15-minute-or-23:00-second-latest-completed',
        'ai': 'deepseek-chat-completions',
        'ai_key_storage': 'aes-256-gcm-server-vault',
        'word_enrichment': 'server-owned-30-second-retry-queue',
        'obsidian': 'server-data-vault-markdown',
        'feishu': 'recording-webhook-transcript',
      });
    });

    // ---------- Users & Session ----------

    router.get('/api/users/current', (Request request) async {
      final user = await db.currentUser();
      return _json({'user': user?.toMap()});
    });

    router.get('/api/users/credential', (Request request) async {
      final email = request.url.queryParameters['email'];
      if (email == null || email.trim().isEmpty) {
        return Response.badRequest(body: 'email is required');
      }
      final credential = await db.credentialForEmail(email);
      if (credential == null) {
        return Response.notFound('Not Found');
      }
      return _json({
        'user': credential.user.toMap(),
        'password_hash': credential.passwordHash,
        'password_salt': credential.passwordSalt,
      });
    });

    router.get('/api/users/by-email', (Request request) async {
      final email = request.url.queryParameters['email'];
      if (email == null || email.trim().isEmpty) {
        return Response.badRequest(body: 'email is required');
      }
      final credential = await db.credentialForEmail(email);
      return _json({'user': credential?.user.toMap()});
    });

    router.post('/api/auth/login', (Request request) async {
      final payload = await _readJson(request);
      final email = (payload['email'] as String? ?? '').trim().toLowerCase();
      final password = payload['password'] as String? ?? '';
      if (email.isEmpty || password.isEmpty) {
        return Response.badRequest(body: 'email and password are required');
      }
      final security = await db.loginSecurityForEmail(email);
      if (security.remainingAt(DateTime.now()) > Duration.zero) {
        return Response(
          429,
          body: jsonEncode({'error': '登录保护已锁定', ...security.toMap()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final credential = await db.credentialForEmail(email);
      final valid =
          credential != null &&
          credential.passwordHash.isNotEmpty &&
          await _passwordHasher.verify(
            password: password,
            expectedHash: credential.passwordHash,
            encodedSalt: credential.passwordSalt,
          );
      if (!valid) {
        final failed = await db.recordFailedLogin(email);
        return Response(
          401,
          body: jsonEncode({'error': '邮箱或密码不正确', ...failed.toMap()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      await db.clearFailedLogins(email);
      await db.setCurrentUser(credential.user.id);
      return _json({'user': credential.user.toMap()});
    });

    router.get('/api/users/external', (Request request) async {
      final provider = request.url.queryParameters['provider'];
      final subject = request.url.queryParameters['subject'];
      if (provider == null || subject == null) {
        return Response.badRequest(body: 'provider and subject are required');
      }
      final user = await db.userForExternalAccount(
        provider: provider,
        subject: subject,
      );
      return _json({'user': user?.toMap()});
    });

    router.post('/api/users', (Request request) async {
      final payload = await _readJson(request);
      try {
        final user = await db.createUser(
          email: (payload['email'] as String? ?? '').trim().toLowerCase(),
          displayName: (payload['display_name'] as String? ?? '').trim(),
          passwordHash: payload['password_hash'] as String? ?? '',
          passwordSalt: payload['password_salt'] as String? ?? '',
        );
        return _json({'user': user.toMap()});
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/users/external', (Request request) async {
      final payload = await _readJson(request);
      try {
        final user = await db.createExternalUser(
          provider: (payload['provider'] as String? ?? '').trim().toLowerCase(),
          subject: (payload['subject'] as String? ?? '').trim(),
          email: (payload['email'] as String? ?? '').trim().toLowerCase(),
          displayName: (payload['display_name'] as String? ?? '').trim(),
        );
        return _json({'user': user.toMap()});
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/session/current', (Request request) async {
      final payload = await _readJson(request);
      final userId = (payload['user_id'] as num?)?.toInt();
      if (userId == null) {
        return Response.badRequest(body: 'user_id is required');
      }
      await db.setCurrentUser(userId);
      return _json({'ok': true});
    });

    router.post('/api/session/clear', (Request request) async {
      await db.clearSession();
      return _json({'ok': true});
    });

    router.post('/api/users/<userId>/seed', (
      Request request,
      String userId,
    ) async {
      await db.seedStarterData(int.parse(userId));
      return _json({'ok': true});
    });

    // ---------- Login Security ----------

    router.get('/api/login-security/<email>', (
      Request request,
      String email,
    ) async {
      final state = await db.loginSecurityForEmail(email);
      return _json(state.toMap());
    });

    router.post('/api/login-security/<email>/failed', (
      Request request,
      String email,
    ) async {
      final state = await db.recordFailedLogin(email);
      return _json(state.toMap());
    });

    router.post('/api/login-security/<email>/clear', (
      Request request,
      String email,
    ) async {
      await db.clearFailedLogins(email);
      return _json({'ok': true});
    });

    // ---------- AI Settings ----------

    router.get('/api/settings/ai', (Request request) async {
      final configured = await db.aiApiKeyConfigured();
      return _json({
        'enabled': configured ? (await db.aiSettings()).enabled : false,
        // Provider credentials are decrypted only inside server-side AI jobs
        // and are never returned to Android, Windows, logs, or OpenClaw.
        'api_key_configured': configured,
        'api_key_hint': await db.aiApiKeyHint(),
        'encryption_ready': db.secretVaultReady,
        'encryption': 'AES-256-GCM',
        'model': configured
            ? (await db.aiSettings()).model
            : AiConnectionSettings.defaultModel,
      });
    });

    router.post('/api/settings/ai', (Request request) async {
      final payload = await _readJson(request);
      try {
        await db.saveAiSettings(
          AiConnectionSettings(
            enabled: payload['enabled'] == true,
            apiKey: (payload['api_key'] as String? ?? '').trim(),
            model: (payload['model'] as String? ?? '').trim(),
          ),
          clearApiKey: payload['clear_api_key'] == true,
        );
        final configured = await db.aiApiKeyConfigured();
        if (configured && payload['enabled'] == true) {
          unawaited(pendingWordProcessor.runAll());
        }
        return _json({
          'ok': true,
          'api_key_configured': configured,
          'encryption_ready': db.secretVaultReady,
        });
      } catch (error) {
        return _json({
          'error': 'AI 设置未保存：$error',
          'encryption_ready': db.secretVaultReady,
        }, statusCode: 503);
      }
    });

    router.post('/api/settings/ai/test', (Request request) async {
      final payload = await _readJson(request);
      final candidate = (payload['api_key'] as String? ?? '').trim();
      try {
        final stored = await db.aiSettings();
        final settings = AiConnectionSettings(
          enabled: payload['enabled'] is bool
              ? payload['enabled'] == true
              : stored.enabled,
          apiKey: candidate.isEmpty ? stored.apiKey : candidate,
          model: (payload['model'] as String? ?? '').trim().isEmpty
              ? stored.model
              : (payload['model'] as String).trim(),
        );
        final probe = await aiService.testConnection(settings);
        return _json({'ok': probe.ok, 'message': probe.message});
      } catch (error) {
        return _json({'ok': false, 'message': 'DeepSeek 连接失败：$error'});
      }
    });

    // ---------- Words ----------

    router.get('/api/words/<userId>', (Request request, String userId) async {
      final words = await db.wordsForUser(int.parse(userId));
      return _json(words.map((w) => w.toMap()).toList());
    });

    router.post('/api/words/<userId>', (Request request, String userId) async {
      final payload = await _readJson(request);
      final rawWords = (payload['words'] as List<dynamic>?) ?? const [];
      final parsed = <ParsedWord>[
        for (final raw in rawWords)
          if (raw is Map<String, dynamic>)
            ParsedWord(
              word: (raw['word'] as String? ?? '').trim(),
              phonetic: (raw['phonetic'] as String? ?? '').trim(),
              partOfSpeech: (raw['part_of_speech'] as String? ?? '').trim(),
              translation: (raw['translation'] as String? ?? '').trim(),
              exampleEnglish: (raw['example_en'] as String? ?? '').trim(),
              exampleChinese: (raw['example_zh'] as String? ?? '').trim(),
            ),
      ];
      final inserted = await db.insertWords(
        userId: int.parse(userId),
        words: parsed,
      );
      if (inserted > 0) pendingWordWorker?.wakeUp();
      return _json({'inserted': inserted});
    });

    router.get('/api/words/<userId>/pending', (
      Request request,
      String userId,
    ) async {
      final pending = await db.pendingWordCount(int.parse(userId));
      return _json({
        'status': pending == 0 ? 'idle' : 'queued',
        'pending_count': pending,
        'retry_interval_seconds': 30,
      });
    });

    router.post('/api/words/<userId>/enrich-pending', (
      Request request,
      String userId,
    ) async {
      final parsedUserId = int.parse(userId);
      final payload = await _readJson(request);
      if (payload['background'] == true) {
        final pending = await db.pendingWordCount(parsedUserId);
        if (pending > 0) pendingWordWorker?.wakeUp();
        unawaited(pendingWordProcessor.runForUser(parsedUserId));
        return _json({
          'status': pending == 0 ? 'idle' : 'queued',
          'pending_count': pending,
          'requested_count': 0,
          'enriched_count': 0,
          'message': pending == 0
              ? '没有待 AI 补全的词条。'
              : '服务器已接管后台补全；每 30 秒自动检查一次。',
          'checked_at': DateTime.now().toIso8601String(),
          'retry_interval_seconds': 30,
        });
      }
      final result = await pendingWordProcessor.runForUser(parsedUserId);
      return _json(result.toMap());
    });

    router.post('/api/words/<userId>/review', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      final rawWord = (payload['word'] as Map<String, dynamic>?) ?? const {};
      final rawSchedule =
          (payload['schedule'] as Map<String, dynamic>?) ?? const {};
      final rating =
          ReviewRating.values[(payload['rating'] as num?)?.toInt() ?? 0];
      await db.recordReview(
        userId: int.parse(userId),
        word: StudyWord.fromMap(rawWord),
        rating: rating,
        schedule: ReviewSchedule(
          intervalDays: (rawSchedule['interval_days'] as num?)?.toInt() ?? 0,
          mastery: (rawSchedule['mastery'] as num?)?.toInt() ?? 0,
          dueAt: DateTime.parse(
            rawSchedule['due_at'] as String? ??
                DateTime.now().toIso8601String(),
          ),
        ),
      );
      return _json({'ok': true});
    });

    // ---------- Notes ----------

    router.get('/api/notes/<userId>', (Request request, String userId) async {
      final notes = await db.notesForUser(int.parse(userId));
      return _json(notes.map((n) => n.toMap()).toList());
    });

    router.post('/api/notes/<userId>', (Request request, String userId) async {
      final payload = await _readJson(request);
      await db.addNote(
        userId: int.parse(userId),
        title: (payload['title'] as String? ?? '').trim(),
        contentEnglish: (payload['content_en'] as String? ?? '').trim(),
        contentChinese: (payload['content_zh'] as String? ?? '').trim(),
        source: (payload['source'] as String? ?? '').trim(),
      );
      return _json({'ok': true});
    });

    // ---------- Adaptive course and chapter quizzes ----------

    router.get('/api/course/<userId>', (Request request, String userId) async {
      final chapters = await db.courseChapters(int.parse(userId));
      return _json(chapters.map((chapter) => chapter.toMap()).toList());
    });

    router.get('/api/course/<userId>/daily-plan', (
      Request request,
      String userId,
    ) async {
      final id = int.parse(userId);
      final chapters = await db.courseChapters(id);
      final target = chapters.firstWhere(
        (chapter) => chapter.status != CourseChapterStatus.locked,
        orElse: () => chapters.first,
      );
      final notes = await db.notesForUser(id);
      final words = await db.wordsForUser(id);
      final settings = await db.aiSettings();
      final context = jsonEncode({
        'learner_baseline': {
          'statistics': 'AP Statistics beginner',
          'calculus': 'not started',
          'long_term_goal':
              '18-month path from AP Statistics to a small language model and DeepSeek V4-Pro principles',
        },
        'target_chapter': target.toMap(),
        'course_progress': [
          for (final chapter in chapters)
            {
              'chapter_id': chapter.chapterId,
              'status': chapter.status.name,
              'mastery': chapter.mastery,
              'attempts': chapter.attempts,
              'last_score': chapter.lastScore,
            },
        ],
        'low_mastery_words': [
          for (final word in words.where((word) => word.mastery < 2).take(12))
            {'word': word.word, 'mastery': word.mastery},
        ],
        // Only compact learning-note summaries are included. Raw email bodies
        // and complete conversation transcripts are intentionally excluded.
        'learning_note_summaries': [
          for (final note in notes.take(8))
            {
              'title': note.title,
              'summary': note.contentChinese.length > 500
                  ? note.contentChinese.substring(0, 500)
                  : note.contentChinese,
              'source': note.source,
            },
        ],
      });

      if (settings.ready) {
        try {
          final raw = await aiService.completeText(
            settings: settings,
            prompt: _dailyPlanPrompt(context),
          );
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final plan = _coursePlanFromAi(
              Map<String, dynamic>.from(decoded),
              target,
            );
            return _json(plan.toMap());
          }
        } catch (_) {
          // A local plan is safer than making the course page fail when the
          // provider is temporarily unavailable or returns malformed JSON.
        }
      }
      return _json(_fallbackCoursePlan(target).toMap());
    });

    router.post('/api/course/<userId>/<chapterId>/attempt', (
      Request request,
      String userId,
      String chapterId,
    ) async {
      final payload = await _readJson(request);
      final rawAnswers = payload['answers'];
      if (rawAnswers is! Map) {
        return Response.badRequest(body: 'answers is required');
      }
      final answers = <String, int>{};
      for (final entry in rawAnswers.entries) {
        final value = entry.value;
        if (value is num) answers[entry.key.toString()] = value.toInt();
      }
      try {
        final result = await db.submitCourseAttempt(
          userId: int.parse(userId),
          chapterId: chapterId,
          answers: answers,
        );
        return _json({
          'chapter_id': result.chapterId,
          'score': result.score,
          'passed': result.passed,
          'message': result.message,
          'wrong_question_ids': result.wrongQuestionIds,
          'next_chapter_id': result.nextChapterId,
        });
      } on StateError catch (error) {
        return Response.badRequest(body: error.message);
      }
    });

    // ---------- ChatGPT conversation auto-sync ----------

    router.get('/api/conversation-sync/<userId>', (
      Request request,
      String userId,
    ) async {
      final state = await db.conversationSyncState(int.parse(userId));
      return _json({'state': state.toMap()});
    });

    router.post('/api/conversation-sync/<userId>', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      final current = await db.conversationSyncState(int.parse(userId));
      final state = current.copyWith(
        enabled: payload['enabled'] is bool
            ? payload['enabled'] as bool
            : current.enabled,
        scheduleConfigured: payload['schedule_configured'] is bool
            ? payload['schedule_configured'] as bool
            : current.scheduleConfigured,
        lastNightlyRunAt:
            DateTime.tryParse(
              payload['last_nightly_run_at']?.toString() ?? '',
            ) ??
            current.lastNightlyRunAt,
        status: current.status,
        lastError: payload['last_error'] as String?,
      );
      await db.saveConversationSyncState(
        userId: int.parse(userId),
        state: state,
      );
      return _json({'ok': true, 'state': state.toMap()});
    });

    router.get('/api/conversation-sync/<userId>/inbox', (
      Request request,
      String userId,
    ) async {
      final conversations = await db.conversationInbox(int.parse(userId));
      return _json(conversations.map((item) => item.toMap()).toList());
    });

    // A ChatGPT web companion/bridge posts snapshots here. It must include
    // the newest conversation as well as the previous one so the client can
    // deliberately select index 1 and avoid an in-progress latest chat.
    router.post('/api/conversation-sync/<userId>/inbox', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      final raw = payload['conversations'];
      final conversations = <ChatGptConversationSnapshot>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final map = Map<String, Object?>.from(item);
          final externalId = (map['external_id'] ?? map['id'])
              ?.toString()
              .trim();
          final title = (map['title'] ?? 'ChatGPT 对话').toString();
          final transcript = (map['transcript'] ?? map['content'])?.toString();
          final updatedAt = DateTime.tryParse(
            (map['updated_at'] ?? map['updatedAt'])?.toString() ?? '',
          );
          if (externalId == null ||
              externalId.isEmpty ||
              transcript == null ||
              transcript.trim().isEmpty ||
              updatedAt == null) {
            continue;
          }
          conversations.add(
            ChatGptConversationSnapshot(
              externalId: externalId,
              title: title,
              transcript: transcript,
              updatedAt: updatedAt,
              isComplete:
                  map['is_complete'] == true ||
                  map['isComplete'] == true ||
                  map['is_complete']?.toString() == '1',
            ),
          );
        }
      }
      final accepted = await db.ingestConversationInbox(
        userId: int.parse(userId),
        conversations: conversations,
      );
      return _json({'accepted': accepted});
    });

    router.post('/api/conversation-sync/<userId>/complete', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      final conversationId = (payload['conversation_id'] as String? ?? '')
          .trim();
      final title = (payload['title'] as String? ?? 'ChatGPT 对话').trim();
      final syncedAt = DateTime.tryParse(payload['synced_at'] as String? ?? '');
      if (conversationId.isEmpty || syncedAt == null) {
        return Response.badRequest(
          body: 'conversation_id and synced_at are required',
        );
      }
      await db.markConversationSynced(
        userId: int.parse(userId),
        conversationId: conversationId,
        title: title,
        syncedAt: syncedAt,
      );
      return _json({'ok': true});
    });

    // Feishu recording bridge/webhook. The recording-ready event may only
    // identify the recording, so a small bridge can resolve its transcript
    // and retry this endpoint with `transcript`.
    router.post('/api/feishu/<userId>/webhook', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      final isUrlVerification =
          payload['type']?.toString() == 'url_verification';
      if (isUrlVerification) {
        // Feishu's URL verification uses the token issued by the Feishu
        // developer console. It is different from the token used by our
        // transcript bridge, so validate it separately when configured.
        if (!_feishuVerificationAuthorized(payload)) {
          return Response(401, body: 'Invalid Feishu verification token');
        }
      } else if (!_feishuWebhookAuthorized(request, payload)) {
        return Response(401, body: 'Invalid Feishu webhook token');
      }
      final challenge = payload['challenge']?.toString();
      if (isUrlVerification && challenge != null && challenge.isNotEmpty) {
        return _json({'challenge': challenge});
      }

      final event = payload['event'] is Map
          ? Map<String, dynamic>.from(payload['event'] as Map)
          : const <String, dynamic>{};
      final transcript = _firstNonEmpty([
        payload['transcript'],
        payload['text'],
        event['transcript'],
        event['text'],
        event['recognition_text'],
      ]);
      final recordingId = _firstNonEmpty([
        payload['recording_id'],
        payload['id'],
        event['recording_id'],
        event['id'],
        event['meeting'] is Map ? (event['meeting'] as Map)['id'] : null,
      ]);
      if (transcript.isEmpty) {
        return _json({
          'ok': true,
          'accepted': false,
          'recording_id': recordingId,
          'message': '录音事件已收到，但需要转写文本后再生成 Note。',
        });
      }
      if (transcript.length > 100000) {
        return Response.badRequest(body: 'transcript is too long');
      }

      final settings = await db.aiSettings();
      if (!settings.ready) {
        return Response(503, body: 'DeepSeek is not configured on the server');
      }
      final title = _firstNonEmpty([
        payload['title'],
        event['title'],
        '飞书录音 Note',
      ]);
      try {
        final summary = await _summarizeFeishuRecording(
          settings: settings,
          title: title,
          transcript: transcript,
        );
        final summaryChinese = _stringOr(
          summary['summaryChinese'],
          '已生成飞书录音摘要。',
        );
        final summaryEnglish = _stringOr(
          summary['summaryEnglish'],
          'Feishu recording summarized for later review.',
        );
        final concepts = _stringList(summary['learnedConcepts']);
        final actions = _stringList(summary['actionItems']);
        final contentChinese = [
          summaryChinese,
          if (concepts.isNotEmpty)
            '学习要点：\n${concepts.map((item) => '- $item').join('\n')}',
          if (actions.isNotEmpty)
            '待处理：\n${actions.map((item) => '- $item').join('\n')}',
        ].join('\n\n');
        final updatedAt =
            DateTime.tryParse(
              _firstNonEmpty([
                payload['created_at'],
                event['created_at'],
                payload['updated_at'],
              ]),
            ) ??
            DateTime.now().toUtc();
        final sourceId =
            'feishu-${recordingId.isEmpty ? updatedAt.microsecondsSinceEpoch : recordingId}';
        final words = _parsedWords(summary['words']);
        if (words.isNotEmpty) {
          await db.insertWords(userId: int.parse(userId), words: words);
          pendingWordWorker?.wakeUp();
        }
        final summaryTitle = _stringOr(summary['title'], title);
        await db.addNote(
          userId: int.parse(userId),
          title: summaryTitle,
          contentEnglish: summaryEnglish,
          contentChinese: contentChinese,
          source: '飞书录音豆自动同步',
        );
        await db.saveObsidianEntry(
          userId: int.parse(userId),
          title: summaryTitle,
          contentEnglish: summaryEnglish,
          contentChinese: contentChinese,
          source: '飞书录音豆自动同步',
          category: _stringOr(summary['category'], 'Recording'),
          tags: [..._stringList(summary['tags']), 'feishu', 'recording'],
          sourceId: sourceId,
          updatedAt: updatedAt,
        );
        return _json({
          'ok': true,
          'accepted': true,
          'title': summaryTitle,
          'source_id': sourceId,
          'inserted_words': words.length,
        });
      } catch (error) {
        return Response.internalServerError(
          body: 'Feishu recording failed: $error',
        );
      }
    });

    router.post('/api/obsidian/entries/<userId>', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      final rawTags = payload['tags'];
      final tags = rawTags is List
          ? rawTags.map((item) => item.toString()).toList(growable: false)
          : const <String>[];
      final updatedAt = DateTime.tryParse(
        payload['updated_at'] as String? ?? '',
      );
      final sourceId = (payload['source_id'] as String? ?? '').trim();
      if (sourceId.isEmpty || updatedAt == null) {
        return Response.badRequest(
          body: 'source_id and updated_at are required',
        );
      }
      await db.saveObsidianEntry(
        userId: int.parse(userId),
        title: (payload['title'] as String? ?? '自动摘要').trim(),
        contentEnglish: (payload['content_en'] as String? ?? '').trim(),
        contentChinese: (payload['content_zh'] as String? ?? '').trim(),
        source: (payload['source'] as String? ?? '').trim(),
        category: (payload['category'] as String? ?? 'Inbox').trim(),
        tags: tags,
        sourceId: sourceId,
        updatedAt: updatedAt,
      );
      return _json({'ok': true, 'vault': 'server/data/obsidian-vault/$userId'});
    });

    // ---------- Outlook / QQ mail auto-summary ----------

    router.get('/api/email-sync/<userId>/<provider>', (
      Request request,
      String userId,
      String provider,
    ) async {
      final emailProvider = _emailProvider(provider);
      if (emailProvider == null) return Response.notFound('Unknown provider');
      final state = await db.emailSyncState(
        userId: int.parse(userId),
        provider: emailProvider,
      );
      return _json({'state': state.toMap()});
    });

    router.post('/api/email-sync/<userId>/<provider>', (
      Request request,
      String userId,
      String provider,
    ) async {
      final emailProvider = _emailProvider(provider);
      if (emailProvider == null) return Response.notFound('Unknown provider');
      final payload = await _readJson(request);
      final current = await db.emailSyncState(
        userId: int.parse(userId),
        provider: emailProvider,
      );
      final state = current.copyWith(
        enabled: payload['enabled'] is bool
            ? payload['enabled'] as bool
            : current.enabled,
        status: current.status,
        lastError: payload['last_error'] as String?,
      );
      await db.saveEmailSyncState(userId: int.parse(userId), state: state);
      return _json({'ok': true, 'state': state.toMap()});
    });

    router.get('/api/email-sync/<userId>/<provider>/inbox', (
      Request request,
      String userId,
      String provider,
    ) async {
      final emailProvider = _emailProvider(provider);
      if (emailProvider == null) return Response.notFound('Unknown provider');
      final messages = await db.emailInbox(
        userId: int.parse(userId),
        provider: emailProvider,
      );
      return _json(messages.map((item) => item.toMap()).toList());
    });

    // Outlook OAuth and QQ IMAP/Bridge adapters post normalized messages here.
    router.post('/api/email-sync/<userId>/<provider>/inbox', (
      Request request,
      String userId,
      String provider,
    ) async {
      final emailProvider = _emailProvider(provider);
      if (emailProvider == null) return Response.notFound('Unknown provider');
      final payload = await _readJson(request);
      final rawMessages = payload['messages'];
      final messages = <EmailMessageSnapshot>[];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is! Map) continue;
          final map = Map<String, Object?>.from(item);
          final externalId = (map['external_id'] ?? map['id'])
              ?.toString()
              .trim();
          final receivedAt = DateTime.tryParse(
            (map['received_at'] ?? map['receivedAt'])?.toString() ?? '',
          );
          final body = (map['body'] ?? map['content'])?.toString();
          if (externalId == null ||
              externalId.isEmpty ||
              receivedAt == null ||
              body == null ||
              body.trim().isEmpty) {
            continue;
          }
          messages.add(
            EmailMessageSnapshot(
              externalId: externalId,
              provider: emailProvider,
              subject: (map['subject'] ?? '(无主题)').toString(),
              sender: (map['sender'] ?? map['from'] ?? '').toString(),
              recipients: (map['recipients'] ?? map['to'] ?? '').toString(),
              body: body,
              receivedAt: receivedAt,
              isComplete:
                  map['is_complete'] == true ||
                  map['isComplete'] == true ||
                  map['is_complete']?.toString() == '1',
            ),
          );
        }
      }
      final accepted = await db.ingestEmailInbox(
        userId: int.parse(userId),
        provider: emailProvider,
        messages: messages,
      );
      return _json({'accepted': accepted});
    });

    router.post('/api/email-sync/<userId>/<provider>/complete', (
      Request request,
      String userId,
      String provider,
    ) async {
      final emailProvider = _emailProvider(provider);
      if (emailProvider == null) return Response.notFound('Unknown provider');
      final payload = await _readJson(request);
      final messageId = (payload['message_id'] as String? ?? '').trim();
      final subject = (payload['subject'] as String? ?? '(无主题)').trim();
      final syncedAt = DateTime.tryParse(payload['synced_at'] as String? ?? '');
      if (messageId.isEmpty || syncedAt == null) {
        return Response.badRequest(
          body: 'message_id and synced_at are required',
        );
      }
      await db.markEmailSynced(
        userId: int.parse(userId),
        provider: emailProvider,
        messageId: messageId,
        subject: subject,
        syncedAt: syncedAt,
      );
      return _json({'ok': true});
    });

    // ---------- Captures ----------

    router.get('/api/captures/<userId>', (
      Request request,
      String userId,
    ) async {
      final captures = await db.capturesForUser(int.parse(userId));
      return _json(captures.map((c) => c.toMap()).toList());
    });

    router.post('/api/captures/<userId>', (
      Request request,
      String userId,
    ) async {
      final payload = await _readJson(request);
      await db.addCapture(
        userId: int.parse(userId),
        fileName: (payload['file_name'] as String? ?? '').trim(),
        filePath: (payload['file_path'] as String? ?? '').trim(),
        kind: (payload['kind'] as String? ?? '').trim(),
      );
      return _json({'ok': true});
    });

    // ---------- Stats ----------

    router.get('/api/stats/<userId>/today', (
      Request request,
      String userId,
    ) async {
      final stats = await db.todayStats(int.parse(userId));
      return _json(stats.toMap());
    });

    router.post('/api/stats/<userId>/checkin', (
      Request request,
      String userId,
    ) async {
      await db.markCheckedIn(int.parse(userId));
      return _json({'ok': true});
    });

    // ---------- AI Proxy ----------

    router.post('/api/ai/chat', (Request request) async {
      final payload = await _readJson(request);
      final prompt = payload['prompt'] as String? ?? '';

      try {
        final result = await aiService.completeText(
          settings: await db.aiSettings(),
          prompt: prompt,
        );
        return _json({'result': result});
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    return router;
  }

  Response _json(Object body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final text = await request.readAsString();
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  EmailProvider? _emailProvider(String value) {
    final normalized = value.trim().toLowerCase();
    for (final provider in EmailProvider.values) {
      if (provider.apiValue == normalized) return provider;
    }
    return null;
  }

  String _dailyPlanPrompt(String context) {
    return '''Create one small, realistic daily study plan for a complete beginner.
Use the learner context below, but treat it as learning evidence rather than unquestioned truth.
The plan must stay inside the target chapter and fit roughly 25-40 minutes.
Return JSON only with exactly these keys:
{
  "title": "short Chinese title",
  "phase": "course phase",
  "chapter_id": "the target chapter id",
  "rationale": "one or two Chinese sentences explaining the personalization",
  "tasks": ["3-5 concrete tasks in Chinese"],
  "test_focus": ["2-4 concepts the chapter test should check"]
}
Do not invent a later chapter, do not expose private details, and do not include markdown fences.

Learner context:
$context''';
  }

  CourseDailyPlan _coursePlanFromAi(
    Map<String, dynamic> map,
    CourseChapter target,
  ) {
    List<String> strings(Object? value, {int limit = 5}) {
      if (value is! List) return const [];
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .take(limit)
          .toList(growable: false);
    }

    final tasks = strings(map['tasks']);
    final focus = strings(map['test_focus'], limit: 4);
    final title = map['title']?.toString().trim() ?? '';
    final rationale = map['rationale']?.toString().trim() ?? '';
    return CourseDailyPlan(
      generatedAt: DateTime.now().toUtc(),
      title: title.isEmpty ? '今日：${target.title}' : title,
      phase: target.phase,
      chapterId: target.chapterId,
      rationale: rationale.isEmpty ? '根据当前解锁章节和学习记录安排今天的最小学习单元。' : rationale,
      tasks: tasks.isEmpty ? _fallbackCoursePlan(target).tasks : tasks,
      testFocus: focus.isEmpty ? target.objectives.take(4).toList() : focus,
      aiGenerated: true,
      source: 'deepseek',
    );
  }

  CourseDailyPlan _fallbackCoursePlan(CourseChapter target) {
    return CourseDailyPlan(
      generatedAt: DateTime.now().toUtc(),
      title: '今日：${target.title}',
      phase: target.phase,
      chapterId: target.chapterId,
      rationale: 'AI 暂不可用，先按你的当前解锁章节安排一个可完成的本地计划。',
      tasks: [
        '阅读本章讲解并用自己的话写下一个关键概念。',
        '完成一个对应的小实验或手算例题。',
        '完成本章选择题测试；低于 80% 时记录错题并明天重做。',
      ],
      testFocus: target.objectives.take(4).toList(growable: false),
      aiGenerated: false,
      source: 'local-fallback',
    );
  }

  bool _feishuWebhookAuthorized(Request request, Map<String, dynamic> payload) {
    final bridgeToken = Platform.environment['FEISHU_WEBHOOK_TOKEN']?.trim();
    final verificationToken = Platform.environment['FEISHU_VERIFICATION_TOKEN']
        ?.trim();
    if ((bridgeToken == null || bridgeToken.isEmpty) &&
        (verificationToken == null || verificationToken.isEmpty)) {
      return true;
    }
    final header = payload['header'] is Map
        ? Map<String, dynamic>.from(payload['header'] as Map)
        : const <String, dynamic>{};
    final supplied =
        request.headers['x-feishu-webhook-token']?.trim() ??
        request.headers['x-feishu-verification-token']?.trim() ??
        payload['token']?.toString().trim() ??
        header['token']?.toString().trim() ??
        header['verification_token']?.toString().trim() ??
        '';
    return (bridgeToken != null &&
            bridgeToken.isNotEmpty &&
            supplied == bridgeToken) ||
        (verificationToken != null &&
            verificationToken.isNotEmpty &&
            supplied == verificationToken);
  }

  bool _feishuVerificationAuthorized(Map<String, dynamic> payload) {
    final configured = Platform.environment['FEISHU_VERIFICATION_TOKEN']
        ?.trim();
    // If no Feishu verification token was configured, keep the challenge
    // compatible with the previous deployment and let the developer console
    // complete URL verification. Production deployments should configure it.
    if (configured == null || configured.isEmpty) return true;
    final header = payload['header'] is Map
        ? Map<String, dynamic>.from(payload['header'] as Map)
        : const <String, dynamic>{};
    final supplied =
        payload['token']?.toString().trim() ??
        header['token']?.toString().trim() ??
        header['verification_token']?.toString().trim() ??
        '';
    return supplied == configured;
  }

  String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  Future<Map<String, dynamic>> _summarizeFeishuRecording({
    required AiConnectionSettings settings,
    required String title,
    required String transcript,
  }) async {
    final raw = await aiService.completeText(
      settings: settings,
      prompt:
          '''Summarize this Feishu recording for a Chinese learner's personal knowledge base.
Return JSON only with these keys: title, category, tags, summaryEnglish, summaryChinese, learnedConcepts, actionItems, words.
Keep the summary concise and do not include the original transcript.
category should be Recording, Learning, Work, Personal, or Inbox.
tags should be 1-5 short lowercase tags.
words should only contain useful English words actually present in the transcript; each word must have word, phonetic, partOfSpeech, translation, exampleEnglish, exampleChinese.
Never output passwords, API keys, email addresses, phone numbers, or other personal identifiers.

Recording title: $title
Transcript:
$transcript''',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Feishu summary JSON is invalid');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _stringOr(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  List<String> _stringList(Object? value, {int limit = 8}) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(limit)
        .toList(growable: false);
  }

  List<ParsedWord> _parsedWords(Object? value) {
    if (value is! List) return const [];
    final words = <ParsedWord>[];
    for (final item in value.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final word = map['word']?.toString().trim() ?? '';
      if (word.isEmpty) continue;
      words.add(
        ParsedWord(
          word: word,
          phonetic: _stringOr(map['phonetic'], '待生成'),
          partOfSpeech: _stringOr(map['partOfSpeech'], '待识别'),
          translation: _stringOr(map['translation'], '待 AI 翻译'),
          exampleEnglish: _stringOr(map['exampleEnglish'], ''),
          exampleChinese: _stringOr(map['exampleChinese'], ''),
        ),
      );
    }
    return words.take(20).toList(growable: false);
  }
}
