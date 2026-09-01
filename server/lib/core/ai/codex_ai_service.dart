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

  static const preferredLabel = 'chatgpt5.5';
  static const _preferredModelAliases = [
    'chatgpt5.5',
    'chatgpt-5.5',
    'gpt-5.5',
    'gpt-5.5-codex',
  ];

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
      final model = await _resolvePreferredModel(client);
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
        message: 'ChatGPT 登录已接通 Codex 额度，当前模型为 ${model ?? preferredLabel}。',
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

      final model = await _resolvePreferredModel(client);
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

  Future<CodexAppServerClient> _startClient() async {
    final client = CodexAppServerClient(
      executable: executable,
      arguments: arguments,
    );
    await client.start();
    return client;
  }

  Future<String?> _resolvePreferredModel(CodexAppServerClient client) async {
    try {
      final models = await client.listModels();
      for (final candidate in _preferredModelAliases) {
        if (models.contains(candidate)) return candidate;
      }
      for (final model in models) {
        final normalized = model.toLowerCase();
        if (normalized.contains('5.5')) return model;
      }
    } catch (_) {
      // Fall back to the server default when model discovery is unavailable.
    }
    return null;
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

  static List<Map<String, Object?>> _readItems(dynamic decoded) {
    if (decoded is Map<String, Object?>) {
      final items = decoded['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map<Map<String, Object?>>(
              (item) => Map<String, Object?>.from(item),
            )
            .toList(growable: false);
      }
    }
    throw const FormatException('Codex 返回的 JSON 缺少 items。');
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
