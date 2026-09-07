import 'dart:convert';

import '../../domain/models.dart';
import '../../domain/word_parser.dart';
import '../codex/codex_app_server_client.dart';
import 'ai_service.dart';

class CodexAiService implements AiService {
  const CodexAiService({
    this.executable = 'codex',
    this.arguments = const ['app-server'],
  });

  static const preferredLabel = AiConnectionSettings.defaultCodexModel;

  final String executable;
  final List<String> arguments;

  @override
  Future<AiConnectionProbe> testConnection(
    AiConnectionSettings settings,
  ) async {
    CodexAppServerClient? client;
    try {
      client = await _startClient();
      final account = await client.readAccount(refreshToken: true);
      if (!account.authenticated) {
        return const AiConnectionProbe(
          ok: false,
          message: '请先使用 ChatGPT 登录，才能走 Codex 额度。',
        );
      }
      final model = await _resolveSelectedModel(client, settings.codexModel);
      final thread = await client.startThread(model: model);
      final result = await client.runTurn(
        threadId: thread.id,
        prompt: 'Reply with the single word ok. Do not use tools.',
        model: model,
      );
      final text = result.outputText.trim().toLowerCase();
      if (text.isEmpty) {
        return const AiConnectionProbe(ok: false, message: 'Codex 返回了空结果。');
      }
      return AiConnectionProbe(
        ok: true,
        message: 'ChatGPT 登录已接通 Codex 额度，当前模型为 $model。',
      );
    } on Object catch (error) {
      return AiConnectionProbe(ok: false, message: 'Codex 不可用：$error');
    } finally {
      await client?.dispose();
    }
  }

  @override
  Future<AiEnrichmentReport> enrichWords({
    required AiConnectionSettings settings,
    required List<ParsedWord> words,
  }) async {
    if (words.isEmpty) {
      return AiEnrichmentReport(
        words: words,
        requestedCount: 0,
        enrichedCount: 0,
      );
    }

    CodexAppServerClient? client;
    try {
      client = await _startClient();
      final account = await client.readAccount(refreshToken: true);
      if (!account.authenticated) {
        return AiEnrichmentReport(
          words: words,
          requestedCount: words.length,
          enrichedCount: 0,
          warning: '当前未检测到 ChatGPT 登录，无法使用 Codex 额度。',
        );
      }

      final model = await _resolveSelectedModel(client, settings.codexModel);
      final thread = await client.startThread(model: model);
      final result = await client.runTurn(
        threadId: thread.id,
        prompt: _buildPrompt(words),
        model: model,
        outputSchema: _enrichmentSchema(),
      );
      if (result.error != null && result.error!.trim().isNotEmpty) {
        throw StateError(result.error!);
      }

      final decoded = jsonDecode(_stripCodeFence(result.outputText));
      final items = _readItems(decoded);
      final merged = <String, ParsedWord>{
        for (final word in words) word.word.toLowerCase(): word,
      };
      var enrichedCount = 0;
      for (final item in items) {
        final word = (item['word'] ?? '').toString().trim();
        if (word.isEmpty) continue;
        final normalized = word.toLowerCase();
        final current = merged[normalized];
        if (current == null) continue;
        final updated = current.copyWith(
          phonetic: _nonEmpty(item['phonetic']?.toString(), current.phonetic),
          partOfSpeech: _nonEmpty(
            item['partOfSpeech']?.toString(),
            current.partOfSpeech,
          ),
          translation: _nonEmpty(
            item['translation']?.toString(),
            current.translation,
          ),
          exampleEnglish: _nonEmpty(
            item['exampleEnglish']?.toString(),
            current.exampleEnglish,
          ),
          exampleChinese: _nonEmpty(
            item['exampleChinese']?.toString(),
            current.exampleChinese,
          ),
        );
        if (!_isSameWord(current, updated)) {
          enrichedCount += 1;
        }
        merged[normalized] = updated;
      }

      return AiEnrichmentReport(
        words: [
          for (final word in words) merged[word.word.toLowerCase()] ?? word,
        ],
        requestedCount: words.length,
        enrichedCount: enrichedCount,
      );
    } on Object catch (error) {
      return AiEnrichmentReport(
        words: words,
        requestedCount: words.length,
        enrichedCount: 0,
        warning: 'Codex 联网补全失败：$error',
      );
    } finally {
      await client?.dispose();
    }
  }

