import 'dart:io';
import 'package:server/data/app_database.dart';
import 'package:server/core/security/secret_vault.dart';
import 'package:test/test.dart';

void main() {
  test(
    'recordings aggregate by Shanghai date and retries update the vault',
    () async {
      final dir = await Directory.systemTemp.createTemp('ailo-recording-test-');
      final db = await AppDatabase.open(
        dataDirectory: dir,
        secretVault: SecretVault.forTesting(List.filled(32, 17)),
      );
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final user = await db.createUser(
        email: 'recording@example.test',
        displayName: 'Test',
        passwordHash: '',
        passwordSalt: '',
      );
      Future<void> save(String id, String text) => db.saveRecordingDay(
        userId: user.id,
        recordingId: id,
        title: id,
        chinese: text,
        english: '',
        recordedAt: DateTime.parse('2026-09-09T18:00:00Z'),
      );
      await save('one', '旧摘要');
      await save('two', '第二段');
      await save('one', '修订摘要');
      final notes = await db.notesForUser(user.id);
      final day = notes.singleWhere((n) => n.source == '飞书录音每日总结:2026-09-10');
      expect(day.contentChinese, contains('共 2 段录音'));
      expect(day.contentChinese, contains('修订摘要'));
      expect(day.contentChinese, isNot(contains('旧摘要')));
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.contains('Recording Daily') && f.path.endsWith('.md'),
          )
          .toList();
      expect(files, hasLength(1));
      expect(await files.single.readAsString(), contains('修订摘要'));
    },
  );
}
