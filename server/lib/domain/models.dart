enum ReviewRating { again, hard, good, easy }

extension ReviewRatingLabel on ReviewRating {
  String get label => switch (this) {
    ReviewRating.again => '忘记了',
    ReviewRating.hard => '较困难',
    ReviewRating.good => '记住了',
    ReviewRating.easy => '很简单',
  };

  int get databaseValue => index;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.authProvider = 'local',
    this.externalSubject,
  });

  final int id;
  final String email;
  final String displayName;
  final DateTime createdAt;

  /// The login system that created this account. Kept explicit so a
  /// ChatGPT/Codex identity can be linked without storing its access token in
  /// the learning database.
  final String authProvider;

  /// Stable identifier returned by the external provider. This is not a
  /// credential and is safe to use only for account lookup/linking.
  final String? externalSubject;

  bool get isExternal => authProvider != 'local';

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id']! as int,
      email: map['email']! as String,
      displayName: map['display_name']! as String,
      createdAt: DateTime.parse(map['created_at']! as String),
      authProvider: (map['auth_provider'] as String?) ?? 'local',
      externalSubject: map['external_subject'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'auth_provider': authProvider,
      'external_subject': externalSubject,
    };
  }
}

class StoredCredential {
  const StoredCredential({
    required this.user,
    required this.passwordHash,
    required this.passwordSalt,
  });

  final AppUser user;
  final String passwordHash;
  final String passwordSalt;
}

enum AiProvider {
  codex,
  deepSeek;

  String get apiValue => this == AiProvider.codex ? 'codex' : 'deepseek';

  static AiProvider fromApiValue(Object? value) =>
      value?.toString().trim().toLowerCase() == 'codex'
      ? AiProvider.codex
      : AiProvider.deepSeek;
}

class AiConnectionSettings {
  const AiConnectionSettings({
    required this.enabled,
    required this.apiKey,
    required this.model,
    this.provider = AiProvider.deepSeek,
    this.codexModel = defaultCodexModel,
    this.autoReturnToCodex = false,
    this.codexResumeAt,
  });

  static const defaultModel = 'deepseek-v4-flash';
  // GPT-5.4 was retired for ChatGPT-login Codex on 2026-08-31. This is only
  // the migration preference; every use still validates against model/list.
  static const defaultCodexModel = 'gpt-5.6-terra';

  static String migrateCodexModel(String value) {
    return switch (value.trim()) {
      '' => defaultCodexModel,
      'gpt-5.4' => 'gpt-5.6-terra',
      'gpt-5.4-mini' => 'gpt-5.6-luna',
      final model => model,
    };
  }

  /// Chooses only from ids returned by the active Codex App Server.
  static String? selectCodexModel(
    Iterable<String> advertisedModels, {
    String? requested,
  }) {
    final models = advertisedModels
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toList(growable: false);
    if (models.isEmpty) return null;
    final selected = migrateCodexModel(requested ?? '');
    if (models.contains(selected)) return selected;
    for (final fallback in const [
      'gpt-5.6-terra',
      'gpt-5.6-sol',
      'gpt-5.6-luna',
    ]) {
      if (models.contains(fallback)) return fallback;
    }
    return models.first;
  }

  static const empty = AiConnectionSettings(
    enabled: false,
    apiKey: '',
    model: defaultModel,
    provider: AiProvider.deepSeek,
    codexModel: defaultCodexModel,
  );

  final bool enabled;
  final String apiKey;
  final String model;
  final AiProvider provider;
  final String codexModel;
  final bool autoReturnToCodex;
  final DateTime? codexResumeAt;

  bool get ready => enabled && apiKey.trim().isNotEmpty;
  bool get usesCodex => provider == AiProvider.codex;
  bool get usesDeepSeek => provider == AiProvider.deepSeek;

  AiConnectionSettings copyWith({
    bool? enabled,
    String? apiKey,
    String? model,
    AiProvider? provider,
    String? codexModel,
    bool? autoReturnToCodex,
    DateTime? codexResumeAt,
  }) {
    return AiConnectionSettings(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      codexModel: codexModel ?? this.codexModel,
      autoReturnToCodex: autoReturnToCodex ?? this.autoReturnToCodex,
      codexResumeAt: codexResumeAt ?? this.codexResumeAt,
    );
  }
}

