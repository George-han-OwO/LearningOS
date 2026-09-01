import 'dart:math';

import 'models.dart';

class ReviewSchedule {
  const ReviewSchedule({
    required this.intervalDays,
    required this.mastery,
    required this.dueAt,
  });

  final int intervalDays;
  final int mastery;
  final DateTime dueAt;
}

class LearningEngine {
  const LearningEngine._();

  static ReviewSchedule schedule({
    required StudyWord word,
    required ReviewRating rating,
    DateTime? now,
  }) {
    final reviewedAt = now ?? DateTime.now();
    final currentInterval = max(1, word.intervalDays);

    final interval = switch (rating) {
      ReviewRating.again => 1,
      ReviewRating.hard => max(1, (currentInterval * 1.4).round()),
      ReviewRating.good =>
        word.intervalDays == 0 ? 2 : max(2, (currentInterval * 2.5).round()),
      ReviewRating.easy =>
        word.intervalDays == 0 ? 4 : max(4, (currentInterval * 3.5).round()),
    };

    final masteryDelta = switch (rating) {
      ReviewRating.again => -18,
      ReviewRating.hard => 4,
      ReviewRating.good => 12,
      ReviewRating.easy => 18,
    };

    return ReviewSchedule(
      intervalDays: interval,
      mastery: (word.mastery + masteryDelta).clamp(0, 100),
      dueAt: reviewedAt.add(Duration(days: interval)),
    );
  }
}
