import 'package:ai_study_os/domain/auto_note_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next nightly run is 23:00 in the device local time', () {
    final before = DateTime(2026, 8, 27, 22, 59);
    expect(
      AutoNoteSchedule.nextNightlyAt(before),
      DateTime(2026, 8, 27, 23),
    );

    final after = DateTime(2026, 8, 27, 23, 1);
    expect(
      AutoNoteSchedule.nextNightlyAt(after),
      DateTime(2026, 8, 28, 23),
    );
  });

  test('a nightly run is due once after 23:00 and not twice on the same day', () {
    final now = DateTime(2026, 8, 27, 23, 5);
    expect(AutoNoteSchedule.isNightlyDue(now: now), isTrue);
    expect(
      AutoNoteSchedule.isNightlyDue(
        now: now,
        lastRunAt: DateTime(2026, 8, 27, 23),
      ),
      isFalse,
    );
    expect(
      AutoNoteSchedule.isNightlyDue(
        now: DateTime(2026, 8, 28, 8),
        lastRunAt: DateTime(2026, 8, 27, 23),
      ),
      isFalse,
    );
  });
}