class WordImportResult {
  const WordImportResult({
    required this.insertedCount,
    required this.aiEnrichedCount,
    this.aiWarning,
  });

  const WordImportResult.empty()
    : insertedCount = 0,
      aiEnrichedCount = 0,
      aiWarning = null;

  final int insertedCount;
  final int aiEnrichedCount;
  final String? aiWarning;
}

enum ConversationSyncStatus { disabled, waiting, syncing, synced, error }

class ChatGptConversationSnapshot {
  const ChatGptConversationSnapshot({
    required this.externalId,
    required this.title,
    required this.transcript,
    required this.updatedAt,
    required this.isComplete,
  });

  final String externalId;
  final String title;
  final String transcript;
  final DateTime updatedAt;
  final bool isComplete;

  factory ChatGptConversationSnapshot.fromMap(Map<String, Object?> map) {
    final complete = map['is_complete'];
    return ChatGptConversationSnapshot(
      externalId: map['external_id']! as String,
      title: map['title']! as String,
      transcript: map['transcript']! as String,
      updatedAt: DateTime.parse(map['updated_at']! as String),
      isComplete:
          complete == true ||
          (complete is num && complete.toInt() == 1) ||
          (complete is String && complete.trim() == '1'),
    );
  }

  Map<String, dynamic> toMap() => {
    'external_id': externalId,
    'title': title,
    'transcript': transcript,
    'updated_at': updatedAt.toIso8601String(),
    'is_complete': isComplete,
  };
}

class ConversationSyncState {
  const ConversationSyncState({
    required this.enabled,
    required this.intervalMinutes,
    required this.status,
    this.lastAttemptAt,
    this.lastSyncedAt,
    this.lastSyncedConversationId,
    this.lastSyncedTitle,
    this.lastError,
    this.lastNightlyRunAt,
    this.scheduleConfigured = false,
  });

  static const defaultState = ConversationSyncState(
    enabled: false,
    intervalMinutes: 15,
    status: ConversationSyncStatus.waiting,
  );

  final bool enabled;
  final int intervalMinutes;
  final ConversationSyncStatus status;
  final DateTime? lastAttemptAt;
  final DateTime? lastSyncedAt;
  final String? lastSyncedConversationId;
  final String? lastSyncedTitle;
  final String? lastError;
  final DateTime? lastNightlyRunAt;

  /// True only after the user has explicitly chosen the high-frequency mode.
  /// This lets upgraded installations distinguish an old implicit default of
  /// enabled=true from a deliberate user choice.
  final bool scheduleConfigured;

  ConversationSyncState copyWith({
    bool? enabled,
    int? intervalMinutes,
    ConversationSyncStatus? status,
    DateTime? lastAttemptAt,
    DateTime? lastSyncedAt,
    String? lastSyncedConversationId,
    String? lastSyncedTitle,
    String? lastError,
    DateTime? lastNightlyRunAt,
    bool? scheduleConfigured,
    bool clearError = false,
  }) {
    return ConversationSyncState(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      status: status ?? this.status,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastSyncedConversationId:
          lastSyncedConversationId ?? this.lastSyncedConversationId,
      lastSyncedTitle: lastSyncedTitle ?? this.lastSyncedTitle,
      lastError: clearError ? null : lastError ?? this.lastError,
      lastNightlyRunAt: lastNightlyRunAt ?? this.lastNightlyRunAt,
      scheduleConfigured: scheduleConfigured ?? this.scheduleConfigured,
    );
  }

