import 'package:ai_study_os/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI connection defaults to DeepSeek-V4-flash', () {
    expect(AiConnectionSettings.defaultModel, 'deepseek-v4-flash');
    expect(AiConnectionSettings.empty.model, 'deepseek-v4-flash');
    expect(AiConnectionSettings.defaultCodexModel, 'gpt-5.6-terra');
    expect(AiConnectionSettings.empty.provider, AiProvider.deepSeek);
  });

  test('retired Codex models migrate and stay inside model/list', () {
    expect(
      AiConnectionSettings.selectCodexModel(const [
        'gpt-5.6-sol',
        'gpt-5.6-terra',
      ], requested: 'gpt-5.4'),
      'gpt-5.6-terra',
    );
    expect(
      AiConnectionSettings.selectCodexModel(const [
        'future-codex-model',
      ], requested: 'gpt-5.4'),
      'future-codex-model',
    );
    expect(AiConnectionSettings.selectCodexModel(const []), isNull);
  });

  test('AI provider setting round-trips the API value', () {
    expect(AiProvider.fromApiValue('codex'), AiProvider.codex);
    expect(AiProvider.fromApiValue('deepseek'), AiProvider.deepSeek);
    expect(AiProvider.codex.apiValue, 'codex');
  });

  test(
    'AI connection accepts a typed key or server-configured encrypted key',
    () {
      const disabled = AiConnectionSettings(
        enabled: false,
        apiKey: 'sk-test',
        model: AiConnectionSettings.defaultModel,
      );
      const missingKey = AiConnectionSettings(
        enabled: true,
        apiKey: '   ',
        model: AiConnectionSettings.defaultModel,
      );
      const ready = AiConnectionSettings(
        enabled: true,
        apiKey: 'sk-test',
        model: AiConnectionSettings.defaultModel,
      );
      const serverReady = AiConnectionSettings(
        enabled: true,
        apiKey: '',
        model: AiConnectionSettings.defaultModel,
        apiKeyConfigured: true,
        apiKeyHint: '••••••••test',
        serverEncryptionReady: true,
      );

      expect(disabled.ready, isFalse);
      expect(missingKey.ready, isFalse);
      expect(ready.ready, isTrue);
      expect(ready.hasClientApiKey, isTrue);
      expect(serverReady.ready, isTrue);
      expect(serverReady.hasClientApiKey, isFalse);
    },
  );
}
