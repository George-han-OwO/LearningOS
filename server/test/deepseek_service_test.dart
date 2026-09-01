import 'dart:convert';
import 'dart:io';

import 'package:server/core/ai/deepseek_service.dart';
import 'package:server/domain/models.dart';
import 'package:server/domain/word_parser.dart';
import 'package:test/test.dart';

void main() {
  test('word enrichment accepts snake_case part-of-speech fields', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'items': [
                    {
                      'word': 'sample',
                      'phonetic': '/ˈsæmpəl/',
                      'part_of_speech': 'noun',
                      'translation': '样本',
                      'example_en': 'This sample is representative.',
                      'example_zh': '这个样本具有代表性。',
                    },
                  ],
                }),
              },
            },
          ],
        }),
      );
      await request.response.close();
    });

    final service = DeepSeekService(
      endpoint: 'http://127.0.0.1:${server.port}/chat/completions',
    );
    final report = await service.enrichWords(
      settings: const AiConnectionSettings(
        enabled: true,
        apiKey: 'test-provider-key',
        model: 'deepseek-v4-flash',
      ),
      words: const [
        ParsedWord(
          word: 'sample',
          phonetic: '待生成',
          partOfSpeech: '待识别',
          translation: '待 AI 翻译',
          exampleEnglish: '',
          exampleChinese: '',
        ),
      ],
    );

    expect(report.warning, isNull);
    expect(report.enrichedCount, 1);
    expect(report.words.single.partOfSpeech, 'noun');
    expect(report.words.single.translation, '样本');
    expect(report.words.single.exampleEnglish, isNotEmpty);
    expect(report.words.single.exampleChinese, isNotEmpty);
  });
}
