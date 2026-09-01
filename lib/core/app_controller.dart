import 'dart:async';

import 'package:flutter/widgets.dart';

import 'ai/ai_service.dart';
import 'codex/chatgpt_auth_service.dart';
import '../data/app_database.dart';
import '../domain/auto_note_schedule.dart';
import '../domain/learning_engine.dart';
import '../domain/models.dart';
import '../domain/security_policy.dart';
import '../domain/word_parser.dart';
import 'security/password_hasher.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController(
    this._database,
    this._passwordHasher, [
    AiService? aiService,
    ChatGptAuthService? chatGptAuthService,
  ]) : _aiService = aiService ?? const NoopAiService(),
       _chatGptAuthService =
           chatGptAuthService ?? const NoopChatGptAuthService();

  final AppDatabase _database;
  final PasswordHasher _passwordHasher;
  final AiService _aiService;
  final ChatGptAuthService _chatGptAuthService;

  AppUser? _currentUser;
  List<StudyWord> _words = const [];
  List<StudyNote> _notes = const [];
  List<CapturedDocument> _captures = const [];
  List<CourseChapter> _courseChapters = const [];
  CourseDailyPlan? _courseDailyPlan;
  TodayStats _todayStats = const TodayStats.empty();
  LoginSecurityState _loginSecurity = const LoginSecurityState.clear();
  AiConnectionSettings _aiSettings = AiConnectionSettings.empty;
  ChatGptAuthState _chatGptAuth = const ChatGptAuthState.unavailable();
  ChatGptCodexQuotaState _codexQuota =
      const ChatGptCodexQuotaState.unavailable();
  CodexHistorySyncState _codexHistory = const CodexHistorySyncState.idle();
  ConversationSyncState _conversationSyncState =
      ConversationSyncState.defaultState;
  Map<EmailProvider, EmailSyncState> _emailSyncStates = {
    for (final provider in EmailProvider.values)
      provider: EmailSyncState.defaultFor(provider),
  };
  Timer? _conversationSyncTimer;
  Timer? _codexRealtimeTimer;
  Timer? _pendingWordEnrichmentTimer;
  final Set<EmailProvider> _emailSyncBusy = {};
  bool _conversationSyncBusy = false;
  bool _codexRealtimeBusy = false;
  bool _nightlySyncBusy = false;
  bool _conversationSyncBackendAvailable = true;
  bool _pendingWordEnrichmentBusy = false;
  bool _pendingWordBackendAvailable = true;
  PendingWordEnrichmentState _pendingWordEnrichmentState =
      PendingWordEnrichmentState.idle;
  bool _busy = false;
  DateTime? _lastCodexQuotaRefreshAt;

  AppUser? get currentUser => _currentUser;
  List<StudyWord> get words => _words;
  List<StudyNote> get notes => _notes;
  List<CapturedDocument> get captures => _captures;
  List<CourseChapter> get courseChapters => _courseChapters;
  CourseDailyPlan? get courseDailyPlan => _courseDailyPlan;
  TodayStats get todayStats => _todayStats;
  LoginSecurityState get loginSecurity => _loginSecurity;
  AiConnectionSettings get aiSettings => _aiSettings;
  ChatGptAuthState get chatGptAuth => _chatGptAuth;
  ChatGptCodexQuotaState get codexQuota => _codexQuota;
  CodexHistorySyncState get codexHistory => _codexHistory;
  ConversationSyncState get conversationSyncState => _conversationSyncState;
  PendingWordEnrichmentState get pendingWordEnrichmentState =>
      _pendingWordEnrichmentState;
  EmailSyncState emailSyncState(EmailProvider provider) =>
      _emailSyncStates[provider] ?? EmailSyncState.defaultFor(provider);
  bool get chatGptSupported => _chatGptAuthService.supported;
  bool get busy => _busy;
  bool get authenticated => _currentUser != null;
  String get databasePath => _database.apiUrl;
  bool get chatGptAiReady => _chatGptAuth.authenticated;
  bool get deepSeekReady => _aiSettings.ready;
  bool get aiReady => chatGptAiReady || deepSeekReady;
  int get pendingAiWordCount =>
      _words.where((word) => word.needsAiEnrichment).length;
  String get activeAiModel => chatGptAiReady ? 'chatgpt5.5' : _aiSettings.model;
  String get activeAiProviderLabel =>
      chatGptAiReady ? 'ChatGPT / Codex' : 'DeepSeek API';

  @override
  void dispose() {
    _conversationSyncTimer?.cancel();
    _codexRealtimeTimer?.cancel();
    _pendingWordEnrichmentTimer?.cancel();
    unawaited(_chatGptAuthService.dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<StudyWord> get dueWords =>
      _words.where((word) => word.isDue).toList(growable: false);

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _aiSettings = await _database.aiSettings();
    } catch (_) {
      _aiSettings = AiConnectionSettings.empty;
    }
    try {
      _chatGptAuth = await _chatGptAuthService.read();
    } catch (error) {
      _chatGptAuth = ChatGptAuthState.unavailable('ChatGPT 登录状态读取失败：$error');
    }
    try {
      _currentUser = await _database.currentUser();
      if (_currentUser != null) {
        await _loadAutoSyncState(_currentUser!.id);
        await _reloadLearningData();
        _startConversationSyncTimer();
        _startPendingWordEnrichmentTimer();
        _startCodexRealtimeBridge();
      }
    } catch (_) {
      _currentUser = null;
    }
    notifyListeners();
  }

  /// Starts the official Codex App Server login and lets the UI present the
  /// returned browser URL/device code. The callback must not handle or store
  /// any access token; Codex keeps the managed session itself.
  Future<String?> signInWithChatGPT({
    required Future<void> Function(ChatGptLoginChallenge challenge)
    presentChallenge,
    bool deviceCode = false,
  }) async {
    return _guard(() async {
      if (!_chatGptAuthService.supported) {
        return '当前平台没有可用的 Codex App Server。Windows 端请安装 Codex；Android 端需要连接受信任的 Codex 网关。';
      }

      ChatGptLoginChallenge? challenge;
      try {
        final loginChallenge = await _chatGptAuthService.startLogin(
          deviceCode: deviceCode,
        );
        challenge = loginChallenge;
        await presentChallenge(loginChallenge);
        final state = await _chatGptAuthService.completeLogin(loginChallenge);
        _chatGptAuth = state;
        notifyListeners();
        if (!state.authenticated) {
          return state.message ?? 'ChatGPT 登录未完成。';
        }

        final subject = state.accountId?.trim();
        if (subject == null || subject.isEmpty) {
          return 'ChatGPT 登录成功，但没有返回可用于绑定本地账号的账户标识。';
        }
        final existing = await _database.userForExternalAccount(
          provider: 'chatgpt',
          subject: subject,
        );
        final user =
            existing ??
            await _database.createExternalUser(
              provider: 'chatgpt',
              subject: subject,
              email: state.email ?? '',
              displayName:
                  state.displayName ?? _displayNameFromEmail(state.email),
            );
        await _database.setCurrentUser(user.id);
        await _database.seedStarterData(user.id);
        _currentUser = user;
        await _loadAutoSyncState(user.id);
        await _reloadLearningData();
        _startConversationSyncTimer();
        _startPendingWordEnrichmentTimer();
        _startCodexRealtimeBridge(fullRefresh: true);
        return null;
      } catch (error) {
        if (challenge != null) {
          try {
            await _chatGptAuthService.cancelLogin(challenge.loginId);
          } catch (_) {
            // Best effort cancellation; preserve the original error.
          }
        }
        return 'ChatGPT 登录失败：$error';
      }
    });
  }

  Future<String?> disconnectChatGpt() async {
    return _guard(() async {
      _stopCodexRealtimeBridge();
      await _chatGptAuthService.logout();
      _chatGptAuth = _chatGptAuthService.supported
          ? const ChatGptAuthState.signedOut()
          : const ChatGptAuthState.unavailable();
      _codexQuota = const ChatGptCodexQuotaState.unavailable();
      _codexHistory = const CodexHistorySyncState.idle();
      notifyListeners();
      return null;
    });
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      return '请输入邮箱和密码。';
    }

    return _guard(() async {
      final normalizedEmail = email.trim().toLowerCase();
      _loginSecurity = await _database.loginSecurityForEmail(normalizedEmail);
      final remaining = _loginSecurity.remainingAt(DateTime.now());
      if (remaining > Duration.zero) {
        return '登录保护已锁定，请在 ${SecurityPolicy.formatRemaining(remaining)}后再试。';
      }

      AppUser user;
      try {
        user = await _database.authenticate(
          email: normalizedEmail,
          password: password,
        );
      } catch (_) {
        _loginSecurity = await _database.loginSecurityForEmail(normalizedEmail);
        return _failedLoginMessage(_loginSecurity);
      }
      _loginSecurity = const LoginSecurityState.clear();
      await _database.setCurrentUser(user.id);
      _currentUser = user;
      await _loadAutoSyncState(user.id);
      await _reloadLearningData();
      _startConversationSyncTimer();
      _startPendingWordEnrichmentTimer();
      _startCodexRealtimeBridge();
      return null;
    });
  }

  Future<String?> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (displayName.trim().length < 2) return '昵称至少需要 2 个字符。';
    if (!email.contains('@')) return '请输入有效的邮箱地址。';
    if (password.length < 8) return '密码至少需要 8 个字符。';

    return _guard(() async {
      final existing = await _database.userForEmail(email);
      if (existing != null) return '这个邮箱已经注册。';

      final digest = await _passwordHasher.hash(password);
      final user = await _database.createUser(
        email: email,
        displayName: displayName,
        passwordHash: digest.hash,
        passwordSalt: digest.salt,
      );
      await _database.setCurrentUser(user.id);
      await _database.clearFailedLogins(user.email);
      await _database.seedStarterData(user.id);
      _currentUser = user;
      await _loadAutoSyncState(user.id);
      await _reloadLearningData();
      _startConversationSyncTimer();
      _startPendingWordEnrichmentTimer();
      _startCodexRealtimeBridge();
      return null;
    });
  }

  Future<String?> enterLocalDemo() async {
    return _guard(() async {
      const email = 'demo@local.study';
      final existing = await _database.userForEmail(email);
      final AppUser user;
      if (existing == null) {
        final digest = await _passwordHasher.hash('local-demo-password');
        user = await _database.createUser(
          email: email,
          displayName: 'George',
          passwordHash: digest.hash,
          passwordSalt: digest.salt,
        );
      } else {
        user = existing;
      }
      await _database.setCurrentUser(user.id);
      await _database.clearFailedLogins(user.email);
      await _database.seedStarterData(user.id);
      _currentUser = user;
      await _loadAutoSyncState(user.id);
      await _reloadLearningData();
      _startConversationSyncTimer();
      _startPendingWordEnrichmentTimer();
      _startCodexRealtimeBridge();
      return null;
    });
  }

  Future<void> signOut() async {
    _conversationSyncTimer?.cancel();
    _conversationSyncTimer = null;
    _pendingWordEnrichmentTimer?.cancel();
    _pendingWordEnrichmentTimer = null;
    _stopCodexRealtimeBridge();
    await _database.clearSession();
    _currentUser = null;
    _words = const [];
    _notes = const [];
    _captures = const [];
    _todayStats = const TodayStats.empty();
    _conversationSyncState = ConversationSyncState.defaultState;
    _codexHistory = const CodexHistorySyncState.idle();
    _conversationSyncBackendAvailable = true;
    _pendingWordBackendAvailable = true;
    _pendingWordEnrichmentState = PendingWordEnrichmentState.idle;
    _emailSyncStates = {
      for (final provider in EmailProvider.values)
        provider: EmailSyncState.defaultFor(provider),
    };
    _loginSecurity = const LoginSecurityState.clear();
    notifyListeners();
  }

  Future<WordImportResult> importWords(String rawText) async {
    if (rawText.length > SecurityPolicy.maxWordBankCharacters) {
      throw const FormatException('单次词库文本不能超过 100,000 个字符。');
    }
    final user = _requireUser();
    final parsed = WordParser.parse(rawText);
    if (parsed.isEmpty) return const WordImportResult.empty();

    _setBusy(true);
    try {
      var enrichedCount = 0;
      String? aiWarning;
      var finalWords = parsed;

      final aiTargets = parsed
          .where(
            (word) =>
                word.translation == '待 AI 翻译' ||
                word.phonetic == '待生成' ||
                word.partOfSpeech == '待识别',
          )
          .toList(growable: false);
      if ((chatGptAiReady || _aiSettings.hasClientApiKey) &&
          aiTargets.isNotEmpty) {
        try {
          final report = await _aiService.enrichWords(
            settings: _aiSettings,
            words: aiTargets,
          );
          final enriched = <String, ParsedWord>{
            for (final word in report.words) word.word.toLowerCase(): word,
          };
          finalWords = [
            for (final word in parsed)
              enriched[word.word.toLowerCase()] ?? word,
          ];
          enrichedCount = report.enrichedCount;
          aiWarning = report.warning;
        } catch (error) {
          aiWarning = '联网补全失败：$error';
        }
      }

      final inserted = await _database.insertWords(
        userId: user.id,
        words: finalWords,
      );
      await _reloadLearningData();
      if (pendingAiWordCount > 0) {
        _pendingWordEnrichmentState = PendingWordEnrichmentState(
          status: 'queued',
          pendingCount: pendingAiWordCount,
          requestedCount: 0,
          enrichedCount: 0,
          message: '已加入服务器后台队列；每 30 秒自动检查一次。',
          retryIntervalSeconds: 30,
        );
        notifyListeners();
        unawaited(_runPendingWordEnrichment());
      }
      return WordImportResult(
        insertedCount: inserted,
        aiEnrichedCount: enrichedCount,
        aiWarning: aiWarning,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<ConversationImportResult> importConversation(String transcript) async {
    if (transcript.trim().isEmpty) {
      throw const FormatException('请先粘贴一段 AI 对话。');
    }
    if (transcript.length > SecurityPolicy.maxWordBankCharacters) {
      throw const FormatException('单次对话不能超过 100,000 个字符。');
    }
    final user = _requireUser();
    _setBusy(true);
    try {
      final analysis = await _aiService.analyzeConversation(
        settings: _aiSettings,
        transcript: transcript.trim(),
      );
      final inserted = analysis.words.isEmpty
          ? 0
          : await _database.insertWords(userId: user.id, words: analysis.words);
      final concepts = analysis.learnedConcepts.isEmpty
          ? ''
          : '\n\n学习证据 / Learned concepts:\n${analysis.learnedConcepts.map((item) => '- $item').join('\n')}';
      final actions = analysis.actionItems.isEmpty
          ? ''
          : '\n\n待复习 / Next actions:\n${analysis.actionItems.map((item) => '- $item').join('\n')}';
      final archivedAt = DateTime.now();
      final source = 'AI 对话导入 · ${archivedAt.toIso8601String()}';
      await _database.addNote(
        userId: user.id,
        title: analysis.title,
        contentEnglish:
            '${analysis.summaryEnglish}\n\n[Original AI conversation]\n${transcript.trim()}',
        contentChinese: '${analysis.summaryChinese}$concepts$actions',
        source: source,
      );
      await _database.saveObsidianEntry(
        userId: user.id,
        title: analysis.title,
        contentEnglish: analysis.summaryEnglish,
        contentChinese: '${analysis.summaryChinese}$concepts$actions',
        source: source,
        category: analysis.category,
        tags: analysis.tags,
        sourceId: 'manual-${archivedAt.microsecondsSinceEpoch}',
        updatedAt: archivedAt,
      );
      await _reloadLearningData();
      return ConversationImportResult(
        title: analysis.title,
        insertedWords: inserted,
        summaryChinese: analysis.summaryChinese,
        warning: analysis.warning,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> reviewWord(StudyWord word, ReviewRating rating) async {
    final user = _requireUser();
    final schedule = LearningEngine.schedule(word: word, rating: rating);
    await _database.recordReview(
      userId: user.id,
      word: word,
      rating: rating,
      schedule: schedule,
    );
    await _reloadLearningData();
  }

  Future<void> checkIn() async {
    final user = _requireUser();
    await _database.markCheckedIn(user.id);
    await _reloadLearningData();
  }

  Future<void> addCapture({
    required String fileName,
    required String filePath,
    required String kind,
  }) async {
    final user = _requireUser();
    await _database.addCapture(
      userId: user.id,
      fileName: fileName,
      filePath: filePath,
      kind: kind,
    );
    _captures = await _database.capturesForUser(user.id);
    notifyListeners();
  }

  Future<void> addNote({
    required String title,
    required String contentEnglish,
    required String contentChinese,
    required String source,
  }) async {
    final user = _requireUser();
    await _database.addNote(
      userId: user.id,
      title: title,
      contentEnglish: contentEnglish,
      contentChinese: contentChinese,
      source: source,
    );
    _notes = await _database.notesForUser(user.id);
    notifyListeners();
  }

  Future<String?> setConversationSyncEnabled(bool enabled) async {
    final user = _requireUser();
    return _guard(() async {
      final next = _conversationSyncState.copyWith(
        enabled: enabled,
        scheduleConfigured: true,
        status: enabled
            ? ConversationSyncStatus.waiting
            : ConversationSyncStatus.waiting,
        clearError: true,
      );
      await _database.saveConversationSyncState(userId: user.id, state: next);
      _conversationSyncState = next;
      // The switch selects high-frequency mode. Turning it off keeps the
      // daily 23:00 summary schedule active; it does not disable summaries.
      _startConversationSyncTimer(runMissedNightly: false);
      notifyListeners();
      return null;
    });
  }

  Future<String?> setEmailSyncEnabled(
    EmailProvider provider,
    bool enabled,
  ) async {
    final user = _requireUser();
    return _guard(() async {
      final next = emailSyncState(provider).copyWith(
        enabled: enabled,
        status: enabled
            ? ConversationSyncStatus.waiting
            : ConversationSyncStatus.disabled,
        clearError: true,
      );
      await _database.saveEmailSyncState(userId: user.id, state: next);
      _emailSyncStates = {..._emailSyncStates, provider: next};
      _startConversationSyncTimer(runMissedNightly: false);
      notifyListeners();
      return null;
    });
  }

  Future<EmailSyncResult> syncEmailProvider(
    EmailProvider provider, {
    bool manual = false,
    bool scheduledNightly = false,
  }) async {
    final user = _requireUser();
    final state = emailSyncState(provider);
    if (_emailSyncBusy.contains(provider)) {
      return const EmailSyncResult(synced: false, message: '邮箱同步正在进行中，请稍候。');
    }
    if (!manual && !state.enabled) {
      return EmailSyncResult(
        synced: false,
        message: '${provider.label} 自动同步已关闭。',
      );
    }
    if (!manual && !scheduledNightly && !_conversationSyncState.enabled) {
      return EmailSyncResult(
        synced: false,
        message: '高频循环未开启，将在每天 23:00 统一检查。',
      );
    }

    _emailSyncBusy.add(provider);
    final attemptAt = DateTime.now();
    final syncing = state.copyWith(
      status: ConversationSyncStatus.syncing,
      lastAttemptAt: attemptAt,
      clearError: true,
    );
    _emailSyncStates = {..._emailSyncStates, provider: syncing};
    notifyListeners();
    try {
      final messages = await _database.emailInbox(
        userId: user.id,
        provider: provider,
      );
      final candidate = messages
          .where((message) => message.isComplete)
          .firstOrNull;
      if (candidate == null) {
        return await _finishEmailSync(
          provider,
          syncing.copyWith(status: ConversationSyncStatus.waiting),
          '${provider.label} 暂无待总结的已完成邮件。',
        );
      }
      if (!aiReady) {
        const message = '请先连接 ChatGPT/Codex 或启用 DeepSeek，才能自动生成邮件摘要。';
        return await _finishEmailSync(
          provider,
          syncing.copyWith(
            status: ConversationSyncStatus.error,
            lastError: message,
          ),
          message,
        );
      }

      final analysis = await _aiService.analyzeConversation(
        settings: _aiSettings,
        transcript: _transcriptForAi(candidate.transcript),
      );
      if (analysis.warning != null) throw StateError(analysis.warning!);
      final concepts = analysis.learnedConcepts.isEmpty
          ? ''
          : '\n\n学习证据 / Learned concepts:\n${analysis.learnedConcepts.map((item) => '- $item').join('\n')}';
      final actions = analysis.actionItems.isEmpty
          ? ''
          : '\n\n待处理 / Next actions:\n${analysis.actionItems.map((item) => '- $item').join('\n')}';
      final source = '${provider.label} 自动同步';
      final title = analysis.title == 'AI 对话学习记录'
          ? candidate.subject
          : analysis.title;
      await _database.addNote(
        userId: user.id,
        title: title,
        contentEnglish:
            '${analysis.summaryEnglish}\n\n[Original email]\n${candidate.transcript}',
        contentChinese: '${analysis.summaryChinese}$concepts$actions',
        source: source,
      );
      await _database.saveObsidianEntry(
        userId: user.id,
        title: title,
        contentEnglish: analysis.summaryEnglish,
        contentChinese: '${analysis.summaryChinese}$concepts$actions',
        source: source,
        category: analysis.category,
        tags: [...analysis.tags, provider.apiValue, 'email'],
        sourceId: '${provider.apiValue}-${candidate.externalId}',
        updatedAt: candidate.receivedAt,
      );
      final syncedAt = DateTime.now();
      await _database.markEmailSynced(
        userId: user.id,
        provider: provider,
        messageId: candidate.externalId,
        subject: candidate.subject,
        syncedAt: syncedAt,
      );
      _emailSyncStates = {
        ..._emailSyncStates,
        provider: syncing.copyWith(
          status: ConversationSyncStatus.synced,
          lastSyncedAt: syncedAt,
          lastSyncedMessageId: candidate.externalId,
          lastSyncedSubject: candidate.subject,
          clearError: true,
        ),
      };
      await _reloadLearningData();
      return EmailSyncResult(
        synced: true,
        message: '${provider.label} 邮件「$title」已生成摘要并归档到 Obsidian。',
      );
    } catch (error) {
      final message = '${provider.label} 邮件同步失败：$error';
      return await _finishEmailSync(
        provider,
        syncing.copyWith(
          status: ConversationSyncStatus.error,
          lastError: message,
        ),
        message,
      );
    } finally {
      _emailSyncBusy.remove(provider);
    }
  }

  Future<EmailSyncResult> _finishEmailSync(
    EmailProvider provider,
    EmailSyncState next,
    String message,
  ) async {
    final user = _requireUser();
    _emailSyncStates = {..._emailSyncStates, provider: next};
    await _database.saveEmailSyncState(userId: user.id, state: next);
    notifyListeners();
    return EmailSyncResult(synced: false, message: message);
  }

  Future<void> _loadAutoSyncState(int userId) async {
    _conversationSyncBackendAvailable = true;
    try {
      _conversationSyncState = await _database.conversationSyncState(userId);
    } catch (error) {
      if (!_isMissingServerRoute(error)) rethrow;
      _conversationSyncBackendAvailable = false;
      _conversationSyncState = ConversationSyncState.defaultState.copyWith(
        status: ConversationSyncStatus.error,
        lastError: '服务器版本过旧：自动笔记接口尚未部署。请更新 AILearningOS 服务端。',
      );
      _emailSyncStates = {
        for (final provider in EmailProvider.values)
          provider: EmailSyncState.defaultFor(provider),
      };
      return;
    }

    final emailStates = <EmailProvider, EmailSyncState>{};
    for (final provider in EmailProvider.values) {
      try {
        emailStates[provider] = await _database.emailSyncState(
          userId: userId,
          provider: provider,
        );
      } catch (error) {
        if (!_isMissingServerRoute(error)) rethrow;
        emailStates[provider] = EmailSyncState.defaultFor(provider);
      }
    }
    _emailSyncStates = emailStates;
  }

  /// Syncs exactly the second newest snapshot in the Bridge inbox. The
  /// newest snapshot is intentionally ignored so a still-streaming ChatGPT
  /// answer cannot become a note.
  Future<ConversationSyncResult> syncChatGptConversation({
    bool manual = false,
    bool scheduledNightly = false,
  }) async {
    final user = _requireUser();
    if (_conversationSyncBusy) {
      return const ConversationSyncResult(
        synced: false,
        message: '同步正在进行中，请稍候。',
      );
    }
    if (!manual && !scheduledNightly && !_conversationSyncState.enabled) {
      return const ConversationSyncResult(
        synced: false,
        message: '高频循环未开启，将在每天 23:00 统一检查。',
      );
    }

    _conversationSyncBusy = true;
    final attemptAt = DateTime.now();
    _conversationSyncState = _conversationSyncState.copyWith(
      status: ConversationSyncStatus.syncing,
      lastAttemptAt: attemptAt,
      clearError: true,
    );
    notifyListeners();
    try {
      final snapshots = await _database.conversationInbox(user.id);
      if (snapshots.length < 2) {
        return await _finishConversationSync(
          _conversationSyncState.copyWith(
            status: ConversationSyncStatus.waiting,
            lastAttemptAt: attemptAt,
          ),
          '等待至少两条 ChatGPT 对话快照。',
        );
      }

      final candidate = snapshots[1];
      if (!candidate.isComplete) {
        return await _finishConversationSync(
          _conversationSyncState.copyWith(
            status: ConversationSyncStatus.waiting,
            lastAttemptAt: attemptAt,
          ),
          '最新一条的上一条对话仍未标记为完成，暂不生成笔记。',
        );
      }
      if (candidate.externalId ==
          _conversationSyncState.lastSyncedConversationId) {
        return await _finishConversationSync(
          _conversationSyncState.copyWith(
            status: ConversationSyncStatus.synced,
            lastAttemptAt: attemptAt,
          ),
          '没有新的倒数第二条对话。',
        );
      }
      if (!aiReady) {
        return await _finishConversationSync(
          _conversationSyncState.copyWith(
            status: ConversationSyncStatus.error,
            lastAttemptAt: attemptAt,
            lastError: '请先连接 ChatGPT/Codex 或启用 DeepSeek，才能自动生成摘要。',
          ),
          '请先连接 ChatGPT/Codex 或启用 DeepSeek，才能自动生成摘要。',
        );
      }

      final analysis = await _aiService.analyzeConversation(
        settings: _aiSettings,
        transcript: candidate.transcript,
      );
      if (analysis.warning != null) throw StateError(analysis.warning!);
      final concepts = analysis.learnedConcepts.isEmpty
          ? ''
          : '\n\n学习证据 / Learned concepts:\n${analysis.learnedConcepts.map((item) => '- $item').join('\n')}';
      final actions = analysis.actionItems.isEmpty
          ? ''
          : '\n\n待复习 / Next actions:\n${analysis.actionItems.map((item) => '- $item').join('\n')}';
      final insertedWords = analysis.words.isEmpty
          ? 0
          : await _database.insertWords(userId: user.id, words: analysis.words);
      await _database.addNote(
        userId: user.id,
        title: analysis.title,
        contentEnglish:
            '${analysis.summaryEnglish}\n\n[Original ChatGPT conversation]\n${candidate.transcript}',
        contentChinese: '${analysis.summaryChinese}$concepts$actions',
        source: 'ChatGPT 自动同步 · ${candidate.updatedAt.toIso8601String()}',
      );
      await _database.saveObsidianEntry(
        userId: user.id,
        title: analysis.title,
        contentEnglish: analysis.summaryEnglish,
        contentChinese: '${analysis.summaryChinese}$concepts$actions',
        source: 'ChatGPT 自动同步',
        category: analysis.category,
        tags: analysis.tags,
        sourceId: candidate.externalId,
        updatedAt: candidate.updatedAt,
      );
      final syncedAt = DateTime.now();
      await _database.markConversationSynced(
        userId: user.id,
        conversationId: candidate.externalId,
        title: candidate.title,
        syncedAt: syncedAt,
      );
      _conversationSyncState = _conversationSyncState.copyWith(
        status: ConversationSyncStatus.synced,
        lastAttemptAt: attemptAt,
        lastSyncedAt: syncedAt,
        lastSyncedConversationId: candidate.externalId,
        lastSyncedTitle: candidate.title,
        clearError: true,
      );
      await _reloadLearningData();
      return ConversationSyncResult(
        synced: true,
        title: analysis.title,
        message: '已生成笔记${insertedWords == 0 ? '' : '，并加入 $insertedWords 个词条'}。',
      );
    } catch (error) {
      final message = '自动同步失败：$error';
      return await _finishConversationSync(
        _conversationSyncState.copyWith(
          status: ConversationSyncStatus.error,
          lastAttemptAt: attemptAt,
          lastError: message,
        ),
        message,
      );
    } finally {
      _conversationSyncBusy = false;
    }
  }

  Future<ConversationSyncResult> _finishConversationSync(
    ConversationSyncState next,
    String message,
  ) async {
    final user = _requireUser();
    _conversationSyncState = next;
    await _database.saveConversationSyncState(userId: user.id, state: next);
    notifyListeners();
    return ConversationSyncResult(synced: false, message: message);
  }

  void _startPendingWordEnrichmentTimer() {
    _pendingWordEnrichmentTimer?.cancel();
    _pendingWordEnrichmentTimer = null;
    if (_currentUser == null ||
        !_pendingWordBackendAvailable ||
        pendingAiWordCount == 0) {
      return;
    }

    _pendingWordEnrichmentTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_runPendingWordEnrichment()),
    );
    unawaited(_runPendingWordEnrichment());
  }

  Future<void> _runPendingWordEnrichment() async {
    final user = _currentUser;
    if (user == null ||
        !_pendingWordBackendAvailable ||
        _pendingWordEnrichmentBusy ||
        pendingAiWordCount == 0) {
      return;
    }

    _pendingWordEnrichmentBusy = true;
    _pendingWordEnrichmentState = PendingWordEnrichmentState(
      status: 'checking',
      pendingCount: pendingAiWordCount,
      requestedCount: 0,
      enrichedCount: 0,
      message: '正在检查服务器后台补全进度…',
      retryIntervalSeconds: 30,
      checkedAt: DateTime.now(),
    );
    notifyListeners();

    try {
      // Pull completed rows before waking the next batch. The server owns the
      // actual worker, so this remains safe when Android is backgrounded.
      _words = await _database.wordsForUser(user.id);
      try {
        _aiSettings = await _database.aiSettings();
      } catch (_) {
        // Keep the last visible connection state during a transient refresh.
      }
      if (pendingAiWordCount == 0) {
        _pendingWordEnrichmentTimer?.cancel();
        _pendingWordEnrichmentTimer = null;
        _pendingWordEnrichmentState = PendingWordEnrichmentState(
          status: 'complete',
          pendingCount: 0,
          requestedCount: 0,
          enrichedCount: 0,
          message: '待翻译、待识别词性和其他待补全字段已全部处理完成。',
          retryIntervalSeconds: 30,
          checkedAt: DateTime.now(),
        );
        return;
      }
      _pendingWordEnrichmentState = await _database.enrichPendingWords(user.id);
      if (pendingAiWordCount == 0) {
        _pendingWordEnrichmentTimer?.cancel();
        _pendingWordEnrichmentTimer = null;
      }
    } catch (error) {
      if (_isMissingServerRoute(error)) {
        _pendingWordBackendAvailable = false;
        _pendingWordEnrichmentTimer?.cancel();
        _pendingWordEnrichmentTimer = null;
        _pendingWordEnrichmentState = PendingWordEnrichmentState(
          status: 'unavailable',
          pendingCount: pendingAiWordCount,
          requestedCount: 0,
          enrichedCount: 0,
          message: '当前服务器版本还没有 30 秒词库队列接口。',
          retryIntervalSeconds: 30,
          checkedAt: DateTime.now(),
        );
      } else {
        _pendingWordEnrichmentState = PendingWordEnrichmentState(
          status: 'retrying',
          pendingCount: pendingAiWordCount,
          requestedCount: 0,
          enrichedCount: 0,
          message: '后台队列暂时无法连接，30 秒后自动重试：$error',
          retryIntervalSeconds: 30,
          checkedAt: DateTime.now(),
        );
      }
    } finally {
      _pendingWordEnrichmentBusy = false;
      notifyListeners();
    }
  }

  void _startCodexRealtimeBridge({bool fullRefresh = false}) {
    _codexRealtimeTimer?.cancel();
    _codexRealtimeTimer = null;
    if (_currentUser == null ||
        !_chatGptAuth.authenticated ||
        !_chatGptAuthService.supported) {
      return;
    }
    unawaited(
      _refreshCodexRealtimeBridge(fullRefresh: fullRefresh, refreshQuota: true),
    );
    _codexRealtimeTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshCodexRealtimeBridge()),
    );
  }

  void _stopCodexRealtimeBridge() {
    _codexRealtimeTimer?.cancel();
    _codexRealtimeTimer = null;
  }

  Future<String?> refreshCodexConnection() async {
    if (!_chatGptAuth.authenticated) return '请先登录 ChatGPT。';
    await _refreshCodexRealtimeBridge(fullRefresh: true, refreshQuota: true);
    return _codexHistory.lastError ?? _codexQuota.message;
  }

  Future<void> _refreshCodexRealtimeBridge({
    bool fullRefresh = false,
    bool refreshQuota = false,
  }) async {
    final user = _currentUser;
    if (user == null || !_chatGptAuth.authenticated || _codexRealtimeBusy) {
      return;
    }
    _codexRealtimeBusy = true;
    final now = DateTime.now();
    try {
      final quotaAge = _lastCodexQuotaRefreshAt == null
          ? null
          : now.difference(_lastCodexQuotaRefreshAt!);
      if (refreshQuota ||
          quotaAge == null ||
          quotaAge >= const Duration(minutes: 1)) {
        try {
          _codexQuota = await _chatGptAuthService.readQuota();
          _lastCodexQuotaRefreshAt = now;
        } catch (error) {
          _codexQuota = ChatGptCodexQuotaState.unavailable('额度读取失败：$error');
        }
      }

      final batch = await _chatGptAuthService.readCodexHistory(
        fullRefresh: fullRefresh,
      );
      if (batch.changedConversations.isNotEmpty) {
        await _database.ingestConversationInbox(
          userId: user.id,
          conversations: [
            for (final conversation in batch.changedConversations)
              ChatGptConversationSnapshot(
                externalId: conversation.externalId,
                title: conversation.title,
                transcript: conversation.transcript,
                updatedAt: conversation.updatedAt,
                isComplete: conversation.isComplete,
              ),
          ],
        );
      }
      _codexHistory = CodexHistorySyncState(
        running: true,
        folderName: batch.folderName,
        threadCount: batch.totalThreads,
        lastReadAt: batch.checkedAt,
      );
    } catch (error) {
      _codexHistory = CodexHistorySyncState(
        running: true,
        folderName: _codexHistory.folderName,
        threadCount: _codexHistory.threadCount,
        lastReadAt: _codexHistory.lastReadAt,
        lastError: 'Codex OSS 会话读取失败：$error',
      );
    } finally {
      _codexRealtimeBusy = false;
      notifyListeners();
    }
  }

  static String _transcriptForAi(String transcript) {
    const maxCharacters = 100000;
    if (transcript.length <= maxCharacters) return transcript;
    return '[Earlier messages omitted for AI analysis.]\n\n'
        '${transcript.substring(transcript.length - maxCharacters)}';
  }

  void _startConversationSyncTimer({bool runMissedNightly = true}) {
    _conversationSyncTimer?.cancel();
    _conversationSyncTimer = null;
    if (_currentUser == null || !_conversationSyncBackendAvailable) return;

    if (_conversationSyncState.enabled) {
      final intervalMinutes = _conversationSyncState.intervalMinutes
          .clamp(1, 24 * 60)
          .toInt();
      _conversationSyncTimer = Timer.periodic(
        Duration(minutes: intervalMinutes),
        (_) => _runHighFrequencySync(),
      );
      // An explicit switch-on should provide immediate feedback instead of
      // making the user wait for the first 15-minute tick.
      unawaited(_runHighFrequencySync());
      return;
    }

    _scheduleNightlySync(runMissedNightly: runMissedNightly);
  }

  Future<void> _runHighFrequencySync() async {
    if (_currentUser == null ||
        !_conversationSyncBackendAvailable ||
        !_conversationSyncState.enabled) {
      return;
    }
    unawaited(syncChatGptConversation());
    for (final provider in EmailProvider.values) {
      if (emailSyncState(provider).enabled) {
        unawaited(syncEmailProvider(provider));
      }
    }
  }

  void _scheduleNightlySync({required bool runMissedNightly}) {
    if (_currentUser == null ||
        !_conversationSyncBackendAvailable ||
        _conversationSyncState.enabled) {
      return;
    }

    final now = DateTime.now();
    if (runMissedNightly &&
        AutoNoteSchedule.isNightlyDue(
          now: now,
          lastRunAt: _conversationSyncState.lastNightlyRunAt,
        )) {
      unawaited(_runNightlySync());
    }

    final next = AutoNoteSchedule.nextNightlyAt(now);
    _conversationSyncTimer = Timer(next.difference(now), () {
      if (_currentUser == null || _conversationSyncState.enabled) return;
      unawaited(_runNightlySync());
      _scheduleNightlySync(runMissedNightly: false);
    });
  }

  Future<void> _runNightlySync() async {
    if (_nightlySyncBusy ||
        _currentUser == null ||
        !_conversationSyncBackendAvailable ||
        _conversationSyncState.enabled) {
      return;
    }

    final now = DateTime.now();
    if (!AutoNoteSchedule.isNightlyDue(
      now: now,
      lastRunAt: _conversationSyncState.lastNightlyRunAt,
    )) {
      return;
    }

    _nightlySyncBusy = true;
    try {
      // Persist the attempt before processing. If the app resumes twice or a
      // scheduled callback fires twice, the same calendar day is not repeated.
      final marked = _conversationSyncState.copyWith(
        lastNightlyRunAt: now,
        status: ConversationSyncStatus.waiting,
        clearError: true,
      );
      _conversationSyncState = marked;
      await _database.saveConversationSyncState(
        userId: _currentUser!.id,
        state: marked,
      );
      notifyListeners();

      await syncChatGptConversation(scheduledNightly: true);
      for (final provider in EmailProvider.values) {
        if (emailSyncState(provider).enabled) {
          await syncEmailProvider(provider, scheduledNightly: true);
        }
      }
    } finally {
      _nightlySyncBusy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentUser != null) {
      _startConversationSyncTimer();
      _startPendingWordEnrichmentTimer();
      _startCodexRealtimeBridge(fullRefresh: true);
    }
  }

  Future<String?> saveAiSettings({
    required bool enabled,
    required String apiKey,
    required String model,
  }) async {
    return _guard(() async {
      final settings = AiConnectionSettings(
        enabled: enabled,
        apiKey: apiKey.trim(),
        model: model.trim().isEmpty
            ? AiConnectionSettings.defaultModel
            : model.trim(),
        apiKeyConfigured:
            apiKey.trim().isNotEmpty || _aiSettings.apiKeyConfigured,
        apiKeyHint: _aiSettings.apiKeyHint,
        serverEncryptionReady: _aiSettings.serverEncryptionReady,
      );
      await _database.saveAiSettings(settings);
      _aiSettings = await _database.aiSettings();
      notifyListeners();
      if (_aiSettings.ready && pendingAiWordCount > 0) {
        unawaited(_runPendingWordEnrichment());
      }
      return null;
    });
  }

  Future<String?> testAiConnection({AiConnectionSettings? settings}) async {
    final activeSettings = settings ?? _aiSettings;
    if (!_chatGptAuth.authenticated && !activeSettings.ready) {
      return '请先使用 ChatGPT 登录接入 Codex，或启用 DeepSeek API Key。';
    }
    return _guard(() async {
      if (activeSettings.ready) {
        return _database.testAiConnection(activeSettings);
      }
      final probe = await _aiService.testConnection(activeSettings);
      return probe.ok ? null : probe.message;
    });
  }

  Future<void> refresh() => _reloadLearningData();

  Future<CourseAttemptResult> submitCourseAttempt({
    required String chapterId,
    required Map<String, int> answers,
  }) async {
    final user = _requireUser();
    _setBusy(true);
    try {
      final result = await _database.submitCourseAttempt(
        userId: user.id,
        chapterId: chapterId,
        answers: answers,
      );
      await _reloadLearningData();
      return result;
    } catch (error) {
      return CourseAttemptResult(
        chapterId: chapterId,
        score: 0,
        passed: false,
        message: '章节提交失败：$error',
        wrongQuestionIds: const [],
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshCoursePlan() async {
    final user = _currentUser;
    if (user == null) return;
    _setBusy(true);
    try {
      _courseDailyPlan = await _database.courseDailyPlan(user.id);
    } catch (_) {
      // The course map remains usable if an older server has no daily-plan API.
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _reloadLearningData() async {
    final user = _requireUser();
    final values = await Future.wait<Object>([
      _database.wordsForUser(user.id),
      _database.notesForUser(user.id),
      _database.capturesForUser(user.id),
      _database.todayStats(user.id),
      _database.loginSecurityForEmail(user.email),
    ]);
    _words = values[0] as List<StudyWord>;
    _notes = values[1] as List<StudyNote>;
    _captures = values[2] as List<CapturedDocument>;
    _todayStats = values[3] as TodayStats;
    _loginSecurity = values[4] as LoginSecurityState;
    if (pendingAiWordCount > 0 && _pendingWordEnrichmentTimer == null) {
      _startPendingWordEnrichmentTimer();
    } else if (pendingAiWordCount == 0) {
      _pendingWordEnrichmentTimer?.cancel();
      _pendingWordEnrichmentTimer = null;
    }
    if (pendingAiWordCount == 0) {
      _pendingWordEnrichmentState = PendingWordEnrichmentState.idle;
    } else if (_pendingWordEnrichmentState.pendingCount == 0) {
      _pendingWordEnrichmentState = PendingWordEnrichmentState(
        status: 'queued',
        pendingCount: pendingAiWordCount,
        requestedCount: 0,
        enrichedCount: 0,
        message: '已加入服务器后台队列；每 30 秒自动检查一次。',
        retryIntervalSeconds: 30,
      );
    }
    try {
      _courseChapters = await _database.courseChapters(user.id);
    } catch (_) {
      // Keep older deployed servers usable while the course API is rolled out.
      _courseChapters = const [];
    }
    notifyListeners();
  }

  Future<String?> _guard(Future<String?> Function() operation) async {
    _setBusy(true);
    try {
      return await operation();
    } catch (error) {
      return '操作失败：$error';
    } finally {
      _setBusy(false);
    }
  }

  AppUser _requireUser() {
    final user = _currentUser;
    if (user == null) throw StateError('需要先登录。');
    return user;
  }

  static bool _isMissingServerRoute(Object error) =>
      error.toString().toLowerCase().contains('http 404');

  String _failedLoginMessage(LoginSecurityState state) {
    final remaining = state.remainingAt(DateTime.now());
    if (remaining > Duration.zero) {
      return '邮箱或密码不正确。登录保护已锁定 ${SecurityPolicy.formatRemaining(remaining)}。';
    }
    return '邮箱或密码不正确。连续失败将触发指数退避锁定。';
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  static String _displayNameFromEmail(String? email) {
    final value = email?.trim();
    if (value == null || value.isEmpty) return 'ChatGPT 用户';
    final localPart = value.split('@').first.trim();
    return localPart.isEmpty ? 'ChatGPT 用户' : localPart;
  }
}