  factory ConversationSyncState.fromMap(Map<String, Object?> map) {
    final statusName = (map['status'] as String?)?.trim();
    final status = ConversationSyncStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => ConversationSyncStatus.waiting,
    );
    final scheduleConfigured = _asBool(
      map['schedule_configured'],
      fallback: false,
    );
    return ConversationSyncState(
      enabled: scheduleConfigured
          ? _asBool(map['enabled'], fallback: false)
          : false,
      intervalMinutes: (map['interval_minutes'] as num?)?.toInt() ?? 15,
      status: status,
      lastAttemptAt: _asDateTime(map['last_attempt_at']),
      lastSyncedAt: _asDateTime(map['last_synced_at']),
      lastSyncedConversationId: map['last_synced_conversation_id'] as String?,
      lastSyncedTitle: map['last_synced_title'] as String?,
      lastError: map['last_error'] as String?,
      lastNightlyRunAt: _asDateTime(map['last_nightly_run_at']),
      scheduleConfigured: scheduleConfigured,
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'interval_minutes': intervalMinutes,
    'status': status.name,
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'last_synced_at': lastSyncedAt?.toIso8601String(),
    'last_synced_conversation_id': lastSyncedConversationId,
    'last_synced_title': lastSyncedTitle,
    'last_error': lastError,
    'last_nightly_run_at': lastNightlyRunAt?.toIso8601String(),
    'schedule_configured': scheduleConfigured,
  };

