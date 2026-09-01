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
  Future<AiConnectionProbe> testConnection(
    AiConnectionSettings settings,
  ) async {
    final codexProbe = await codexService.testConnection(settings);
    if (codexProbe.ok) return codexProbe;
    if (settings.hasClientApiKey) {
      return deepSeekService.testConnection(settings);
    }
    return codexProbe;
  }

  @override
  Future<AiEnrichmentReport> enrichWords({
    required AiConnectionSettings settings,
    required List<ParsedWord> words,
  }) async {
    final codexProbe = await codexService.testConnection(settings);
    if (codexProbe.ok) {
      final report = await codexService.enrichWords(
        settings: settings,
        words: words,
      );
      if (report.enrichedCount > 0 || report.warning == null) {
        return report;
      }
    }
    return deepSeekService.enrichWords(settings: settings, words: words);
  }

  @override
  Future<AiConversationAnalysis> analyzeConversation({
    required AiConnectionSettings settings,
    required String transcript,
  }) async {
    final codex = await codexService.analyzeConversation(
      settings: settings,
      transcript: transcript,
    );
    if (codex.warning == null) return codex;
    if (settings.hasClientApiKey) {
      return deepSeekService.analyzeConversation(
        settings: settings,
        transcript: transcript,
      );
    }
    return codex;
  }
}
