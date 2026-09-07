import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CanvasException implements Exception {
  const CanvasException(this.message, [this.statusCode = 502]);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

/// Read-only Canvas API. Credentials only travel to the validated institution
/// origin, never redirects or a foreign pagination destination.
class CanvasService {
  CanvasService({this._client, Set<String>? allowedHosts})
    : _allowedHosts =
          allowedHosts ??
          (Platform.environment['AILO_CANVAS_ALLOWED_HOSTS'] ?? '')
              .split(',')
              .map((s) => s.trim().toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();

  final http.Client? _client;
  final Set<String> _allowedHosts;

  Uri validateBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !(uri.host.endsWith('.instructure.com') ||
            _allowedHosts.contains(uri.host))) {
      throw const CanvasException(
        '请填写学校 Canvas 的 HTTPS 域名（不含页面路径）。学校自定义域名需先在后端 AILO_CANVAS_ALLOWED_HOSTS 中配置。',
        400,
      );
    }
    return Uri(scheme: 'https', host: uri.host);
  }

  String validateToken(String token) {
    final value = token.trim();
    if (value.isEmpty ||
        value.length > 4096 ||
        RegExp(r'[\s\\]').hasMatch(value)) {
      throw const CanvasException('请粘贴完整 Canvas 令牌，不要包含空格或 Markdown 转义符。', 400);
    }
    return value;
  }

  Future<Map<String, dynamic>> profile(String baseUrl, String token) async {
    final base = validateBaseUrl(baseUrl);
    final response = await _get(
      base,
      base.resolve('/api/v1/users/self/profile'),
      validateToken(token),
    );
    final data = _decode(response);
    if (data is! Map || data['id'] == null) {
      throw const CanvasException('Canvas 账号响应无效。');
    }
    return {
      'id': data['id'].toString(),
      'name': data['name']?.toString() ?? '',
      'primary_email': data['primary_email']?.toString() ?? '',
    };
  }

  Future<Map<String, dynamic>> courses(
    String baseUrl,
    String token, {
    String? cursor,
  }) => _page(
    baseUrl,
    token,
    '/api/v1/courses',
    cursor: cursor,
    query: {'per_page': '50', 'enrollment_state': 'active'},
    fields: const ['id', 'name', 'course_code', 'workflow_state'],
  );

  Future<Map<String, dynamic>> assignments(
    String baseUrl,
    String token,
    String courseId, {
    String? cursor,
  }) {
    if (!RegExp(r'^\d+$').hasMatch(courseId)) {
      throw const CanvasException('Canvas 课程 ID 无效。', 400);
    }
    return _page(
      baseUrl,
      token,
      '/api/v1/courses/$courseId/assignments',
      cursor: cursor,
      query: {
        'per_page': '50',
        'order_by': 'due_at',
        'include[]': 'submission',
      },
      fields: const ['id', 'name', 'due_at', 'points_possible', 'html_url'],
      submission: true,
    );
  }

  Future<Map<String, dynamic>> _page(
    String baseUrl,
    String token,
    String path, {
    String? cursor,
    required Map<String, String> query,
    required List<String> fields,
    bool submission = false,
  }) async {
    final base = validateBaseUrl(baseUrl);
    var uri = base.resolve(path).replace(queryParameters: query);
    if (cursor != null && cursor.isNotEmpty) {
      uri =
          Uri.tryParse(cursor) ??
          (throw const CanvasException('Canvas 分页地址无效。', 400));
      _validatePage(base, uri, path);
    }
    final response = await _get(base, uri, validateToken(token));
    final data = _decode(response);
    if (data is! List) throw const CanvasException('Canvas 列表响应无效。');
    String? next;
    for (final match in RegExp(
      r'<([^>]+)>;\s*rel="([^"]+)"',
    ).allMatches(response.headers['link'] ?? '')) {
      if (match[2] != 'next') continue;
      final candidate = Uri.tryParse(match[1]!);
      if (candidate == null) throw const CanvasException('Canvas 分页地址无效。');
      _validatePage(base, candidate, path);
      next = candidate.toString();
    }
    return {
      'items': [
        for (final item in data.whereType<Map>())
          {
            for (final field in fields)
              field: field == 'id' ? item[field]?.toString() : item[field],
            if (submission && item['submission'] is Map)
              'submission': {
                for (final field in const [
                  'workflow_state',
                  'submitted_at',
                  'score',
                  'grade',
                  'missing',
                  'late',
                ])
                  field: (item['submission'] as Map)[field],
              },
          },
      ],
      'next_cursor': next,
    };
  }

  void _validatePage(Uri base, Uri uri, String path) {
    if (uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.path != path && uri.path != '$path.json') ||
        uri.queryParameters.containsKey('access_token')) {
      throw const CanvasException('Canvas 返回了不受信任的分页地址。', 400);
    }
  }

  Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const CanvasException('Canvas 返回了无法解析的数据。');
    }
  }

  Future<http.Response> _get(Uri base, Uri uri, String token) async {
    if (uri.origin != base.origin) {
      throw const CanvasException('Canvas 请求域名不匹配。', 400);
    }
    final client = _client ?? http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        });
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
      switch (response.statusCode) {
        case 200:
          return response;
        case 401:
          throw const CanvasException('Canvas 令牌无效或已过期，请重新连接。', 401);
        case 403:
          throw const CanvasException('Canvas 未授予读取该资料的权限。', 403);
        case 404:
          throw const CanvasException('Canvas 课程或接口不存在，请检查学校网址。', 404);
        case 429:
          throw const CanvasException('Canvas 请求过于频繁，请稍后重试。', 429);
        default:
          throw const CanvasException('Canvas 暂时无法访问，请检查学校网址或稍后重试。');
      }
    } on CanvasException {
      rethrow;
    } catch (_) {
      throw const CanvasException('后端连接 Canvas 失败，请稍后重试。', 503);
    } finally {
      if (_client == null) client.close();
    }
  }
}
