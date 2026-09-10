import 'dart:io';

import 'package:server/core/codex/codex_app_server_client.dart';
import 'package:server/core/codex/server_codex_gateway.dart';
import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:server/domain/models.dart';
import 'package:test/test.dart';

void main() {
  test(
    'backend restores Codex after its primary quota window resets',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ailo-auto-route-',
      );
      final database = await AppDatabase.open(
        dataDirectory: directory,
        secretVault: SecretVault.forTesting(List<int>.filled(32, 17)),
      );
      final user = await database.createUser(
        email: 'route-owner@example.test',
        displayName: 'Route Owner',
        passwordHash: '',
        passwordSalt: '',
      );
      await database.saveAiSettings(
        user.id,
        const AiConnectionSettings(
          enabled: true,
          apiKey: 'deepseek-key-for-fallback',
          model: AiConnectionSettings.defaultModel,
          provider: AiProvider.codex,
          autoReturnToCodex: true,
        ),
      );
      await database.bindCodexHome(
        userId: user.id,
        homeId: 'test_codex_home_1234567890',
      );
      await database.scheduleCodexReturn(
        user.id,
        DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      );

      final gateway = _Gateway(
        database,
        clientFactory: (_) async => _QuotaClient(),
      );
      addTearDown(() async {
        await gateway.dispose();
        await database.close();
        await directory.delete(recursive: true);
      });

      expect(
        (await database.aiSettings(user.id)).provider,
        AiProvider.deepSeek,
      );
      expect(await gateway.restoreDueCodexProviders(), 1);

      final restored = await database.aiSettings(user.id);
      expect(restored.provider, AiProvider.codex);
      expect(restored.autoReturnToCodex, isTrue);
      expect(restored.codexResumeAt, isNull);
    },
  );

  test('recognizes App Server wording when Codex has reached a usage cap', () {
    expect(
      ServerCodexGateway.isQuotaFailure(
        StateError('You have reached the limit for this Codex usage window.'),
      ),
      isTrue,
    );
    expect(
      ServerCodexGateway.isQuotaFailure(
        StateError('resource exhausted: too many requests'),
      ),
      isTrue,
    );
    expect(
      ServerCodexGateway.isQuotaFailure(
        StateError('selected model is unavailable'),
      ),
      isFalse,
    );
  });

  test(
    'does not restore Codex while its longer quota window is still full',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ailo-long-window-route-',
      );
      final database = await AppDatabase.open(
        dataDirectory: directory,
        secretVault: SecretVault.forTesting(List<int>.filled(32, 18)),
      );
      final user = await database.createUser(
        email: 'long-window-owner@example.test',
        displayName: 'Long Window Owner',
        passwordHash: '',
        passwordSalt: '',
      );
      await database.saveAiSettings(
        user.id,
        const AiConnectionSettings(
          enabled: true,
          apiKey: 'deepseek-key-for-fallback',
          model: AiConnectionSettings.defaultModel,
          provider: AiProvider.deepSeek,
          autoReturnToCodex: true,
        ),
      );
      await database.bindCodexHome(
        userId: user.id,
        homeId: 'test_codex_home_long_window_12345',
      );
      await database.scheduleCodexReturn(
        user.id,
        DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      );
      final gateway = _Gateway(
        database,
        clientFactory: (_) async => _LongWindowQuotaClient(),
      );
      addTearDown(() async {
        await gateway.dispose();
        await database.close();
        await directory.delete(recursive: true);
      });

      expect(await gateway.restoreDueCodexProviders(), 0);
      final unchanged = await database.aiSettings(user.id);
      expect(unchanged.provider, AiProvider.deepSeek);
      expect(
        unchanged.codexResumeAt,
        isNotNull,
        reason: 'The longer exhausted window must delay the next Codex retry.',
      );
    },
  );
}

class _Gateway extends ServerCodexGateway {
  _Gateway(super.database, {super.clientFactory});

  @override
  bool get enabled => true;
}

class _QuotaClient extends CodexAppServerClient {
  @override
  bool get isInitialized => true;

  @override
  Future<CodexQuota> readRateLimits() async => CodexQuota(
    planType: 'plus',
    primary: CodexRateLimitWindow(
      usedPercent: 12,
      windowDurationMinutes: 300,
      resetsAt: DateTime.now().toUtc().add(const Duration(hours: 5)),
    ),
  );

  @override
  Future<void> dispose() async {}
}

class _LongWindowQuotaClient extends CodexAppServerClient {
  @override
  bool get isInitialized => true;

  @override
  Future<CodexQuota> readRateLimits() async => CodexQuota(
    planType: 'plus',
    primary: CodexRateLimitWindow(
      usedPercent: 15,
      windowDurationMinutes: 300,
      resetsAt: DateTime.now().toUtc().add(const Duration(hours: 4)),
    ),
    secondary: CodexRateLimitWindow(
      usedPercent: 100,
      windowDurationMinutes: 10080,
      resetsAt: DateTime.now().toUtc().add(const Duration(days: 5)),
    ),
  );

  @override
  Future<void> dispose() async {}
}