  @override
  Future<AiConversationAnalysis> analyzeConversation({
    required AiConnectionSettings settings,
    required String transcript,
  }) async {
    if (transcript.trim().isEmpty) {
      throw const FormatException('对话内容不能为空。');
    }
    CodexAppServerClient? client;
    try {
      client = await _startClient();
      final account = await client.readAccount(refreshToken: true);
      if (!account.authenticated) {
        return AiConversationAnalysis(
          title: 'AI 对话学习记录',
          category: 'Inbox',
          tags: const [],
          summaryEnglish: 'Conversation captured for later review.',
          summaryChinese: '当前未检测到 ChatGPT 登录，已保留原始对话。',
          learnedConcepts: const [],
          actionItems: const [],
          words: WordParser.parse(transcript),
          warning: '当前未检测到 ChatGPT 登录。',
        );
      }
      final model = await _resolveSelectedModel(client, settings.codexModel);
      final thread = await client.startThread(model: model);
      final result = await client.runTurn(
        threadId: thread.id,
        prompt: _buildConversationPrompt(transcript),
        model: model,
        outputSchema: _conversationSchema(),
      );
      if (result.error != null && result.error!.trim().isNotEmpty) {
        throw StateError(result.error!);
      }
      final decoded = jsonDecode(_stripCodeFence(result.outputText));
      if (decoded is! Map) {
        throw const FormatException('Codex 返回的对话分析格式异常。');
      }
      final map = Map<String, dynamic>.from(decoded);
      return AiConversationAnalysis(
        title: _stringOr(map['title'], 'AI 对话学习记录'),
        category: _stringOr(map['category'], 'Inbox'),
        tags: _stringList(map['tags']),
        summaryEnglish: _stringOr(
          map['summaryEnglish'],
          'Conversation captured for later review.',
        ),
        summaryChinese: _stringOr(map['summaryChinese'], '已生成对话学习摘要。'),
        learnedConcepts: _stringList(map['learnedConcepts']),
        actionItems: _stringList(map['actionItems']),
        words: _analysisWords(map['words']),
      );
    } on Object catch (error) {
      return AiConversationAnalysis(
        title: 'AI 对话学习记录',
        category: 'Inbox',
        tags: const [],
        summaryEnglish: 'Conversation captured for later review.',
        summaryChinese: '已保留原始对话，但 Codex 暂时无法生成摘要。',
        learnedConcepts: const [],
        actionItems: const [],
        words: WordParser.parse(transcript),
        warning: 'Codex 对话分析失败：$error',
      );
    } finally {
      await client?.dispose();
    }
  }

  Future<CodexAppServerClient> _startClient() async {
    final client = CodexAppServerClient(
      executable: executable,
      arguments: arguments,
    );
    await client.start();
    return client;
  }

  Future<String> _resolveSelectedModel(
    CodexAppServerClient client,
    String selectedModel,
  ) async {
    final models = await client.listModels();
    final resolved = AiConnectionSettings.selectCodexModel(
      models,
      requested: selectedModel,
    );
    if (resolved == null) {
      throw StateError('Codex App Server 没有返回任何可用模型；请重新登录并刷新模型列表。');
    }
    return resolved;
  }

