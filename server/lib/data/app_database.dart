import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../domain/learning_engine.dart';
import '../domain/course_catalog.dart';
import '../domain/models.dart';
import '../domain/security_policy.dart';
import '../domain/word_parser.dart';
import '../core/security/secret_vault.dart';

class AppDatabase {
  AppDatabase._(this._database, this.filePath, this._secretVault);

  final Database _database;
  final String filePath;
  final SecretVault _secretVault;

  bool get secretVaultReady => _secretVault.ready;
  String? get secretVaultConfigurationError => _secretVault.configurationError;

  static Future<AppDatabase> open({
    Directory? dataDirectory,
    SecretVault? secretVault,
  }) async {
    final supportDirectory =
        dataDirectory ?? Directory(path.join(Directory.current.path, 'data'));
    await supportDirectory.create(recursive: true);
    final databasePath = path.join(
      supportDirectory.path,
      'ai_study_os.sqlite3',
    );

    ffi.sqfliteFfiInit();
    final factory = ffi.databaseFactoryFfi;

    final database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 9,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createLoginSecurityTable(db);
          if (oldVersion < 3) await _createAiSettingsTable(db);
          if (oldVersion < 4) await _addExternalAuthColumns(db);
          if (oldVersion < 5) await _createConversationSyncTables(db);
          if (oldVersion < 6) await _createEmailSyncTables(db);
          if (oldVersion < 7) await _createCourseTables(db);
          // Versions below 5 create the conversation table as part of the
          // upgrade and therefore already receive the new columns above.
          if (oldVersion >= 5 && oldVersion < 8) {
            await _addAutoNoteScheduleColumns(db);
          }
        },
      ),
    );

    final appDatabase = AppDatabase._(
      database,
      databasePath,
      secretVault ?? SecretVault.fromEnvironment(),
    );
    await appDatabase._migrateAndValidateAiApiKey();
    return appDatabase;
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        auth_provider TEXT NOT NULL DEFAULT 'local',
        external_subject TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_session (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_id INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        word TEXT NOT NULL,
        phonetic TEXT NOT NULL,
        part_of_speech TEXT NOT NULL,
        translation TEXT NOT NULL,
        example_en TEXT NOT NULL,
        example_zh TEXT NOT NULL,
        mastery INTEGER NOT NULL DEFAULT 0,
        interval_days INTEGER NOT NULL DEFAULT 0,
        due_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(user_id, word),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE review_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        word_id INTEGER NOT NULL,
        rating INTEGER NOT NULL,
        reviewed_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE study_days (
        user_id INTEGER NOT NULL,
        day_key TEXT NOT NULL,
        minutes INTEGER NOT NULL DEFAULT 0,
        reviews_done INTEGER NOT NULL DEFAULT 0,
        new_words INTEGER NOT NULL DEFAULT 0,
        checked_in INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(user_id, day_key),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content_en TEXT NOT NULL,
        content_zh TEXT NOT NULL,
        source TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE captured_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await _createLoginSecurityTable(db);
    await _createAiSettingsTable(db);
    await _createExternalAuthIndex(db);
    await _createConversationSyncTables(db);
    await _createEmailSyncTables(db);
    await _createCourseTables(db);
    await db.execute('CREATE INDEX words_due_index ON words(user_id, due_at)');
    await db.execute(
      'CREATE INDEX reviews_date_index ON review_events(user_id, reviewed_at)',
    );
  }

  static Future<void> _createLoginSecurityTable(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS login_security (
        email TEXT PRIMARY KEY,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        last_failed_at TEXT
      )
    ''');
  }

  static Future<void> _createAiSettingsTable(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createConversationSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_sync_state (
        user_id INTEGER PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 0,
        schedule_configured INTEGER NOT NULL DEFAULT 0,
        interval_minutes INTEGER NOT NULL DEFAULT 15,
        status TEXT NOT NULL DEFAULT 'waiting',
        last_attempt_at TEXT,
        last_synced_at TEXT,
        last_synced_conversation_id TEXT,
        last_synced_title TEXT,
        last_error TEXT,
        last_nightly_run_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chatgpt_conversation_inbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        external_id TEXT NOT NULL,
        title TEXT NOT NULL,
        transcript TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_complete INTEGER NOT NULL DEFAULT 0,
        received_at TEXT NOT NULL,
        UNIQUE(user_id, external_id),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS conversation_inbox_order_index '
      'ON chatgpt_conversation_inbox(user_id, updated_at DESC)',
    );
  }

  static Future<void> _addAutoNoteScheduleColumns(Database db) async {
    // Existing schema-v7 databases have the old implicit enabled=1 behavior.
    // The new marker lets the client treat that legacy default as "not chosen"
    // while preserving an explicit choice made after this migration.
    await db.execute(
      'ALTER TABLE conversation_sync_state '
      'ADD COLUMN schedule_configured INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE conversation_sync_state ADD COLUMN last_nightly_run_at TEXT',
    );
  }

  static Future<void> _createEmailSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_sync_state (
        user_id INTEGER NOT NULL,
        provider TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        interval_minutes INTEGER NOT NULL DEFAULT 15,
        status TEXT NOT NULL DEFAULT 'waiting',
        last_attempt_at TEXT,
        last_synced_at TEXT,
        last_synced_message_id TEXT,
        last_synced_subject TEXT,
        last_error TEXT,
        PRIMARY KEY(user_id, provider),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_inbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        provider TEXT NOT NULL,
        external_id TEXT NOT NULL,
        subject TEXT NOT NULL,
        sender TEXT NOT NULL,
        recipients TEXT NOT NULL,
        body TEXT NOT NULL,
        received_at TEXT NOT NULL,
        is_complete INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT,
        UNIQUE(user_id, provider, external_id),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS email_inbox_order_index '
      'ON email_inbox(user_id, provider, synced_at, received_at DESC)',
    );
  }

  static Future<void> _createCourseTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_progress (
        user_id INTEGER NOT NULL,
        chapter_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'locked',
        mastery REAL NOT NULL DEFAULT 0,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_score REAL,
        next_review_at TEXT,
        mistakes_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL,
        PRIMARY KEY(user_id, chapter_id),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        chapter_id TEXT NOT NULL,
        score REAL NOT NULL,
        passed INTEGER NOT NULL,
        answers_json TEXT NOT NULL,
        mistakes_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS course_progress_order_index '
      'ON course_progress(user_id, status, updated_at DESC)',
    );
  }

  static Future<void> _addExternalAuthColumns(Database db) async {
    // SQLite does not support IF NOT EXISTS on ALTER TABLE. The version
    // gate above makes these statements run only once for databases created
    // by an earlier build.
    await db.execute(
      "ALTER TABLE users ADD COLUMN auth_provider TEXT NOT NULL DEFAULT 'local'",
    );
    await db.execute('ALTER TABLE users ADD COLUMN external_subject TEXT');
    await _createExternalAuthIndex(db);
  }

  static Future<void> _createExternalAuthIndex(Database db) {
    return db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS users_external_auth_index
      ON users(auth_provider, external_subject)
    ''');
  }

  Future<AppUser?> currentUser() async {
    final rows = await _database.rawQuery('''
      SELECT users.*
      FROM users
      INNER JOIN app_session ON app_session.user_id = users.id
      WHERE app_session.id = 1
      LIMIT 1
    ''');
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<StoredCredential?> credentialForEmail(String email) async {
    final rows = await _database.query(
      'users',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return StoredCredential(
      user: AppUser.fromMap(row),
      passwordHash: row['password_hash']! as String,
      passwordSalt: row['password_salt']! as String,
    );
  }

  Future<LoginSecurityState> loginSecurityForEmail(String email) async {
    final rows = await _database.query(
      'login_security',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty
        ? const LoginSecurityState.clear()
        : LoginSecurityState.fromMap(rows.first);
  }

  Future<LoginSecurityState> recordFailedLogin(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    final now = DateTime.now();
    return _database.transaction((transaction) async {
      final rows = await transaction.query(
        'login_security',
        where: 'email = ?',
        whereArgs: [normalizedEmail],
        limit: 1,
      );
      final previous = rows.isEmpty
          ? const LoginSecurityState.clear()
          : LoginSecurityState.fromMap(rows.first);
      final failedAttempts = math.min(30, previous.failedAttempts + 1);
      final lockDuration = SecurityPolicy.lockDurationForFailureCount(
        failedAttempts,
      );
      final lockedUntil = lockDuration == Duration.zero
          ? null
          : now.add(lockDuration);
      await transaction.insert('login_security', {
        'email': normalizedEmail,
        'failed_attempts': failedAttempts,
        'locked_until': lockedUntil?.toIso8601String(),
        'last_failed_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return LoginSecurityState(
        failedAttempts: failedAttempts,
        lockedUntil: lockedUntil,
        lastFailedAt: now,
      );
    });
  }

  Future<void> clearFailedLogins(String email) {
    return _database.delete(
      'login_security',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
    );
  }

  /// Converts the pre-v3 plaintext provider key to authenticated ciphertext.
  ///
  /// A deployment that already contains a provider key deliberately fails
  /// fast when its master key is absent or incorrect. Continuing in that state
  /// would either leave plaintext behind or make background jobs silently use
  /// an unavailable credential.
  Future<void> _migrateAndValidateAiApiKey() async {
    final rows = await _database.query(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: const ['deepseek_api_key', 'deepseek_api_key_encrypted_v1'],
    );
    final values = <String, String>{
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
    final legacy = values['deepseek_api_key']?.trim() ?? '';
    final encrypted = values['deepseek_api_key_encrypted_v1']?.trim() ?? '';

    if (encrypted.isNotEmpty) {
      if (!_secretVault.ready) {
        throw StateError(
          '数据库中已有加密的 DeepSeek API Key，但 ${SecretVault.environmentVariable} 未配置。',
        );
      }
      try {
        await _secretVault.decrypt(encrypted);
      } on SecretVaultException catch (error) {
        throw StateError('无法解密服务器中的 DeepSeek API Key：$error');
      }
      // An interrupted older migration may have left both rows behind. Once
      // the ciphertext has authenticated successfully, remove the plaintext.
      await _database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const ['deepseek_api_key'],
      );
      return;
    }

    if (legacy.isEmpty) {
      // Remove an old empty sentinel row; the absence of a row now represents
      // an unconfigured key.
      await _database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const ['deepseek_api_key'],
      );
      return;
    }

    if (!_secretVault.ready) {
      throw StateError(
        '检测到旧版明文 DeepSeek API Key。请先设置服务器环境变量 '
        '${SecretVault.environmentVariable}，服务器会在启动时自动加密迁移。',
      );
    }

    final cipherText = await _secretVault.encrypt(legacy);
    await _database.transaction((transaction) async {
      await transaction.insert('app_settings', {
        'key': 'deepseek_api_key_encrypted_v1',
        'value': cipherText,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.insert('app_settings', {
        'key': 'deepseek_api_key_hint',
        'value': _keyHint(legacy),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const ['deepseek_api_key'],
      );
    });
  }

  Future<AiConnectionSettings> aiSettings() async {
    final rows = await _database.query('app_settings');
    final values = <String, String>{
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
    final cipherText = values['deepseek_api_key_encrypted_v1']?.trim() ?? '';
    var apiKey = '';
    if (cipherText.isNotEmpty) {
      try {
        apiKey = await _secretVault.decrypt(cipherText);
      } on SecretVaultException catch (error) {
        throw StateError('服务器无法解密 DeepSeek API Key：$error');
      }
    }
    return AiConnectionSettings(
      enabled: values['deepseek_enabled'] == '1',
      apiKey: apiKey,
      model: _normalizeModel(values['deepseek_model'] ?? ''),
    );
  }

  Future<bool> aiApiKeyConfigured() async {
    final rows = await _database.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['deepseek_api_key_encrypted_v1'],
      limit: 1,
    );
    return rows.isNotEmpty &&
        (rows.first['value'] as String? ?? '').trim().isNotEmpty;
  }

  Future<String?> aiApiKeyHint() async {
    final rows = await _database.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['deepseek_api_key_hint'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final hint = (rows.first['value'] as String? ?? '').trim();
    return hint.isEmpty ? null : hint;
  }

  /// Saves a new key only as AES-256-GCM ciphertext. An empty [apiKey]
  /// preserves the already configured key so toggling the feature does not
  /// require the client to receive the secret again.
  Future<void> saveAiSettings(
    AiConnectionSettings settings, {
    bool clearApiKey = false,
  }) async {
    final apiKey = settings.apiKey.trim();
    String? encrypted;
    String? hint;
    if (apiKey.isNotEmpty) {
      if (!_secretVault.ready) {
        throw StateError(_secretVault.configurationError ?? '服务器密钥保险库尚未配置。');
      }
      encrypted = await _secretVault.encrypt(apiKey);
      hint = _keyHint(apiKey);
    }

    await _database.transaction((transaction) async {
      await transaction.insert('app_settings', {
        'key': 'deepseek_enabled',
        'value': settings.enabled ? '1' : '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.insert('app_settings', {
        'key': 'deepseek_model',
        'value': _normalizeModel(settings.model),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (clearApiKey) {
        await transaction.delete(
          'app_settings',
          where: 'key IN (?, ?, ?)',
          whereArgs: const [
            'deepseek_api_key',
            'deepseek_api_key_encrypted_v1',
            'deepseek_api_key_hint',
          ],
        );
      } else if (encrypted != null && hint != null) {
        await transaction.insert('app_settings', {
          'key': 'deepseek_api_key_encrypted_v1',
          'value': encrypted,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.insert('app_settings', {
          'key': 'deepseek_api_key_hint',
          'value': hint,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: const ['deepseek_api_key'],
        );
      }
    });
  }

  Future<AppUser> createUser({
    required String email,
    required String displayName,
    required String passwordHash,
    required String passwordSalt,
  }) async {
    final createdAt = DateTime.now();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = displayName.trim();
    final id = await _database.insert('users', {
      'email': normalizedEmail,
      'display_name': normalizedName,
      'password_hash': passwordHash,
      'password_salt': passwordSalt,
      'auth_provider': 'local',
      'external_subject': null,
      'created_at': createdAt.toIso8601String(),
    });
    return AppUser(
      id: id,
      email: normalizedEmail,
      displayName: normalizedName,
      createdAt: createdAt,
    );
  }

  Future<AppUser?> userForExternalAccount({
    required String provider,
    required String subject,
  }) async {
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedSubject = subject.trim();
    if (normalizedProvider.isEmpty || normalizedSubject.isEmpty) return null;
    final rows = await _database.query(
      'users',
      where: 'auth_provider = ? AND external_subject = ?',
      whereArgs: [normalizedProvider, normalizedSubject],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<AppUser> createExternalUser({
    required String provider,
    required String subject,
    required String email,
    required String displayName,
  }) async {
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedSubject = subject.trim();
    if (normalizedProvider.isEmpty || normalizedSubject.isEmpty) {
      throw ArgumentError('外部账号缺少有效的 provider 或 subject。');
    }

    final existing = await userForExternalAccount(
      provider: normalizedProvider,
      subject: normalizedSubject,
    );
    if (existing != null) return existing;

    final normalizedDisplayName = displayName.trim().isEmpty
        ? 'ChatGPT 用户'
        : displayName.trim();
    final requestedEmail = email.trim().toLowerCase();
    var normalizedEmail = requestedEmail;
    if (normalizedEmail.isEmpty ||
        await credentialForEmail(normalizedEmail) != null) {
      // The provider email may already belong to a local account. Do not
      // silently take over that account; use a stable local alias instead.
      normalizedEmail = 'chatgpt-$normalizedSubject@local.study';
    }

    final createdAt = DateTime.now();
    final id = await _database.insert('users', {
      'email': normalizedEmail,
      'display_name': normalizedDisplayName,
      // External accounts never authenticate with these fields. Empty
      // sentinels keep the existing schema compatible without storing a
      // password or provider token.
      'password_hash': '',
      'password_salt': '',
      'auth_provider': normalizedProvider,
      'external_subject': normalizedSubject,
      'created_at': createdAt.toIso8601String(),
    });
    return AppUser(
      id: id,
      email: normalizedEmail,
      displayName: normalizedDisplayName,
      createdAt: createdAt,
      authProvider: normalizedProvider,
      externalSubject: normalizedSubject,
    );
  }

  Future<void> setCurrentUser(int userId) async {
    await _database.insert('app_session', {
      'id': 1,
      'user_id': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearSession() => _database.delete('app_session');

  Future<void> seedStarterData(int userId) async {
    final countRows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM words WHERE user_id = ?',
      [userId],
    );
    final existing = (countRows.first['count']! as num).toInt();
    if (existing > 0) return;

    final starterWords = WordParser.parse(
      'abandon ability academic accomplish',
    );
    final now = DateTime.now();

    await _database.transaction((transaction) async {
      for (var index = 0; index < starterWords.length; index += 1) {
        final word = starterWords[index];
        await transaction.insert('words', {
          'user_id': userId,
          'word': word.word,
          'phonetic': word.phonetic,
          'part_of_speech': word.partOfSpeech,
          'translation': word.translation,
          'example_en': word.exampleEnglish,
          'example_zh': word.exampleChinese,
          'mastery': index == 1 ? 64 : index * 12,
          'interval_days': index == 1 ? 5 : 0,
          'due_at': index == 1
              ? now.add(const Duration(days: 2)).toIso8601String()
              : now.subtract(Duration(minutes: index + 1)).toIso8601String(),
          'created_at': now.toIso8601String(),
        });
      }

      await transaction.insert('notes', {
        'user_id': userId,
        'title': 'Photosynthesis',
        'content_en':
            'Photosynthesis converts light energy into chemical energy in plants.',
        'content_zh': '光合作用把光能转化为植物可利用的化学能。',
        'source': 'Biology Chapter 3',
        'updated_at': now.toIso8601String(),
      });
      await transaction.insert('notes', {
        'user_id': userId,
        'title': 'Active Recall',
        'content_en':
            'Try to retrieve an answer before looking at the source material.',
        'content_zh': '在查看原始资料前，先主动尝试回忆答案。',
        'source': 'Learning Methods',
        'updated_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      });
    });
  }

  Future<List<StudyWord>> wordsForUser(int userId) async {
    final rows = await _database.query(
      'words',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'due_at ASC, word COLLATE NOCASE ASC',
    );
    return rows.map(StudyWord.fromMap).toList(growable: false);
  }

  Future<int> pendingWordCount(int userId) async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM words '
      'WHERE user_id = ? AND $_pendingWordPredicate',
      [userId],
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<int>> userIdsWithPendingWords({int limit = 100}) async {
    final rows = await _database.rawQuery(
      'SELECT DISTINCT user_id FROM words '
      'WHERE $_pendingWordPredicate ORDER BY user_id ASC LIMIT ?',
      [limit.clamp(1, 1000)],
    );
    return rows
        .map((row) => (row['user_id'] as num).toInt())
        .toList(growable: false);
  }

  Future<List<ParsedWord>> pendingWordsForUser(
    int userId, {
    int limit = 20,
  }) async {
    final rows = await _database.query(
      'words',
      columns: const [
        'word',
        'phonetic',
        'part_of_speech',
        'translation',
        'example_en',
        'example_zh',
      ],
      where: 'user_id = ? AND $_pendingWordPredicate',
      whereArgs: [userId],
      orderBy: 'created_at ASC, id ASC',
      limit: limit.clamp(1, 100),
    );
    return [
      for (final row in rows)
        ParsedWord(
          word: row['word']! as String,
          phonetic: row['phonetic']! as String,
          partOfSpeech: row['part_of_speech']! as String,
          translation: row['translation']! as String,
          exampleEnglish: row['example_en']! as String,
          exampleChinese: row['example_zh']! as String,
        ),
    ];
  }

  Future<int> updateWordEnrichments({
    required int userId,
    required List<ParsedWord> words,
  }) async {
    var updated = 0;
    await _database.transaction((transaction) async {
      for (final word in words) {
        updated += await transaction.update(
          'words',
          {
            'phonetic': word.phonetic,
            'part_of_speech': word.partOfSpeech,
            'translation': word.translation,
            'example_en': word.exampleEnglish,
            'example_zh': word.exampleChinese,
          },
          where: 'user_id = ? AND word = ? COLLATE NOCASE',
          whereArgs: [userId, word.word.trim()],
        );
      }
    });
    return updated;
  }

  Future<int> insertWords({
    required int userId,
    required List<ParsedWord> words,
  }) async {
    var inserted = 0;
    final now = DateTime.now();
    await _database.transaction((transaction) async {
      for (final word in words) {
        final existingRows = await transaction.query(
          'words',
          columns: ['id'],
          where: 'user_id = ? AND word = ?',
          whereArgs: [userId, word.word],
          limit: 1,
        );
        final values = {
          'phonetic': word.phonetic,
          'part_of_speech': word.partOfSpeech,
          'translation': word.translation,
          'example_en': word.exampleEnglish,
          'example_zh': word.exampleChinese,
        };
        if (existingRows.isNotEmpty) {
          await transaction.update(
            'words',
            values,
            where: 'id = ?',
            whereArgs: [existingRows.first['id']],
          );
          inserted += 1;
          continue;
        }
        final id = await transaction.insert('words', {
          'user_id': userId,
          'word': word.word,
          ...values,
          'mastery': 0,
          'interval_days': 0,
          'due_at': now.toIso8601String(),
          'created_at': now.toIso8601String(),
        });
        if (id > 0) inserted += 1;
      }
    });
    return inserted;
  }

  Future<void> recordReview({
    required int userId,
    required StudyWord word,
    required ReviewRating rating,
    required ReviewSchedule schedule,
  }) async {
    final now = DateTime.now();
    final key = _dayKey(now);

    await _database.transaction((transaction) async {
      await transaction.update(
        'words',
        {
          'mastery': schedule.mastery,
          'interval_days': schedule.intervalDays,
          'due_at': schedule.dueAt.toIso8601String(),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [word.id, userId],
      );
      await transaction.insert('review_events', {
        'user_id': userId,
        'word_id': word.id,
        'rating': rating.databaseValue,
        'reviewed_at': now.toIso8601String(),
      });
      await transaction.rawInsert(
        '''
        INSERT INTO study_days
          (user_id, day_key, minutes, reviews_done, new_words, checked_in)
        VALUES (?, ?, 1, 1, 0, 0)
        ON CONFLICT(user_id, day_key) DO UPDATE SET
          minutes = minutes + 1,
          reviews_done = reviews_done + 1
      ''',
        [userId, key],
      );
    });
  }

  Future<List<StudyNote>> notesForUser(int userId) async {
    final rows = await _database.query(
      'notes',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(StudyNote.fromMap).toList(growable: false);
  }

  Future<void> addNote({
    required int userId,
    required String title,
    required String contentEnglish,
    required String contentChinese,
    required String source,
  }) async {
    await _database.insert('notes', {
      'user_id': userId,
      'title': title.trim(),
      'content_en': contentEnglish.trim(),
      'content_zh': contentChinese.trim(),
      'source': source.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<ConversationSyncState> conversationSyncState(int userId) async {
    final rows = await _database.query(
      'conversation_sync_state',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return ConversationSyncState.defaultState;
    return ConversationSyncState.fromMap(rows.first);
  }

  Future<void> saveConversationSyncState({
    required int userId,
    required ConversationSyncState state,
  }) async {
    await _database.insert('conversation_sync_state', {
      'user_id': userId,
      'enabled': state.enabled ? 1 : 0,
      'schedule_configured': state.scheduleConfigured ? 1 : 0,
      'interval_minutes': 15,
      'status': state.status.name,
      'last_attempt_at': state.lastAttemptAt?.toIso8601String(),
      'last_synced_at': state.lastSyncedAt?.toIso8601String(),
      'last_synced_conversation_id': state.lastSyncedConversationId,
      'last_synced_title': state.lastSyncedTitle,
      'last_error': state.lastError,
      'last_nightly_run_at': state.lastNightlyRunAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatGptConversationSnapshot>> conversationInbox(
    int userId,
  ) async {
    final rows = await _database.query(
      'chatgpt_conversation_inbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows
        .map(ChatGptConversationSnapshot.fromMap)
        .toList(growable: false);
  }

  Future<int> ingestConversationInbox({
    required int userId,
    required List<ChatGptConversationSnapshot> conversations,
  }) async {
    var accepted = 0;
    final receivedAt = DateTime.now().toIso8601String();
    await _database.transaction((transaction) async {
      for (final conversation in conversations) {
        if (conversation.externalId.trim().isEmpty ||
            conversation.transcript.trim().isEmpty) {
          continue;
        }
        await transaction.insert(
          'chatgpt_conversation_inbox',
          {
            'user_id': userId,
            'external_id': conversation.externalId.trim(),
            'title': conversation.title.trim().isEmpty
                ? 'ChatGPT 对话'
                : conversation.title.trim(),
            'transcript': conversation.transcript.trim(),
            'updated_at': conversation.updatedAt.toIso8601String(),
            'is_complete': conversation.isComplete ? 1 : 0,
            'received_at': receivedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        accepted += 1;
      }
    });
    return accepted;
  }

  Future<void> markConversationSynced({
    required int userId,
    required String conversationId,
    required String title,
    required DateTime syncedAt,
  }) async {
    final current = await conversationSyncState(userId);
    await saveConversationSyncState(
      userId: userId,
      state: current.copyWith(
        status: ConversationSyncStatus.synced,
        lastAttemptAt: syncedAt,
        lastSyncedAt: syncedAt,
        lastSyncedConversationId: conversationId,
        lastSyncedTitle: title,
        clearError: true,
      ),
    );
  }

  /// Writes an idempotent Markdown entry to the server-owned Obsidian vault.
  /// Source IDs are part of the filename, so a retry updates the same note
  /// instead of creating another copy.
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
    final vault = Directory(
      path.join(path.dirname(filePath), 'obsidian-vault', userId.toString()),
    );
    final categoryDirectory = Directory(
      path.join(vault.path, _safeVaultSegment(category, fallback: 'Inbox')),
    );
    await categoryDirectory.create(recursive: true);
    final fileName =
        '${_safeVaultSegment(title, fallback: 'note')}-${_safeVaultSegment(sourceId, fallback: 'manual')}.md';
    final normalizedTags = <String>{
      'ai-learning-os',
      'auto-summary',
      _safeVaultSegment(category, fallback: 'inbox').toLowerCase(),
      for (final tag in tags)
        if (tag.trim().isNotEmpty) _safeVaultSegment(tag).toLowerCase(),
    }.take(12).toList(growable: false);
    final content = StringBuffer()
      ..writeln('---')
      ..writeln('title: "${_yaml(title)}"')
      ..writeln('category: "${_yaml(category)}"')
      ..writeln('source: "${_yaml(source)}"')
      ..writeln('source_id: "${_yaml(sourceId)}"')
      ..writeln('updated: ${updatedAt.toIso8601String()}')
      ..writeln('ai_generated: true')
      ..writeln(
        'tags: [${normalizedTags.map((tag) => '"${_yaml(tag)}"').join(', ')}]',
      )
      ..writeln('---')
      ..writeln()
      ..writeln('# $title')
      ..writeln()
      ..writeln('> Source / 来源：$source')
      ..writeln()
      ..writeln('## English')
      ..writeln()
      ..writeln(
        contentEnglish.isEmpty ? '_No English summary_' : contentEnglish,
      )
      ..writeln()
      ..writeln('## 中文')
      ..writeln()
      ..writeln(contentChinese.isEmpty ? '_暂无中文摘要_' : contentChinese)
      ..writeln()
      ..writeln('## Knowledge graph')
      ..writeln()
      ..writeln('- [[${_safeVaultSegment(category, fallback: 'Inbox')}]]')
      ..writeln('- [[00 Index]]');
    await File(
      path.join(categoryDirectory.path, fileName),
    ).writeAsString(content.toString(), flush: true);

    final index = File(path.join(vault.path, '00 Index.md'));
    final existing = index.existsSync()
        ? await index.readAsString()
        : '# AILearningOS\n\n';
    final link =
        '- [[${_safeVaultSegment(category, fallback: 'Inbox')}/$fileName]]';
    if (!existing.split('\n').contains(link)) {
      await index.writeAsString('$existing$link\n', flush: true);
    }
  }

  static String _safeVaultSegment(String value, {String fallback = 'item'}) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty
        ? fallback
        : cleaned.substring(0, math.min(120, cleaned.length));
  }

  static String _yaml(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', ' ');

  Future<EmailSyncState> emailSyncState({
    required int userId,
    required EmailProvider provider,
  }) async {
    final rows = await _database.query(
      'email_sync_state',
      where: 'user_id = ? AND provider = ?',
      whereArgs: [userId, provider.apiValue],
      limit: 1,
    );
    if (rows.isEmpty) return EmailSyncState.defaultFor(provider);
    return EmailSyncState.fromMap(provider, rows.first);
  }

  Future<void> saveEmailSyncState({
    required int userId,
    required EmailSyncState state,
  }) async {
    await _database.insert('email_sync_state', {
      'user_id': userId,
      'provider': state.provider.apiValue,
      'enabled': state.enabled ? 1 : 0,
      'interval_minutes': 15,
      'status': state.status.name,
      'last_attempt_at': state.lastAttemptAt?.toIso8601String(),
      'last_synced_at': state.lastSyncedAt?.toIso8601String(),
      'last_synced_message_id': state.lastSyncedMessageId,
      'last_synced_subject': state.lastSyncedSubject,
      'last_error': state.lastError,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<EmailMessageSnapshot>> emailInbox({
    required int userId,
    required EmailProvider provider,
  }) async {
    final rows = await _database.query(
      'email_inbox',
      where: 'user_id = ? AND provider = ? AND synced_at IS NULL',
      whereArgs: [userId, provider.apiValue],
      orderBy: 'received_at DESC, id DESC',
      limit: 50,
    );
    return rows.map(EmailMessageSnapshot.fromMap).toList(growable: false);
  }

  Future<int> ingestEmailInbox({
    required int userId,
    required EmailProvider provider,
    required List<EmailMessageSnapshot> messages,
  }) async {
    var accepted = 0;
    await _database.transaction((transaction) async {
      for (final message in messages.take(50)) {
        if (message.provider != provider ||
            message.externalId.trim().isEmpty ||
            message.body.trim().isEmpty ||
            message.body.length > 100000) {
          continue;
        }
        final values = {
          'subject': message.subject.trim().isEmpty
              ? '(无主题)'
              : message.subject.trim(),
          'sender': message.sender.trim(),
          'recipients': message.recipients.trim(),
          'body': message.body.trim(),
          'received_at': message.receivedAt.toIso8601String(),
          'is_complete': message.isComplete ? 1 : 0,
        };
        final existing = await transaction.query(
          'email_inbox',
          columns: ['id'],
          where: 'user_id = ? AND provider = ? AND external_id = ?',
          whereArgs: [userId, provider.apiValue, message.externalId.trim()],
          limit: 1,
        );
        if (existing.isEmpty) {
          await transaction.insert('email_inbox', {
            'user_id': userId,
            'provider': provider.apiValue,
            'external_id': message.externalId.trim(),
            ...values,
            'synced_at': null,
          });
        } else {
          await transaction.update(
            'email_inbox',
            values,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
        accepted += 1;
      }
    });
    return accepted;
  }

  Future<void> markEmailSynced({
    required int userId,
    required EmailProvider provider,
    required String messageId,
    required String subject,
    required DateTime syncedAt,
  }) async {
    final current = await emailSyncState(userId: userId, provider: provider);
    await _database.transaction((transaction) async {
      await transaction.update(
        'email_inbox',
        {'synced_at': syncedAt.toIso8601String()},
        where: 'user_id = ? AND provider = ? AND external_id = ?',
        whereArgs: [userId, provider.apiValue, messageId],
      );
      await transaction.insert('email_sync_state', {
        'user_id': userId,
        'provider': provider.apiValue,
        'enabled': current.enabled ? 1 : 0,
        'interval_minutes': 15,
        'status': ConversationSyncStatus.synced.name,
        'last_attempt_at': syncedAt.toIso8601String(),
        'last_synced_at': syncedAt.toIso8601String(),
        'last_synced_message_id': messageId,
        'last_synced_subject': subject,
        'last_error': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<CourseChapter>> courseChapters(int userId) async {
    final rows = await _database.query(
      'course_progress',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final progressByChapter = <String, Map<String, Object?>>{
      for (final row in rows) row['chapter_id']! as String: row,
    };
    final result = <CourseChapter>[];
    var previousCompleted = true;
    for (final chapter in courseCatalog) {
      final progress = progressByChapter[chapter.chapterId];
      final storedStatus = progress == null
          ? CourseChapterStatus.locked
          : CourseChapterStatus.values.firstWhere(
              (item) => item.name == progress['status'],
              orElse: () => CourseChapterStatus.locked,
            );
      final status = storedStatus == CourseChapterStatus.completed
          ? CourseChapterStatus.completed
          : previousCompleted
          ? storedStatus == CourseChapterStatus.inProgress
                ? CourseChapterStatus.inProgress
                : CourseChapterStatus.available
          : CourseChapterStatus.locked;
      result.add(
        CourseChapter(
          chapterId: chapter.chapterId,
          phase: chapter.phase,
          orderIndex: chapter.orderIndex,
          title: chapter.title,
          description: chapter.description,
          objectives: chapter.objectives,
          lesson: chapter.lesson,
          questions: chapter.questions,
          status: status,
          mastery: (progress?['mastery'] as num?)?.toDouble() ?? 0,
          attempts: (progress?['attempts'] as num?)?.toInt() ?? 0,
          lastScore: (progress?['last_score'] as num?)?.toDouble(),
          nextReviewAt: DateTime.tryParse(
            progress?['next_review_at'] as String? ?? '',
          ),
        ),
      );
      previousCompleted = status == CourseChapterStatus.completed;
    }
    return result;
  }

  Future<CourseAttemptResult> submitCourseAttempt({
    required int userId,
    required String chapterId,
    required Map<String, int> answers,
  }) async {
    final chapter = courseChapterById(chapterId);
    if (chapter == null) throw StateError('找不到课程章节：$chapterId');
    if (chapter.questions.isEmpty) throw StateError('章节没有可测试的题目。');

    var correct = 0;
    final wrongQuestionIds = <String>[];
    for (final question in chapter.questions) {
      if (answers[question.id] == question.correctIndex) {
        correct += 1;
      } else {
        wrongQuestionIds.add(question.id);
      }
    }
    final score = correct / chapter.questions.length;
    final passed = score >= 0.8;
    final now = DateTime.now().toUtc();
    final previousRows = await _database.query(
      'course_progress',
      where: 'user_id = ? AND chapter_id = ?',
      whereArgs: [userId, chapterId],
      limit: 1,
    );
    final previous = previousRows.isEmpty ? null : previousRows.first;
    final attempts = (previous?['attempts'] as num?)?.toInt() ?? 0;
    final nextReview = now.add(Duration(days: passed ? 3 : 1));

    await _database.transaction((transaction) async {
      await transaction.insert('course_attempts', {
        'user_id': userId,
        'chapter_id': chapterId,
        'score': score,
        'passed': passed ? 1 : 0,
        'answers_json': jsonEncode(answers),
        'mistakes_json': jsonEncode(wrongQuestionIds),
        'created_at': now.toIso8601String(),
      });
      await transaction.insert('course_progress', {
        'user_id': userId,
        'chapter_id': chapterId,
        'status': passed
            ? CourseChapterStatus.completed.name
            : CourseChapterStatus.inProgress.name,
        'mastery': score,
        'attempts': attempts + 1,
        'last_score': score,
        'next_review_at': nextReview.toIso8601String(),
        'mistakes_json': jsonEncode(wrongQuestionIds),
        'updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    final next = passed
        ? courseCatalog
              .where((item) => item.orderIndex == chapter.orderIndex + 1)
              .firstOrNull
        : null;
    return CourseAttemptResult(
      chapterId: chapterId,
      score: score,
      passed: passed,
      message: passed ? '本章通过，下一章已解锁。' : '本章暂未通过，AI 会根据错题安排补课。',
      wrongQuestionIds: wrongQuestionIds,
      nextChapterId: next?.chapterId,
    );
  }

  Future<List<CapturedDocument>> capturesForUser(int userId) async {
    final rows = await _database.query(
      'captured_documents',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(CapturedDocument.fromMap).toList(growable: false);
  }

  Future<void> addCapture({
    required int userId,
    required String fileName,
    required String filePath,
    required String kind,
  }) async {
    await _database.insert('captured_documents', {
      'user_id': userId,
      'file_name': fileName,
      'file_path': filePath,
      'kind': kind,
      'status': '等待 OCR 接入',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<TodayStats> todayStats(int userId) async {
    final now = DateTime.now();
    final dueRows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM words WHERE user_id = ? AND due_at <= ?',
      [userId, now.toIso8601String()],
    );
    final newRows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM words WHERE user_id = ? AND mastery = 0',
      [userId],
    );
    final dayRows = await _database.query(
      'study_days',
      where: 'user_id = ? AND day_key = ?',
      whereArgs: [userId, _dayKey(now)],
      limit: 1,
    );

    final day = dayRows.isEmpty ? null : dayRows.first;
    return TodayStats(
      dueWords: (dueRows.first['count']! as num).toInt(),
      newWords: (newRows.first['count']! as num).toInt(),
      reviewsCompleted: (day?['reviews_done'] as num?)?.toInt() ?? 0,
      minutes: (day?['minutes'] as num?)?.toInt() ?? 0,
      checkedIn: ((day?['checked_in'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  Future<void> markCheckedIn(int userId) async {
    await _database.rawInsert(
      '''
      INSERT INTO study_days
        (user_id, day_key, minutes, reviews_done, new_words, checked_in)
      VALUES (?, ?, 30, 0, 0, 1)
      ON CONFLICT(user_id, day_key) DO UPDATE SET
        minutes = CASE WHEN minutes < 30 THEN 30 ELSE minutes END,
        checked_in = 1
    ''',
      [userId, _dayKey(DateTime.now())],
    );
  }

  Future<void> close() => _database.close();

  static String _normalizeModel(String value) {
    final model = value.trim().toLowerCase();
    if (model.isEmpty || model == 'deepseek-v4-flash') {
      return AiConnectionSettings.defaultModel;
    }
    if (model == 'deepseek-v4-pro') return model;
    return value.trim();
  }

  static String _keyHint(String apiKey) {
    final trimmed = apiKey.trim();
    final visible = trimmed.length <= 4
        ? trimmed
        : trimmed.substring(trimmed.length - 4);
    return '••••••••$visible';
  }

  static const _pendingWordPredicate = '''(
    translation = '待 AI 翻译'
    OR phonetic = '待生成'
    OR part_of_speech = '待识别'
    OR TRIM(part_of_speech) = ''
    OR TRIM(example_en) = ''
    OR TRIM(example_zh) = ''
  )''';

  static String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
