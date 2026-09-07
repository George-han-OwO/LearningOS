import '../../domain/models.dart';
import '../../domain/word_parser.dart';
import 'ai_service.dart';
import 'codex_ai_service.dart';
import 'deepseek_service.dart';

class HybridAiService implements AiService {
  const HybridAiService({
    this.codexService = const CodexAiService(),
    this.deepSeekService = const DeepSeekService(),
  });

  final CodexAiService codexService;
  final DeepSeekService deepSeekService;

  @override
  Future<AiConnectionProbe> testConnection(AiConnectionSettings settings) =>
      settings.usesCodex
      ? codexService.testConnection(settings)
      : deepSeekService.testConnection(settings);

  @override
  Future<AiEnrichmentReport> enrichWords({
    required AiConnectionSettings settings,
    required List<ParsedWord> words,
  }) => settings.usesCodex
      ? codexService.enrichWords(settings: settings, words: words)
      : deepSeekService.enrichWords(settings: settings, words: words);

  Future<String> completeText({
    required AiConnectionSettings settings,
    required String prompt,
  }) {
    if (settings.usesCodex) {
      throw StateError('Codex 需要由已登录的 App Server 网关执行。');
    }
    return deepSeekService.completeText(settings: settings, prompt: prompt);
  }
}