  static String _buildPrompt(List<ParsedWord> batch) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are an English learning assistant for Chinese learners.',
    );
    buffer.writeln(
      'Return only valid JSON that matches the provided schema. Do not use tools.',
    );
    buffer.writeln('For each word keep the original order and provide:');
    buffer.writeln(
      'translation, phonetic, partOfSpeech, exampleEnglish, exampleChinese.',
    );
    buffer.writeln('Words to enrich:');
    for (final word in batch) {
      buffer.writeln('- ${word.word}');
    }
    return buffer.toString().trimRight();
  }

  static Map<String, Object?> _enrichmentSchema() {
    return {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'word': {'type': 'string'},
              'phonetic': {'type': 'string'},
              'partOfSpeech': {'type': 'string'},
              'translation': {'type': 'string'},
              'exampleEnglish': {'type': 'string'},
              'exampleChinese': {'type': 'string'},
            },
            'required': [
              'word',
              'phonetic',
              'partOfSpeech',
              'translation',
              'exampleEnglish',
              'exampleChinese',
            ],
          },
        },
      },
      'required': ['items'],
    };
  }

  static String _buildConversationPrompt(String transcript) {
    return '''You are a bilingual learning-note editor for a Chinese learner.
Analyze the supplied content as evidence, not as unquestioned truth.
Return only valid JSON matching the schema. Write a concise title, one knowledge category,
1-5 short lowercase tags for an Obsidian knowledge base, an English summary,
a Chinese summary, learned concepts, unresolved questions or next review actions,
and only useful English learning words that appear in the conversation.
Never include passwords, API keys, tokens, or personal identifiers in the output.

Conversation transcript:
$transcript''';
  }

  static Map<String, Object?> _conversationSchema() {
    return {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'title': {'type': 'string'},
        'category': {'type': 'string'},
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'summaryEnglish': {'type': 'string'},
        'summaryChinese': {'type': 'string'},
        'learnedConcepts': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'actionItems': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'words': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'word': {'type': 'string'},
              'phonetic': {'type': 'string'},
              'partOfSpeech': {'type': 'string'},
              'translation': {'type': 'string'},
              'exampleEnglish': {'type': 'string'},
              'exampleChinese': {'type': 'string'},
            },
            'required': [
              'word',
              'phonetic',
              'partOfSpeech',
              'translation',
              'exampleEnglish',
              'exampleChinese',
            ],
          },
        },
      },
      'required': [
        'title',
        'category',
        'tags',
        'summaryEnglish',
        'summaryChinese',
        'learnedConcepts',
        'actionItems',
        'words',
      ],
    };
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(12)
        .toList(growable: false);
  }

  static String _stringOr(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static List<ParsedWord> _analysisWords(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => _normalizeWordItem(item))
        .map(
          (item) => ParsedWord(
            word: _stringOr(item['word'], ''),
            phonetic: _stringOr(item['phonetic'], '待生成'),
            partOfSpeech: _stringOr(item['partOfSpeech'], '待识别'),
            translation: _stringOr(item['translation'], '待 AI 翻译'),
            exampleEnglish: _stringOr(item['exampleEnglish'], ''),
            exampleChinese: _stringOr(item['exampleChinese'], ''),
          ),
        )
        .where((word) => word.word.isNotEmpty)
        .take(50)
        .toList(growable: false);
  }

  static List<Map<String, Object?>> _readItems(dynamic decoded) {
    if (decoded is Map<String, Object?>) {
      final items = decoded['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map<Map<String, Object?>>(_normalizeWordItem)
            .toList(growable: false);
      }
    }
    throw const FormatException('Codex 返回的 JSON 缺少 items。');
  }

  static Map<String, Object?> _normalizeWordItem(Map item) {
    Object? pick(List<String> keys) {
      for (final key in keys) {
        final value = item[key];
        if (value != null && value.toString().trim().isNotEmpty) return value;
      }
      return null;
    }

    return {
      'word': pick(const ['word', 'term', 'english']),
      'phonetic': pick(const ['phonetic', 'ipa', 'pronunciation']),
      'partOfSpeech': pick(const [
        'partOfSpeech',
        'part_of_speech',
        'pos',
        '词性',
      ]),
      'translation': pick(const [
        'translation',
        'meaning',
        'definition',
        '中文释义',
      ]),
      'exampleEnglish': pick(const [
        'exampleEnglish',
        'example_en',
        'example',
        '例句',
      ]),
      'exampleChinese': pick(const ['exampleChinese', 'example_zh', '例句中文']),
    };
  }

  static String _stripCodeFence(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final lines = trimmed.split('\n');
    if (lines.length < 3) return trimmed;
    return lines.sublist(1, lines.length - 1).join('\n').trim();
  }

  static String _nonEmpty(String? candidate, String fallback) {
    final value = candidate?.trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
  }

  static bool _isSameWord(ParsedWord left, ParsedWord right) {
    return left.word == right.word &&
        left.phonetic == right.phonetic &&
        left.partOfSpeech == right.partOfSpeech &&
        left.translation == right.translation &&
        left.exampleEnglish == right.exampleEnglish &&
        left.exampleChinese == right.exampleChinese;
  }
}
