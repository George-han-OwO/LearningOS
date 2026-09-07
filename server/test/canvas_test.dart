import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/api/canvas_routes.dart';
import 'package:server/api/router.dart';
import 'package:server/core/ai/hybrid_ai_service.dart';
import 'package:server/core/ai/pending_word_enrichment.dart';
import 'package:server/core/canvas/canvas_service.dart';
import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const base = 'https://school.instructure.com';
  const testToken = 'test-only-canvas-token';

  test('validates HTTPS Canvas host before sending credentials', () async {
    var calls = 0;
    final service = CanvasService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    for (final url in [
      'http://school.instructure.com',
      'https://127.0.0.1',
      'https://attacker.example',
      'https://school.instructure.com.evil.test',
      '$base/path',
      '$base?access_token=value',
      'https://user@school.instructure.com',
    ]) {
      await expectLater(
        service.profile(url, testToken),
        throwsA(isA<CanvasException>()),
      );
    }
    expect(calls, 0);
    expect(
      CanvasService(
        allowedHosts: {'canvas.school.edu'},
      ).validateBaseUrl('https://canvas.school.edu').host,
      'canvas.school.edu',
    );
  });

  test('reads opaque next page and never sends token in URL', () async {
    final seen = <Uri>[];
    final service = CanvasService(
      client: MockClient((request) async {
        seen.add(request.url);
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer $testToken');
        expect(request.url.queryParameters, isNot(contains('access_token')));
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode([
            {'id': seen.length, 'name': 'Course', 'secret_field': 'hidden'},
          ]),
          200,
          headers: seen.length == 1
              ? {'link': '<$base/api/v1/courses?opaque=page-two>; rel="next"'}
              : {},
        );
      }),
    );
    final first = await service.courses(base, testToken);
    final second = await service.courses(
      base,
      testToken,
      cursor: first['next_cursor'] as String,
    );
    expect(seen.last.query, 'opaque=page-two');
    expect(second['next_cursor'], isNull);
    expect((second['items'] as List).single['id'], '2');
    expect(jsonEncode(second), isNot(contains('secret_field')));
  });

  test(
    'rejects cross-origin, unrelated endpoint and credential pagination links',
    () async {
      for (final next in [
        'https://evil.example/api/v1/courses',
        '$base/api/v1/users/self/profile',
        '$base/api/v1/courses?access_token=bad',
      ]) {
        var calls = 0;
        final service = CanvasService(
          client: MockClient((_) async {
            calls++;
            return http.Response(
              '[]',
              200,
              headers: {'link': '<$next>; rel="next"'},
            );
          }),
        );
        await expectLater(
          service.courses(base, testToken),
          throwsA(isA<CanvasException>()),
        );
        expect(calls, 1);
        await expectLater(
          service.courses(base, testToken, cursor: next),
          throwsA(isA<CanvasException>()),
        );
        expect(calls, 1);
      }
    },
  );

  test(
    'redirect and upstream errors never expose response body or token',
    () async {
      for (final status in [302, 401, 403, 429, 500]) {
        final service = CanvasService(
          client: MockClient(
            (_) async => http.Response(
              'private $testToken',
              status,
              headers: {'location': 'https://evil.example'},
            ),
          ),
        );
        try {
          await service.profile(base, testToken);
          fail('expected error');
        } on CanvasException catch (error) {
          expect(error.toString(), isNot(contains(testToken)));
          if (status == 401 || status == 403 || status == 429) {
            expect(error.statusCode, status);
          }
        }
      }
    },
  );

  test('assignments retain due dates and safe submission state', () async {
    final service = CanvasService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/courses/7/assignments');
        expect(request.url.queryParameters['include[]'], 'submission');
        return http.Response(
          jsonEncode([
            {
              'id': 9,
              'name': 'Essay',
              'due_at': '2026-10-01T12:00:00Z',
              'submission': {
                'workflow_state': 'graded',
                'score': 95,
                'private_comment': 'omit',
              },
            },
          ]),
          200,
        );
      }),
    );
    final result = await service.assignments(base, testToken, '7');
    final item = (result['items'] as List).single as Map;
    expect(item['due_at'], '2026-10-01T12:00:00Z');
    expect(item['submission']['score'], 95);
    expect(item['submission'], isNot(contains('private_comment')));
  });

  test(
    'connection is encrypted, persists, isolated and verified before replacement',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ailo-canvas-test-',
      );
      final vault = SecretVault.forTesting(List.filled(32, 19));
      var db = await AppDatabase.open(
        dataDirectory: directory,
        secretVault: vault,
      );
      try {
        final user = await db.createUser(
          email: 'canvas-one@test.local',
          displayName: 'One',
          passwordHash: '',
          passwordSalt: '',
        );
        final other = await db.createUser(
          email: 'canvas-two@test.local',
          displayName: 'Two',
          passwordHash: '',
          passwordSalt: '',
        );
        final session = await db.createAuthSession(user.id);
        final otherSession = await db.createAuthSession(other.id);
        var rejected = false;
        var calls = 0;
        final service = CanvasService(
          client: MockClient((_) async {
            calls++;
            return rejected
                ? http.Response('invalid', 401)
                : http.Response('{"id":42,"name":"Student"}', 200);
          }),
        );
        Handler handler() => CanvasRoutes(db, service).handler;
        Request request(String method, {String? bearer, Object? body}) =>
            Request(
              method,
              Uri.parse('https://ailo.test/connection'),
              headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
              body: body == null ? null : jsonEncode(body),
            );
        final anonymous = await handler()(
          request('PUT', body: {'base_url': base, 'token': testToken}),
        );
        expect(anonymous.statusCode, 401);
        expect(calls, 0);
        final saved = await handler()(
          request(
            'PUT',
            bearer: session.token,
            body: {'base_url': base, 'token': testToken, 'user_id': other.id},
          ),
        );
        expect(saved.statusCode, 200);
        expect(await saved.readAsString(), isNot(contains(testToken)));
        rejected = true;
        final failed = await handler()(
          request(
            'PUT',
            bearer: session.token,
            body: {'base_url': base, 'token': 'invalid-replacement'},
          ),
        );
        expect(failed.statusCode, 401);
        expect((await db.canvasConnection(user.id))!['token'], testToken);
        final otherStatus = await handler()(
          request('GET', bearer: otherSession.token),
        );
        expect(
          jsonDecode(await otherStatus.readAsString())['connected'],
          false,
        );
        final ai = HybridAiService();
        final api = ApiRouter(
          db,
          ai,
          PendingWordEnrichmentProcessor(db, ai),
        ).router;
        final mounted = await api.call(
          Request(
            'GET',
            Uri.parse('https://ailo.test/api/integrations/canvas/connection'),
            headers: {'authorization': 'Bearer ${session.token}'},
          ),
        );
        expect(mounted.statusCode, 200);
        expect(jsonDecode(await mounted.readAsString())['connected'], true);
        await db.close();
        expect(
          latin1.decode(
            await File('${directory.path}/ai_study_os.sqlite3').readAsBytes(),
          ),
          isNot(contains(testToken)),
        );
        db = await AppDatabase.open(
          dataDirectory: directory,
          secretVault: vault,
        );
        expect((await db.canvasConnection(user.id))!['token'], testToken);
        await handler()(request('DELETE', bearer: session.token));
        expect(await db.canvasConnection(user.id), isNull);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
