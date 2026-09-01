import 'package:ai_study_os/core/security/password_hasher.dart';
import 'package:ai_study_os/domain/security_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('password hash verifies the correct password only', () async {
    final hasher = PasswordHasher();
    final digest = await hasher.hash('correct horse battery staple');

    expect(
      await hasher.verify(
        password: 'correct horse battery staple',
        expectedHash: digest.hash,
        encodedSalt: digest.salt,
      ),
      isTrue,
    );
    expect(
      await hasher.verify(
        password: 'wrong password',
        expectedHash: digest.hash,
        encodedSalt: digest.salt,
      ),
      isFalse,
    );
  });

  test('login protection starts exponential lockout at third failure', () {
    expect(SecurityPolicy.lockDurationForFailureCount(2), Duration.zero);
    expect(
      SecurityPolicy.lockDurationForFailureCount(3),
      const Duration(seconds: 15),
    );
    expect(
      SecurityPolicy.lockDurationForFailureCount(4),
      const Duration(seconds: 30),
    );
  });

  test('login protection caps lockout at fifteen minutes', () {
    expect(
      SecurityPolicy.lockDurationForFailureCount(20),
      const Duration(minutes: 15),
    );
  });

  test('security state reports remaining lock duration', () {
    final now = DateTime(2026, 8, 25, 12);
    final state = LoginSecurityState(
      failedAttempts: 5,
      lockedUntil: now.add(const Duration(minutes: 1)),
      lastFailedAt: now,
    );

    expect(state.remainingAt(now), const Duration(minutes: 1));
  });
}
