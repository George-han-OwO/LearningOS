import 'package:ai_study_os/domain/word_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts English words, normalizes case, and removes duplicates', () {
    final words = WordParser.parse('Ability, ability; ACTIVE\nlong-term.');

    expect(words.map((item) => item.word), ['ability', 'active', 'long-term']);
  });

  test('uses bundled translation when known', () {
    final word = WordParser.parse('memory').single;

    expect(word.translation, '记忆；记忆力');
    expect(word.phonetic, isNot('待生成'));
  });

  test('marks unknown words for later AI enrichment', () {
    final word = WordParser.parse('metacognition').single;

    expect(word.translation, '待 AI 翻译');
    expect(word.partOfSpeech, '待识别');
  });
}
