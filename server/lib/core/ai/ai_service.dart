import '../../domain/models.dart';
import '../../domain/word_parser.dart';

class AiConnectionProbe {
  const AiConnectionProbe({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class AiEnrichmentReport {
  const AiEnrichmentReport({
    required this.words,
    required this.requestedCount,
    required this.enrichedCount,
    this.warning,
  });

  final List<ParsedWord> words;
  final int requestedCount;
  final int enrichedCount;
  final String? warning;
}

abstract class AiService {
  Future<AiConnectionProbe> testConnection(AiConnectionSettings settings);

  Future<AiEnrichmentReport> enrichWords({
    required AiConnectionSettings settings,
    required List<ParsedWord> words,
  });
}

class NoopAiService implements AiService {
  const NoopAiService();

  @override
  Future<AiEnrichmentReport> enrichWords({
    required AiConnectionSettings settings,
    required List<ParsedWord> words,
  }) async {
    return AiEnrichmentReport(
      words: words,
      requestedCount: words.length,
      enrichedCount: 0,
      warning: '当前未启用联网 AI，已保留本地结果。',
    );
  }

  @override
  Future<AiConnectionProbe> testConnection(
    AiConnectionSettings settings,
  ) async {
    return const AiConnectionProbe(ok: false, message: '当前未启用联网 AI。');
  }
}
