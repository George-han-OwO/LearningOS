/// Pure date/time rules for the automatic note scheduler.
///
/// The app intentionally uses the device's local time zone for the nightly
/// run. The server stores the resulting timestamp as an ISO-8601 value, so a
/// later app launch can still determine whether today's 23:00 run was made.
class AutoNoteSchedule {
  const AutoNoteSchedule._();

  static const nightlyHour = 23;

  static DateTime scheduledNightlyAt(DateTime value) =>
      DateTime(value.year, value.month, value.day, nightlyHour);

  static DateTime nextNightlyAt(DateTime now) {
    var next = scheduledNightlyAt(now);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  static bool isNightlyDue({
    required DateTime now,
    DateTime? lastRunAt,
  }) {
    final scheduled = scheduledNightlyAt(now);
    final last = lastRunAt?.toLocal();
    return !now.isBefore(scheduled) &&
        (last == null || last.isBefore(scheduled));
  }
}
