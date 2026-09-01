import 'package:ai_study_os/domain/learning_engine.dart';
import 'package:ai_study_os/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 25, 9);

  StudyWord word({int interval = 0, int mastery = 0}) {
    return StudyWord(
      id: 1,
      userId: 1,
      word: 'recall',
      phonetic: '/rɪˈkɔːl/',
      partOfSpeech: 'v.',
      translation: '回忆',
      exampleEnglish: 'Recall the answer.',
      exampleChinese: '回忆答案。',
      mastery: mastery,
      intervalDays: interval,
      dueAt: now,
      createdAt: now,
    );
  }

  test('new card rated good returns in two days', () {
    final schedule = LearningEngine.schedule(
      word: word(),
      rating: ReviewRating.good,
      now: now,
    );

    expect(schedule.intervalDays, 2);
    expect(schedule.mastery, 12);
    expect(schedule.dueAt, DateTime(2026, 8, 27, 9));
  });

  test('again resets interval and never drops mastery below zero', () {
    final schedule = LearningEngine.schedule(
      word: word(interval: 12, mastery: 8),
      rating: ReviewRating.again,
      now: now,
    );

    expect(schedule.intervalDays, 1);
    expect(schedule.mastery, 0);
  });

  test('easy expands an established interval', () {
    final schedule = LearningEngine.schedule(
      word: word(interval: 10, mastery: 90),
      rating: ReviewRating.easy,
      now: now,
    );

    expect(schedule.intervalDays, 35);
    expect(schedule.mastery, 100);
  });
}
