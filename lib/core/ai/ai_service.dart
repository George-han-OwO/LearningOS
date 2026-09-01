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

class AiConversationAnalysis {
  const AiConversationAnalysis({
    required this.title,
    required this.summaryEnglish,
    required this.summaryChinese,
    required this.learnedConcepts,
    required this.actionItems,
    required this.words,
    this.category = 'Inbox',
    this.tags = const [],
    this.warning,
  });

  final String title;
  final String summaryEnglish;
  final String summaryChinese;
  final List<String> learnedConcepts;
  final List<String> actionItems;
  final List<ParsedWord> words;
  final String category;
  final List<String> tags;
  final String? warning;
}

abstract class AiService {
  Future<AiConnectionProbe> testConnection(AiConnectionSettings settings);

  Future<AiEnrichmentReport> enrichWords({
    required AiConnectionSettings settings,
    required List<ParsedWord> words,
  });

  Future<AiConversationAnalysis> analyzeConversation({
    required AiConnectionSettings settings,
    required String transcript,
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

  @override
  Future<AiConversationAnalysis> analyzeConversation({
    required AiConnectionSettings settings,
    required String transcript,
  }) async {
    return AiConversationAnalysis(
      title: 'AI 对话学习记录',
      summaryEnglish: 'Conversation captured for later review.',
      summaryChinese: '已保存原始对话；联网 AI 未启用，暂未生成学习摘要。',
      learnedConcepts: const [],
      actionItems: const [],
      words: WordParser.parse(transcript),
      warning: '当前未启用联网 AI，已先按文本提取候选词。',
    );
  }
}
