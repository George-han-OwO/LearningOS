// This executable intentionally prints only a redacted verification summary.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrlVariable = 'AILO_SERVER_URL';
const _tokenVariable = 'AILO_SESSION_TOKEN';

Future<void> main() async {
  http.Client? client;
  try {
    final baseUri = _validatedBaseUri(Platform.environment[_baseUrlVariable]);
    final token = Platform.environment[_tokenVariable]?.trim() ?? '';
    if (token.isEmpty) {
      _fail('缺少 $_tokenVariable；请传入 LearningOS 设备会话 Bearer。');
    }
    client = http.Client();
    final health = await _getText(client, baseUri, '/health');
    if (health.trim().toUpperCase() != 'OK') {
      _fail('/health 返回了意外内容。');
    }

    final version = await _getJson(client, baseUri, '/version');
    final build = version['build']?.toString() ?? '';
    if (!build.contains('v4.0')) {
      _fail('远程服务不是待验收的 v4.0（实际 build：$build）。');
    }
    if (version['codex_gateway_enabled'] != true) {
      _fail('远程服务已响应，但 Codex 网关未启用。');
    }

    final headers = {'Authorization': 'Bearer $token'};
    final account = await _getJson(
      client,
      baseUri,
      '/api/codex/account',
      headers: headers,
    );
    if (account['available'] != true || account['authenticated'] != true) {
      _fail('该 LearningOS 设备会话尚未绑定已登录的 ChatGPT-Codex 账号。');
    }

    final quota = await _getJson(
      client,
      baseUri,
      '/api/codex/quota',
      headers: headers,
    );
    if (quota['available'] != true) {
      _fail('Codex 登录有效，但额度接口未返回可用状态。');
    }

    final history = await _getJson(
      client,
      baseUri,
      '/api/codex/history?full_refresh=1',
      headers: headers,
    );
    final folder = history['folder_name']?.toString() ?? '';
    final totalThreads = _integer(history['total_threads']);
    final changed = history['changed_conversations'];
    final readableSnapshots = changed is List ? changed.length : 0;
    if (folder.toUpperCase() != 'OSS') {
      _fail('历史接口没有确认 OSS 工作区。');
    }

    print('Remote AILearningOS: healthy ($build)');
    print('Codex gateway: enabled; isolated account session: authenticated');
    print(
      'Quota remaining: '
      '${_remaining(quota['primary_used_percent'])} / '
      '${_remaining(quota['secondary_used_percent'])}',
    );
    print(
      'OSS history: $totalThreads threads, '
      '$readableSnapshots readable snapshots',
    );
    print(
      'Sensitive account fields, tokens, and conversation text were not printed.',
    );
  } on _VerificationFailure catch (error) {
    stderr.writeln('Verification failed: ${error.message}');
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Verification failed: ${_safeError(error)}');
    exitCode = 1;
  } finally {
    client?.close();
  }
}

Uri _validatedBaseUri(String? rawValue) {
  final raw = rawValue?.trim() ?? '';
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    _fail('请设置 $_baseUrlVariable，例如 https://os.example.com。');
  }
  final loopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (uri.scheme != 'https' && !(loopback && uri.scheme == 'http')) {
    _fail('远程服务器必须使用 HTTPS；只有本机回环地址允许 HTTP。');
  }
  return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
}

Future<String> _getText(
  http.Client client,
  Uri baseUri,
  String path, {
  Map<String, String>? headers,
}) async {
  final response = await client
      .get(_resolve(baseUri, path), headers: headers)
      .timeout(const Duration(seconds: 25));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    _fail('$path 返回 HTTP ${response.statusCode}。');
  }
  return response.body;
}

Future<Map<String, dynamic>> _getJson(
  http.Client client,
  Uri baseUri,
  String path, {
  Map<String, String>? headers,
}) async {
  final body = await _getText(client, baseUri, path, headers: headers);
  final value = jsonDecode(body);
  if (value is! Map) _fail('$path 没有返回 JSON 对象。');
  return Map<String, dynamic>.from(value);
}

Uri _resolve(Uri baseUri, String path) {
  final pathUri = Uri.parse(path);
  final suffix = pathUri.path.startsWith('/')
      ? pathUri.path.substring(1)
      : pathUri.path;
  final prefix = baseUri.path.isEmpty ? '/' : '${baseUri.path}/';
  return baseUri.replace(
    path: '$prefix$suffix',
    queryParameters: pathUri.queryParameters.isEmpty
        ? null
        : pathUri.queryParameters,
    fragment: null,
  );
}

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

String _remaining(Object? usedValue) {
  final used = usedValue is num
      ? usedValue.toDouble()
      : double.tryParse(usedValue?.toString() ?? '');
  if (used == null) return '-';
  return '${(100 - used).clamp(0, 100).toStringAsFixed(0)}%';
}

String _safeError(Object error) {
  if (error is FormatException) return '服务器返回了无法解析的数据。';
  if (error is SocketException) return '无法连接远程服务器。';
  if (error is TimeoutException) return '等待远程服务器响应超时。';
  return error.runtimeType.toString();
}

Never _fail(String message) => throw _VerificationFailure(message);

final class _VerificationFailure implements Exception {
  const _VerificationFailure(this.message);

  final String message;
}