  static bool _asBool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    if (value is String) {
      return value.trim().toLowerCase() == 'true' || value.trim() == '1';
    }
    return fallback;
  }

  static DateTime? _asDateTime(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

class ConversationSyncResult {
  const ConversationSyncResult({
    required this.synced,
    required this.message,
    this.title,
  });

  final bool synced;
  final String message;
  final String? title;
}

enum EmailProvider { outlook, qq }

extension EmailProviderLabel on EmailProvider {
  String get label => this == EmailProvider.outlook ? 'Outlook' : 'QQ 邮箱';

  String get apiValue => this == EmailProvider.outlook ? 'outlook' : 'qq';
}

class EmailMessageSnapshot {
  const EmailMessageSnapshot({
    required this.externalId,
    required this.provider,
    required this.subject,
    required this.sender,
    required this.recipients,
    required this.body,
    required this.receivedAt,
    required this.isComplete,
  });

  final String externalId;
  final EmailProvider provider;
  final String subject;
  final String sender;
  final String recipients;
  final String body;
  final DateTime receivedAt;
  final bool isComplete;

  String get transcript =>
      '''Email source: ${provider.label}
Subject: $subject
From: $sender
To: $recipients
Received: ${receivedAt.toIso8601String()}

$body''';

  factory EmailMessageSnapshot.fromMap(Map<String, Object?> map) {
    final provider = (map['provider'] as String?)?.trim().toLowerCase();
    final complete = map['is_complete'];
    return EmailMessageSnapshot(
      externalId: map['external_id']! as String,
      provider: EmailProvider.values.firstWhere(
        (item) => item.apiValue == provider,
        orElse: () => EmailProvider.qq,
      ),
      subject: map['subject']! as String,
      sender: map['sender']! as String,
      recipients: map['recipients']! as String,
      body: map['body']! as String,
      receivedAt: DateTime.parse(map['received_at']! as String),
      isComplete:
          complete == true ||
          (complete is num && complete.toInt() == 1) ||
          (complete is String && complete.trim() == '1'),
    );
  }

  Map<String, dynamic> toMap() => {
    'external_id': externalId,
    'provider': provider.apiValue,
    'subject': subject,
    'sender': sender,
    'recipients': recipients,
    'body': body,
    'received_at': receivedAt.toIso8601String(),
    'is_complete': isComplete,
  };
}

class EmailSyncState {
  const EmailSyncState({
    required this.provider,
    required this.enabled,
    required this.intervalMinutes,
    required this.status,
    this.lastAttemptAt,
    this.lastSyncedAt,
    this.lastSyncedMessageId,
    this.lastSyncedSubject,
    this.lastError,
  });

  static EmailSyncState defaultFor(EmailProvider provider) => EmailSyncState(
    provider: provider,
    enabled: true,
    intervalMinutes: 15,
    status: ConversationSyncStatus.waiting,
  );

  final EmailProvider provider;
  final bool enabled;
  final int intervalMinutes;
  final ConversationSyncStatus status;
  final DateTime? lastAttemptAt;
  final DateTime? lastSyncedAt;
  final String? lastSyncedMessageId;
  final String? lastSyncedSubject;
  final String? lastError;

  EmailSyncState copyWith({
    bool? enabled,
    ConversationSyncStatus? status,
    DateTime? lastAttemptAt,
    DateTime? lastSyncedAt,
    String? lastSyncedMessageId,
    String? lastSyncedSubject,
    String? lastError,
    bool clearError = false,
  }) => EmailSyncState(
    provider: provider,
    enabled: enabled ?? this.enabled,
    intervalMinutes: intervalMinutes,
    status: status ?? this.status,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastSyncedMessageId: lastSyncedMessageId ?? this.lastSyncedMessageId,
    lastSyncedSubject: lastSyncedSubject ?? this.lastSyncedSubject,
    lastError: clearError ? null : lastError ?? this.lastError,
  );

  factory EmailSyncState.fromMap(
    EmailProvider provider,
    Map<String, Object?> map,
  ) => EmailSyncState(
    provider: provider,
    enabled: ConversationSyncState._asBool(map['enabled'], fallback: true),
    intervalMinutes: (map['interval_minutes'] as num?)?.toInt() ?? 15,
    status: ConversationSyncStatus.values.firstWhere(
      (item) => item.name == (map['status'] as String?)?.trim(),
      orElse: () => ConversationSyncStatus.waiting,
    ),
    lastAttemptAt: ConversationSyncState._asDateTime(map['last_attempt_at']),
    lastSyncedAt: ConversationSyncState._asDateTime(map['last_synced_at']),
    lastSyncedMessageId: map['last_synced_message_id'] as String?,
    lastSyncedSubject: map['last_synced_subject'] as String?,
    lastError: map['last_error'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'provider': provider.apiValue,
    'enabled': enabled,
    'interval_minutes': intervalMinutes,
    'status': status.name,
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'last_synced_at': lastSyncedAt?.toIso8601String(),
    'last_synced_message_id': lastSyncedMessageId,
    'last_synced_subject': lastSyncedSubject,
    'last_error': lastError,
  };
}

class EmailSyncResult {
  const EmailSyncResult({required this.synced, required this.message});

  final bool synced;
  final String message;
}

class CourseDailyPlan {
  const CourseDailyPlan({
    required this.generatedAt,
    required this.title,
    required this.phase,
    required this.chapterId,
    required this.rationale,
    required this.tasks,
    required this.testFocus,
    required this.aiGenerated,
    required this.source,
  });

  final DateTime generatedAt;
  final String title;
  final String phase;
  final String chapterId;
  final String rationale;
  final List<String> tasks;
  final List<String> testFocus;
  final bool aiGenerated;
  final String source;

  factory CourseDailyPlan.fromMap(Map<String, Object?> map) {
    final rawTasks = map['tasks'];
    final rawFocus = map['test_focus'];
    return CourseDailyPlan(
      generatedAt:
          DateTime.tryParse(map['generated_at']?.toString() ?? '') ??
          DateTime.now(),
      title: map['title']?.toString() ?? '今日学习计划',
      phase: map['phase']?.toString() ?? '',
      chapterId: map['chapter_id']?.toString() ?? '',
      rationale: map['rationale']?.toString() ?? '',
      tasks: rawTasks is List
          ? rawTasks.map((item) => item.toString()).toList(growable: false)
          : const [],
      testFocus: rawFocus is List
          ? rawFocus.map((item) => item.toString()).toList(growable: false)
          : const [],
      aiGenerated:
          map['ai_generated'] == true ||
          (map['ai_generated'] is num &&
              (map['ai_generated'] as num).toInt() == 1),
      source: map['source']?.toString() ?? 'local-fallback',
    );
  }

  Map<String, dynamic> toMap() => {
    'generated_at': generatedAt.toIso8601String(),
    'title': title,
    'phase': phase,
    'chapter_id': chapterId,
    'rationale': rationale,
    'tasks': tasks,
    'test_focus': testFocus,
    'ai_generated': aiGenerated,
    'source': source,
  };
}

enum CourseChapterStatus { locked, available, inProgress, completed }

class CourseQuestion {
  const CourseQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    this.correctIndex,
    this.explanation,
  });

  final String id;
  final String prompt;
  final List<String> options;
  final int? correctIndex;
  final String? explanation;

  factory CourseQuestion.fromMap(Map<String, Object?> map) {
    final rawOptions = map['options'];
    return CourseQuestion(
      id: map['id']?.toString() ?? '',
      prompt: map['prompt']?.toString() ?? '',
      options: rawOptions is List
          ? rawOptions.map((item) => item.toString()).toList(growable: false)
          : const [],
      correctIndex: (map['correct_index'] as num?)?.toInt(),
      explanation: map['explanation']?.toString(),
    );
  }

  Map<String, dynamic> toMap({bool includeAnswer = false}) => {
    'id': id,
    'prompt': prompt,
    'options': options,
    if (includeAnswer && correctIndex != null) 'correct_index': correctIndex,
    if (includeAnswer && explanation != null) 'explanation': explanation,
  };
}

