import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:test/test.dart';

void main() {
  test(
    'schema 15 upgrades Codex login attempts and quiet-period guards',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ailo-codex-debounce-migration-',
      );
      final vault = SecretVault.forTesting(List.filled(32, 41));
      try {
        var app = await AppDatabase.open(
          dataDirectory: directory,
          secretVault: vault,
        );
        final databasePath = app.filePath;
        await app.close();

        ffi.sqfliteFfiInit();
        final legacy = await ffi.databaseFactoryFfi.openDatabase(databasePath);
        await legacy.execute('DROP TABLE codex_login_guards');
        await legacy.execute('DROP TABLE codex_login_attempts');
        await legacy.execute('''
        CREATE TABLE codex_login_attempts (
          attempt_id TEXT PRIMARY KEY,
          secret_hash TEXT NOT NULL,
          home_id TEXT NOT NULL,
          login_id TEXT NOT NULL,
          owner_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          expires_at TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          target_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          account_metadata TEXT,
          error_message TEXT
        )
      ''');
        await legacy.execute('PRAGMA user_version = 15');
        await legacy.close();

        app = await AppDatabase.open(
          dataDirectory: directory,
          secretVault: vault,
        );
        final attemptId = List.filled(48, 'a').join();
        await app.saveCodexLoginAttempt({
          'attempt_id': attemptId,
          'secret_hash': List.filled(64, 'b').join(),
          'home_id': List.filled(48, 'c').join(),
          'login_id': 'migration-login',
          'owner_user_id': null,
          'request_scope': 'client:${List.filled(64, 'd').join()}',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
        });
        final quietUntil = DateTime.now().toUtc().add(
          const Duration(seconds: 5),
        );
        await app.setCodexLoginQuietUntil('user:7', quietUntil);
        expect(await app.codexLoginQuietUntil('user:7'), quietUntil);
        expect(
          (await app.activeCodexLoginAttempts()).single['request_scope'],
          startsWith('client:'),
        );
        await app.close();

        expect(
          File(path.join(directory.path, 'ai_study_os.sqlite3')).existsSync(),
          true,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
