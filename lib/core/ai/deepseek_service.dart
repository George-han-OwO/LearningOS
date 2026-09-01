import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../domain/models.dart';
import '../../domain/word_parser.dart';
import 'ai_service.dart';

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeepSeekService implements AiService {
  const DeepSeekService({
    this.endpoint = 'https://api.deepseek.com/chat/completions',
    this.batchSize = 20,
    this.timeout = const Duration(seconds: 75),
  });

  final String endpoint;
  final int batchSize;
  final Duration timeout;

  @override
  Future<AiConnectionProbe> testConnection(
    AiConnectionSettings settings,
  ) async {
    if (!settings.hasClientApiKey) {
      return const AiConnectionProbe(
        ok: false,
        message: '请先启用联网 AI 并填写 DeepSeek API Key。',
      );
    }

    final body = await _postJson(
      settings: settings,
      body: {
        'model': _resolveModel(settings),
        'messages': const [
          {
            'role': 'system',
            'content': 'You are a terse connectivity test. Reply with ok only.',
          },
          {'role': 'user', 'content': 'Confirm the connection is working.'},
        ],
        'stream': false,
        'max_tokens': 12,
        'temperature': 0,
        'thinking': const {'type': 'disabled'},
      },
    );
    final responseText = _extractResponseText(body);
    final text = responseText?.trim().toLowerCase();
    if (text == null || text.isEmpty) {
      throw const AiServiceException('DeepSeek 返回了空结果。');
    }
    if (text.contains('ok')) {
      return AiConnectionProbe(
        ok: true,
        message: 'DeepSeek 已连通，模型 ${_resolveModel(settings)} 响应正常。',
      );
    }
    return AiConnectionProbe(
      ok: true,
      message: 'DeepSeek 已连通，模型 ${_resolveModel(settings)} 返回：$text',
    );
  }

  @override
  Future<AiConversationAnalysis> analyzeConversation({
    required AiConnectionSettings settings,
    required String transcript,
  }) async {
    if (transcript.trim().isEmpty) {
      throw const AiServiceException('对话内容不能为空。');
    }
    if (!settings.hasClientApiKey) {
      return const AiConversationAnalysis(
        title: 'AI 对话学习记录',
        summaryEnglish: 'Conversation captured for later review.',
        summaryChinese: '联网 AI 未启用。',
        learnedConcepts: [],
        actionItems: [],
        words: [],
        warning: '请先启用 DeepSeek API，再分析对话。',
      );
    }
    final response = await _postJson(
      settings: settings,
      body: {
        'model': _resolveModel(settings),
        'messages': [
          {
            'role': 'system',
            'content':
                '''You are a bilingual learning evidence analyst for a Chinese learner.
Analyze the supplied content as evidence, not as unquestioned truth.
Return only JSON with title, category, tags, summaryEnglish, summaryChinese, learnedConcepts, actionItems, and words.
category must be one concise knowledge-area name such as Learning, Work, Finance, Personal, or Inbox.
tags must contain 1-5 short lowercase tags for an Obsidian knowledge base.
learnedConcepts must describe what the learner appears to understand or practice.
actionItems must describe unresolved questions or next review steps.
words must include only useful English learning words that appear in the conversation and are worth adding to a word bank.
Each word needs word, phonetic, partOfSpeech, translation, exampleEnglish, exampleChinese.
Do not include passwords, API keys, personal identifiers, or private secrets in the output.''',
          },
          {
            'role': 'user',
            'content': 'Conversation transcript:\n\n$transcript',
          },
        ],
        'stream': false,
        'temperature': 0.1,
        'max_tokens': 4096,
        'thinking': const {'type': 'disabled'},
        'response_format': const {'type': 'json_object'},
      },
    );
    final text = _extractResponseText(response);
    if (text == null || text.trim().isEmpty) {
      throw const AiServiceException('DeepSeek 没有返回可解析的学习分析。');
    }
    final decoded = jsonDecode(_stripCodeFence(text));
    if (decoded is! Map) {
      throw const AiServiceException('DeepSeek 学习分析格式异常。');
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
    if (!settings.hasClientApiKey) {
      return AiEnrichmentReport(
        words: words,
        requestedCount: words.length,
        enrichedCount: 0,
        warning: '联网 AI 未启用，已保留本地解析结果。',
      );
    }

    final merged = <String, ParsedWord>{
      for (final word in words) word.word.toLowerCase(): word,
    };
    var enrichedCount = 0;
    final warnings = <String>[];

    for (final batch in _chunk(words, batchSize)) {
      try {
        final response = await _postJson(
          settings: settings,
          body: {
            'model': _resolveModel(settings),
            'messages': [
              {
                'role': 'system',
                'content': '''
You are an English learning assistant for Chinese learners.
Return only valid JSON in the form {"items":[...]}.
Keep the original order of the requested words.
For each word, provide a concise Chinese translation, IPA phonetic spelling, a short part-of-speech tag, one simple English example, and one Chinese example.
When unsure, choose the most common classroom meaning.
Do not add markdown, code fences, or commentary.
''',
              },
              {'role': 'user', 'content': _buildBatchPrompt(batch)},
            ],
            'stream': false,
            'temperature': 0.2,
            'max_tokens': 2048,
            'thinking': const {'type': 'disabled'},
            'response_format': const {'type': 'json_object'},
          },
        );
        final text = _extractResponseText(response);
        if (text == null || text.trim().isEmpty) {
          throw const AiServiceException('DeepSeek 没有返回可解析的文本。');
        }
        final decoded = jsonDecode(_stripCodeFence(text));
        final items = _readItems(decoded);
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
      } on AiServiceException catch (error) {
        warnings.add(
          '批次 ${batch.first.word}…${batch.last.word}：${error.message}',
        );
      } catch (error) {
        warnings.add('批次 ${batch.first.word}…${batch.last.word}：$error');
      }
    }

    final output = [
      for (final word in words) merged[word.word.toLowerCase()] ?? word,
    ];

    return AiEnrichmentReport(
      words: output,
      requestedCount: words.length,
      enrichedCount: enrichedCount,
      warning: warnings.isEmpty ? null : warnings.join('；'),
    );
  }

  Future<Map<String, Object?>> _postJson({
    required AiConnectionSettings settings,
    required Map<String, Object?> body,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(endpoint);
      final request = await client
          .postUrl(uri)
          .timeout(
            timeout,
            onTimeout: () {
              throw const AiServiceException('连接 DeepSeek 超时。');
            },
          );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${settings.apiKey.trim()}',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(body));

      final response = await request.close().timeout(
        timeout,
        onTimeout: () {
          throw const AiServiceException('等待 DeepSeek 响应超时。');
        },
      );
      final responseBody = await utf8
          .decodeStream(response)
          .timeout(
            timeout,
            onTimeout: () {
              throw const AiServiceException('读取 DeepSeek 响应超时。');
            },
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          _extractApiError(response.statusCode, responseBody),
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, Object?>) {
        throw const AiServiceException('DeepSeek 返回的数据格式异常。');
      }
      return decoded;
    } on SocketException catch (error) {
      throw AiServiceException('网络不可用：$error');
    } on HandshakeException catch (error) {
      throw AiServiceException('TLS 握手失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  static String _buildBatchPrompt(List<ParsedWord> batch) {
    final buffer = StringBuffer();
    buffer.writeln('Words to enrich:');
    for (final word in batch) {
      buffer.writeln('- ${word.word}');
    }
    return buffer.toString().trimRight();
  }

  static String _extractApiError(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is Map<String, Object?>) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            return 'DeepSeek 请求失败 ($statusCode)：$message';
          }
        }
      }
    } catch (_) {
      // Fall back to the raw body below.
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return 'DeepSeek 请求失败 ($statusCode)。';
    }
    return 'DeepSeek 请求失败 ($statusCode)：$trimmed';
  }

  static String? _extractResponseText(Map<String, Object?> payload) {
    final choices = payload['choices'];
    if (choices is List) {
      for (final choice in choices) {
        if (choice is! Map) continue;
        final map = Map<String, Object?>.from(choice);
        final message = map['message'];
        if (message is Map) {
          for (final key in const ['content', 'reasoning_content']) {
            final content = message[key];
            if (content is String && content.trim().isNotEmpty) {
              return content;
            }
          }
        }
      }
    }
    return null;
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
    throw const AiServiceException('DeepSeek 返回的 JSON 缺少 items。');
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

  static Iterable<List<T>> _chunk<T>(List<T> values, int size) sync* {
    if (values.isEmpty) return;
    final safeSize = math.max(1, size);
    for (var index = 0; index < values.length; index += safeSize) {
      final end = math.min(values.length, index + safeSize);
      yield values.sublist(index, end);
    }
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

  static String _resolveModel(AiConnectionSettings settings) {
    final model = settings.model.trim();
    final normalized = model.toLowerCase();
    if (normalized.isEmpty || normalized == 'deepseek-v4-flash') {
      return 'deepseek-v4-flash';
    }
    if (normalized == 'deepseek-v4-pro') return 'deepseek-v4-pro';
    return model;
  }

  static String _stringOr(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
  }

  static List<ParsedWord> _analysisWords(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map)
          ParsedWord(
            word: _stringOr(item['word'] ?? item['term'], '').toLowerCase(),
            phonetic: _stringOr(item['phonetic'] ?? item['ipa'], '待生成'),
            partOfSpeech: _stringOr(
              item['partOfSpeech'] ??
                  item['part_of_speech'] ??
                  item['pos'] ??
                  item['词性'],
              '待识别',
            ),
            translation: _stringOr(
              item['translation'] ?? item['meaning'] ?? item['definition'],
              '待 AI 翻译',
            ),
            exampleEnglish: _stringOr(
              item['exampleEnglish'] ?? item['example_en'],
              '',
            ),
            exampleChinese: _stringOr(
              item['exampleChinese'] ?? item['example_zh'],
              '',
            ),
          ),
    ].where((word) => word.word.isNotEmpty).toList(growable: false);
  }
}
