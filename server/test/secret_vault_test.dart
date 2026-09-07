import 'dart:io';

import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:server/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('SecretVault', () {
    test('AES-256-GCM round trip does not expose plaintext', () async {
      final vault = SecretVault.forTesting(List<int>.generate(32, (i) => i));

      final encrypted = await vault.encrypt('test-provider-key-private');

      expect(encrypted, startsWith('v1.'));
      expect(encrypted, isNot(contains('test-provider-key-private')));
      expect(await vault.decrypt(encrypted), 'test-provider-key-private');
    });

    test('tampering and a different master key are rejected', () async {
      final vault = SecretVault.forTesting(List<int>.filled(32, 7));
      final otherVault = SecretVault.forTesting(List<int>.filled(32, 8));
      final encrypted = await vault.encrypt('test-provider-key-short');
      final parts = encrypted.split('.');
      final last = parts[2][parts[2].length - 1];
      parts[2] =
          '${parts[2].substring(0, parts[2].length - 1)}${last == 'A' ? 'B' : 'A'}';

      expect(
        () => vault.decrypt(parts.join('.')),
        throwsA(isA<SecretVaultException>()),
      );
      expect(
        () => otherVault.decrypt(encrypted),
        throwsA(isA<SecretVaultException>()),
      );
    });

    test('environment key accepts generated base64url format', () async {
      final generated = SecretVault.generateMasterKey();
      final vault = SecretVault.fromEnvironment({
        SecretVault.environmentVariable: generated,
      });

      expect(vault.ready, isTrue);
      expect(await vault.decrypt(await vault.encrypt('secret')), 'secret');
    });
  });

  group('encrypted AI settings', () {
    late Directory dataDirectory;

    setUp(() async {
      dataDirectory = await Directory.systemTemp.createTemp(
        'ailo-secret-vault-',
      );
    });

    tearDown(() async {
      if (await dataDirectory.exists()) {
        await dataDirectory.delete(recursive: true);
      }
    });

    test('stores only ciphertext and can decrypt after restart', () async {
      final vault = SecretVault.forTesting(List<int>.filled(32, 23));
      final database = await AppDatabase.open(
        dataDirectory: dataDirectory,
        secretVault: vault,
      );
      final user = await database.createUser(
        email: 'vault-owner@test.local',
        displayName: 'Vault Owner',
        passwordHash: '',
        passwordSalt: '',
      );
      await database.setCurrentUser(user.id);
      await database.saveAiSettings(
        user.id,
        const AiConnectionSettings(
          enabled: true,
          apiKey: 'test-provider-key-never-store-this-plaintext',
          model: AiConnectionSettings.defaultModel,
          provider: AiProvider.codex,
          codexModel: AiConnectionSettings.defaultCodexModel,
        ),
      );
      final databasePath = database.filePath;
      await database.close();

      sqfliteFfiInit();
      final rawDatabase = await databaseFactoryFfi.openDatabase(databasePath);
      final rows = await rawDatabase.query('user_ai_settings');
      await rawDatabase.close();
      expect(rows, hasLength(1));
      final values = rows.single;
      expect(values['user_id'], user.id);
      expect(
        values['deepseek_api_key_encrypted_v1'],
        allOf(startsWith('v1.'), isNot(contains('test-provider-key-never'))),
      );

      final reopened = await AppDatabase.open(
        dataDirectory: dataDirectory,
        secretVault: vault,
      );
      final reopenedSettings = await reopened.aiSettings(user.id);
      expect(
        reopenedSettings.apiKey,
        'test-provider-key-never-store-this-plaintext',
      );
      expect(reopenedSettings.provider, AiProvider.codex);
      expect(reopenedSettings.codexModel, 'gpt-5.6-terra');
      await reopened.close();
    });

    test('migrates a legacy plaintext key and removes its row', () async {
      final emptyDatabase = await AppDatabase.open(
        dataDirectory: dataDirectory,
        secretVault: SecretVault.fromEnvironment(const {}),
      );
      final user = await emptyDatabase.createUser(
        email: 'legacy-owner@test.local',
        displayName: 'Legacy Owner',
        passwordHash: '',
        passwordSalt: '',
      );
      await emptyDatabase.setCurrentUser(user.id);
      final databasePath = emptyDatabase.filePath;
      await emptyDatabase.close();

      sqfliteFfiInit();
      final rawDatabase = await databaseFactoryFfi.openDatabase(databasePath);
      await rawDatabase.insert('app_settings', {
        'key': 'deepseek_api_key',
        'value': 'test-provider-key-legacy-plaintext',
      });
      await rawDatabase.close();

      final vault = SecretVault.forTesting(List<int>.filled(32, 31));
      final migrated = await AppDatabase.open(
        dataDirectory: dataDirectory,
        secretVault: vault,
      );
      expect(
        (await migrated.aiSettings(user.id)).apiKey,
        'test-provider-key-legacy-plaintext',
      );
      await migrated.close();

      final inspection = await databaseFactoryFfi.openDatabase(databasePath);
      final rows = await inspection.query('app_settings');
      final userRows = await inspection.query('user_ai_settings');
      await inspection.close();
      final keys = rows.map((row) => row['key']).toSet();
      expect(keys, isNot(contains('deepseek_api_key')));
      expect(keys, isNot(contains('deepseek_api_key_encrypted_v1')));
      expect(userRows, hasLength(1));
      expect(userRows.single['user_id'], user.id);
      expect(
        userRows.single['deepseek_api_key_encrypted_v1'],
        startsWith('v1.'),
      );
    });
  });
}
