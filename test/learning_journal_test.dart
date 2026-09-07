import 'package:ai_study_os/domain/learning_journal.dart';
import 'package:ai_study_os/domain/word_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blank journal uses the required eight-section format', () {
    final journal = LearningJournalTemplate.blank(date: DateTime(2026, 9, 7));

    expect(journal, startsWith('# Learning Journal'));
    expect(journal, contains('- 日期：2026-09-07'));
    for (var section = 1; section <= 8; section++) {
      expect(journal, contains('## $section.'));
    }
    expect(journal, contains('- 目标完成度：`     / 10`'));
    expect(journal, contains('## 8. 自由记录'));
  });

  test('AI journal fills analysis while preserving the template', () {
    final journal = LearningJournalTemplate.fromAiAnalysis(
      topic: '生态系统',
      source: 'AI 分析 · DeepSeek',
      summaryChinese: '学习了食物网与物种竞争。',
      summaryEnglish: 'Learned about food webs and competition.',
      concepts: const ['食物网', '生态位'],
      actions: const ['复习物种竞争', '画一张食物网'],
      words: const [
        ParsedWord(
          word: 'competition',
          phonetic: '',
          partOfSpeech: 'noun',
          translation: '竞争',
          exampleEnglish: '',
          exampleChinese: '',
        ),
      ],
      originalText: '两种动物吃相同的食物。',
      date: DateTime(2026, 9, 7),
    );

    expect(journal, contains('- 学习主题：生态系统'));
    expect(journal, contains('- 食物网'));
    expect(journal, contains('competition：竞争'));
    expect(journal, contains('Learned about food webs and competition.'));
    expect(journal, contains('两种动物吃相同的食物。'));
  });
}
