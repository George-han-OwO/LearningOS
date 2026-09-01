import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class PasswordHasher {
  PasswordHasher()
    : _algorithm = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 120000,
        bits: 256,
      );
  final Pbkdf2 _algorithm;

  Future<bool> verify({
    required String password,
    required String expectedHash,
    required String encodedSalt,
  }) async {
    try {
      final key = await _algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: base64Url.decode(encodedSalt),
      );
      final actual = await key.extractBytes();
      final expected = base64Url.decode(expectedHash);
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var i = 0; i < actual.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }
}
