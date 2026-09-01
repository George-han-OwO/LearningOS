import 'dart:math' as math;

class LoginSecurityState {
  const LoginSecurityState({
    required this.failedAttempts,
    required this.lockedUntil,
    required this.lastFailedAt,
  });

  const LoginSecurityState.clear()
    : failedAttempts = 0,
      lockedUntil = null,
      lastFailedAt = null;

  final int failedAttempts;
  final DateTime? lockedUntil;
  final DateTime? lastFailedAt;

  bool get isLocked {
    final until = lockedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  Duration remainingAt(DateTime now) {
    final until = lockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  factory LoginSecurityState.fromMap(Map<String, Object?> map) {
    return LoginSecurityState(
      failedAttempts: (map['failed_attempts']! as num).toInt(),
      lockedUntil: _parseDate(map['locked_until']),
      lastFailedAt: _parseDate(map['last_failed_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

abstract final class SecurityPolicy {
  static const int maxImportBytes = 25 * 1024 * 1024;
  static const int maxWordBankCharacters = 100000;
  static const int firstLockingFailure = 3;
  static const int maxLockSeconds = 900;

  static Duration lockDurationForFailureCount(int failedAttempts) {
    if (failedAttempts < firstLockingFailure) return Duration.zero;
    final exponent = failedAttempts - firstLockingFailure;
    final seconds = math.min(
      maxLockSeconds,
      15 * math.pow(2, exponent).toInt(),
    );
    return Duration(seconds: seconds);
  }

  static String formatRemaining(Duration remaining) {
    if (remaining.inMinutes >= 1) {
      final seconds = remaining.inSeconds.remainder(60);
      return seconds == 0
          ? '${remaining.inMinutes} 分钟'
          : '${remaining.inMinutes} 分 $seconds 秒';
    }
    return '${math.max(1, remaining.inSeconds)} 秒';
  }
}
