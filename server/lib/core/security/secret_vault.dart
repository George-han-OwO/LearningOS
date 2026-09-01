import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Authenticated encryption for provider credentials stored by the server.
///
/// The master key deliberately lives outside SQLite. Production deployments
/// must provide [environmentVariable] as either 32 bytes of base64/base64url or
/// 64 hexadecimal characters. Ciphertexts are versioned so their format can be
/// migrated later without ever falling back to plaintext storage.
class SecretVault {
  SecretVault._(this._masterKey, this.configurationError);

  factory SecretVault.fromEnvironment([Map<String, String>? environment]) {
    final raw =
        (environment ?? Platform.environment)[environmentVariable]?.trim() ??
        '';
    if (raw.isEmpty) {
      return SecretVault._(null, '未设置服务器环境变量 $environmentVariable。');
    }

    try {
      final decoded = _decodeMasterKey(raw);
      if (decoded.length != 32) {
        return SecretVault._(null, '$environmentVariable 必须解码为 32 字节。');
      }
      return SecretVault._(Uint8List.fromList(decoded), null);
    } on FormatException catch (error) {
      return SecretVault._(null, '$environmentVariable 格式无效：$error');
    }
  }

  /// Intended for isolated unit tests. Production code uses the environment.
  factory SecretVault.forTesting(List<int> masterKey) {
    if (masterKey.length != 32) {
      throw ArgumentError.value(masterKey.length, 'masterKey', '必须为 32 字节');
    }
    return SecretVault._(Uint8List.fromList(masterKey), null);
  }

  static const environmentVariable = 'AILO_SECRETS_MASTER_KEY';
  static const _formatVersion = 'v1';
  static const _nonceLength = 12;
  static final _algorithm = AesGcm.with256bits();
  static final _associatedData = utf8.encode(
    'AILearningOS:deepseek_api_key:v1',
  );

  final Uint8List? _masterKey;
  final String? configurationError;

  bool get ready => _masterKey != null;

  /// Generates a base64url master key suitable for setting directly on the
  /// server. It must never be committed, sent to a client, or pasted in chat.
  static String generateMasterKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> encrypt(String plaintext) async {
    final masterKey = _requireMasterKey();
    final random = Random.secure();
    final nonce = List<int>.generate(_nonceLength, (_) => random.nextInt(256));
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(masterKey),
      nonce: nonce,
      aad: _associatedData,
    );
    return <String>[
      _formatVersion,
      _encode(box.nonce),
      _encode(box.cipherText),
      _encode(box.mac.bytes),
    ].join('.');
  }

  Future<String> decrypt(String encoded) async {
    final masterKey = _requireMasterKey();
    final parts = encoded.split('.');
    if (parts.length != 4 || parts.first != _formatVersion) {
      throw const SecretVaultException('密文版本或结构无效。');
    }

    try {
      final nonce = _decode(parts[1]);
      if (nonce.length != _nonceLength) {
        throw const SecretVaultException('密文 nonce 长度无效。');
      }
      final clearBytes = await _algorithm.decrypt(
        SecretBox(_decode(parts[2]), nonce: nonce, mac: Mac(_decode(parts[3]))),
        secretKey: SecretKey(masterKey),
        aad: _associatedData,
      );
      return utf8.decode(clearBytes);
    } on SecretVaultException {
      rethrow;
    } catch (_) {
      // Do not include cryptographic internals or any part of the secret in
      // error messages returned to logs or clients.
      throw const SecretVaultException('密文认证失败或服务器主密钥不匹配。');
    }
  }

  Uint8List _requireMasterKey() {
    final key = _masterKey;
    if (key == null) {
      throw SecretVaultException(configurationError ?? '服务器密钥保险库尚未配置。');
    }
    return key;
  }

  static List<int> _decodeMasterKey(String raw) {
    final hex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (hex.hasMatch(raw)) {
      return [
        for (var index = 0; index < raw.length; index += 2)
          int.parse(raw.substring(index, index + 2), radix: 16),
      ];
    }
    return _decode(raw);
  }

  static String _encode(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

class SecretVaultException implements Exception {
  const SecretVaultException(this.message);

  final String message;

  @override
  String toString() => message;
}
