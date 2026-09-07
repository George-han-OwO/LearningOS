import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/canvas/canvas_service.dart';
import '../core/security/secret_vault.dart';
import '../data/app_database.dart';

class CanvasRoutes {
  CanvasRoutes(this.db, this.service);
  final AppDatabase db;
  final CanvasService service;

  Handler get handler {
    final router = Router();
    router.get(
      '/connection',
      (Request request) => _withUser(request, (userId) async {
        final value = await db.canvasConnection(userId);
        return _json(_publicConnection(value));
      }),
    );
    router.put(
      '/connection',
      (Request request) => _withUser(request, (userId) async {
        if (!db.secretVaultReady) {
          throw const CanvasException('后端尚未配置凭据加密主密钥，请联系服务器管理员。', 503);
        }
        final body = await request.readAsString();
        if (body.length > 12000) {
          throw const CanvasException('Canvas 配置内容过长。', 400);
        }
        final payload = jsonDecode(body);
        if (payload is! Map ||
            payload['base_url'] is! String ||
            payload['token'] is! String) {
          throw const CanvasException('请填写学校 Canvas 网址和令牌。', 400);
        }
        final base = service
            .validateBaseUrl(payload['base_url'] as String)
            .toString();
        final token = service.validateToken(payload['token'] as String);
        // Verify before replacing a working connection. Never echo the token.
        final profile = await service.profile(base, token);
        final value = <String, dynamic>{
          'base_url': base,
          'token': token,
          'profile': profile,
          'connected_at': DateTime.now().toUtc().toIso8601String(),
        };
        await db.saveCanvasConnection(userId, value);
        return _json(_publicConnection(value));
      }),
    );
    router.delete(
      '/connection',
      (Request request) => _withUser(request, (userId) async {
        await db.clearCanvasConnection(userId);
        return _json({'connected': false});
      }),
    );
    router.get(
      '/courses',
      (Request request) => _withUser(request, (userId) async {
        final value = await _connection(userId);
        return _json(
          await service.courses(
            value['base_url'] as String,
            value['token'] as String,
            cursor: request.url.queryParameters['cursor'],
          ),
        );
      }),
    );
    router.get(
      '/courses/<courseId>/assignments',
      (Request request, String courseId) => _withUser(request, (userId) async {
        final value = await _connection(userId);
        return _json(
          await service.assignments(
            value['base_url'] as String,
            value['token'] as String,
            courseId,
            cursor: request.url.queryParameters['cursor'],
          ),
        );
      }),
    );
    return router.call;
  }

  Future<Map<String, dynamic>> _connection(int userId) async {
    final value = await db.canvasConnection(userId);
    if (value == null) throw const CanvasException('请先连接 Canvas。', 409);
    return value;
  }

  Map<String, dynamic> _publicConnection(Map<String, dynamic>? value) =>
      value == null
      ? {'connected': false}
      : {
          'connected': true,
          'base_url': value['base_url'],
          'profile': value['profile'],
          'connected_at': value['connected_at'],
        };

  Future<Response> _withUser(
    Request request,
    Future<Response> Function(int) action,
  ) async {
    try {
      final header = request.headers['authorization'] ?? '';
      if (!header.toLowerCase().startsWith('bearer ')) {
        return _json({'error': '请先登录 AILearningOS。'}, 401);
      }
      final user = await db.userForSessionToken(header.substring(7).trim());
      if (user == null) {
        return _json({'error': '登录已过期，请重新登录 AILearningOS。'}, 401);
      }
      return await action(user.id);
    } on CanvasException catch (error) {
      return _json({'error': error.message}, error.statusCode);
    } on FormatException {
      return _json({'error': 'Canvas 配置格式无效。'}, 400);
    } on SecretVaultException {
      return _json({'error': 'Canvas 加密凭据无法读取或保存，请检查后端主密钥。'}, 503);
    } catch (_) {
      return _json({'error': 'Canvas 操作失败，请稍后重试。'}, 500);
    }
  }

  Response _json(Object value, [int status = 200]) => Response(
    status,
    body: jsonEncode(value),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );
}
