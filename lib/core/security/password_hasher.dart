import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PasswordDigest {
  const PasswordDigest({required this.hash, required this.salt});

  final String hash;
  final String salt;
}

class PasswordHasher {
  PasswordHasher()
    : _algorithm = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 120000,
        bits: 256,
      );

  final Pbkdf2 _algorithm;
  final Random _random = Random.secure();

  Future<PasswordDigest> hash(String password) async {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final derived = await _derive(password, salt);
    return PasswordDigest(
      hash: base64UrlEncode(derived),
      salt: base64UrlEncode(salt),
    );
  }

  Future<bool> verify({
    required String password,
    required String expectedHash,
    required String encodedSalt,
  }) async {
    final salt = base64Url.decode(encodedSalt);
    final actual = await _derive(password, salt);
    final expected = base64Url.decode(expectedHash);
    return _constantTimeEquals(actual, expected);
  }

  Future<List<int>> _derive(String password, List<int> salt) async {
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