class CourseChapter {
  const CourseChapter({
    required this.chapterId,
    required this.phase,
    required this.orderIndex,
    required this.title,
    required this.description,
    required this.objectives,
    required this.lesson,
    required this.questions,
    required this.status,
    required this.mastery,
    required this.attempts,
    this.lastScore,
    this.nextReviewAt,
  });

  final String chapterId;
  final String phase;
  final int orderIndex;
  final String title;
  final String description;
  final List<String> objectives;
  final String lesson;
  final List<CourseQuestion> questions;
  final CourseChapterStatus status;
  final double mastery;
  final int attempts;
  final double? lastScore;
  final DateTime? nextReviewAt;

  bool get isUnlocked => status != CourseChapterStatus.locked;
  bool get isCompleted => status == CourseChapterStatus.completed;

  factory CourseChapter.fromMap(Map<String, Object?> map) {
    final rawObjectives = map['objectives'];
    final rawQuestions = map['questions'];
    final statusName = map['status']?.toString();
    return CourseChapter(
      chapterId: map['chapter_id']?.toString() ?? '',
      phase: map['phase']?.toString() ?? '',
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      objectives: rawObjectives is List
          ? rawObjectives.map((item) => item.toString()).toList(growable: false)
          : const [],
      lesson: map['lesson']?.toString() ?? '',
      questions: rawQuestions is List
          ? rawQuestions
                .whereType<Map>()
                .map(
                  (item) =>
                      CourseQuestion.fromMap(Map<String, Object?>.from(item)),
                )
                .toList(growable: false)
          : const [],
      status: CourseChapterStatus.values.firstWhere(
        (item) => item.name == statusName,
        orElse: () => CourseChapterStatus.locked,
      ),
      mastery: (map['mastery'] as num?)?.toDouble() ?? 0,
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      lastScore: (map['last_score'] as num?)?.toDouble(),
      nextReviewAt: ConversationSyncState._asDateTime(map['next_review_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'chapter_id': chapterId,
    'phase': phase,
    'order_index': orderIndex,
    'title': title,
    'description': description,
    'objectives': objectives,
    'lesson': lesson,
    'questions': [for (final question in questions) question.toMap()],
    'status': status.name,
    'mastery': mastery,
    'attempts': attempts,
    'last_score': lastScore,
    'next_review_at': nextReviewAt?.toIso8601String(),
  };
}

class CourseAttemptResult {
  const CourseAttemptResult({
    required this.chapterId,
    required this.score,
    required this.passed,
    required this.message,
    required this.wrongQuestionIds,
    this.nextChapterId,
  });

  final String chapterId;
  final double score;
  final bool passed;
  final String message;
  final List<String> wrongQuestionIds;
  final String? nextChapterId;

  factory CourseAttemptResult.fromMap(Map<String, Object?> map) {
    final rawWrong = map['wrong_question_ids'];
    final rawPassed = map['passed'];
    return CourseAttemptResult(
      chapterId: map['chapter_id']?.toString() ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      passed: rawPassed == true || (rawPassed is num && rawPassed.toInt() == 1),
      message: map['message']?.toString() ?? '',
      wrongQuestionIds: rawWrong is List
          ? rawWrong.map((item) => item.toString()).toList(growable: false)
          : const [],
      nextChapterId: map['next_chapter_id']?.toString(),
    );
  }
}

class StudyWord {
  const StudyWord({
    required this.id,
    required this.userId,
    required this.word,
    required this.phonetic,
    required this.partOfSpeech,
    required this.translation,
    required this.exampleEnglish,
    required this.exampleChinese,
    required this.mastery,
    required this.intervalDays,
    required this.dueAt,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String word;
  final String phonetic;
  final String partOfSpeech;
  final String translation;
  final String exampleEnglish;
  final String exampleChinese;
  final int mastery;
  final int intervalDays;
  final DateTime dueAt;
  final DateTime createdAt;

  bool get isDue => !dueAt.isAfter(DateTime.now());
  bool get isNew => mastery == 0;

  factory StudyWord.fromMap(Map<String, Object?> map) {
    return StudyWord(
      id: map['id']! as int,
      userId: map['user_id']! as int,
      word: map['word']! as String,
      phonetic: map['phonetic']! as String,
      partOfSpeech: map['part_of_speech']! as String,
      translation: map['translation']! as String,
      exampleEnglish: map['example_en']! as String,
      exampleChinese: map['example_zh']! as String,
      mastery: map['mastery']! as int,
      intervalDays: map['interval_days']! as int,
      dueAt: DateTime.parse(map['due_at']! as String),
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'word': word,
      'phonetic': phonetic,
      'part_of_speech': partOfSpeech,
      'translation': translation,
      'example_en': exampleEnglish,
      'example_zh': exampleChinese,
      'mastery': mastery,
      'interval_days': intervalDays,
      'due_at': dueAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class StudyNote {
  const StudyNote({
    required this.id,
    required this.userId,
    required this.title,
    required this.contentEnglish,
    required this.contentChinese,
    required this.source,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final String title;
  final String contentEnglish;
  final String contentChinese;
  final String source;
  final DateTime updatedAt;

  factory StudyNote.fromMap(Map<String, Object?> map) {
    return StudyNote(
      id: map['id']! as int,
      userId: map['user_id']! as int,
      title: map['title']! as String,
      contentEnglish: map['content_en']! as String,
      contentChinese: map['content_zh']! as String,
      source: map['source']! as String,
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'content_en': contentEnglish,
      'content_zh': contentChinese,
      'source': source,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class CapturedDocument {
  const CapturedDocument({
    required this.id,
    required this.userId,
    required this.fileName,
    required this.filePath,
    required this.kind,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String fileName;
  final String filePath;
  final String kind;
  final String status;
  final DateTime createdAt;

  factory CapturedDocument.fromMap(Map<String, Object?> map) {
    return CapturedDocument(
      id: map['id']! as int,
      userId: map['user_id']! as int,
      fileName: map['file_name']! as String,
      filePath: map['file_path']! as String,
      kind: map['kind']! as String,
      status: map['status']! as String,
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'file_name': fileName,
      'file_path': filePath,
      'kind': kind,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class TodayStats {
  const TodayStats({
    required this.dueWords,
    required this.newWords,
    required this.reviewsCompleted,
    required this.minutes,
    required this.checkedIn,
  });

  const TodayStats.empty()
    : dueWords = 0,
      newWords = 0,
      reviewsCompleted = 0,
      minutes = 0,
      checkedIn = false;

  final int dueWords;
  final int newWords;
  final int reviewsCompleted;
  final int minutes;
  final bool checkedIn;

  double get progress {
    if (checkedIn) return 1;
    final total = dueWords + reviewsCompleted;
    if (total <= 0) return 0;
    return (reviewsCompleted / total).clamp(0, 1);
  }

  Map<String, dynamic> toMap() {
    return {
      'due_words': dueWords,
      'new_words': newWords,
      'reviews_completed': reviewsCompleted,
      'minutes': minutes,
      'checked_in': checkedIn,
    };
  }
}
