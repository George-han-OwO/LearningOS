import 'dart:async';
import 'dart:convert';

import 'package:server/core/codex/codex_app_server_client.dart';
import 'package:test/test.dart';

void main() {
  test('closed transport is not a reusable initialized client', () async {
    final transport = _CatalogTransport();
    final client = CodexAppServerClient(transport: transport);
    await client.start();
    expect(client.isInitialized, isTrue);
    await transport.close();
    await Future<void>.delayed(Duration.zero);
    expect(client.isInitialized, isFalse);
    await client.dispose();
  });

  test(
    'server client enables history API and reads every model page',
    () async {
      final transport = _CatalogTransport();
      final client = CodexAppServerClient(
        requestTimeout: const Duration(seconds: 1),
        transport: transport,
      );

      await client.start(experimentalApi: true);

      expect(transport.experimentalApiEnabled, isTrue);
      expect(await client.listModels(), [
        'gpt-5.6-terra',
        'gpt-5.6-luna',
        'gpt-5.6-sol',
      ]);
      await client.dispose();
    },
  );
}

class _CatalogTransport implements CodexJsonlTransport {
  final StreamController<String> _lines = StreamController<String>();
  final Completer<void> _done = Completer<void>();
  bool experimentalApiEnabled = false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> writeLine(String line) async {
    final request = Map<String, dynamic>.from(jsonDecode(line) as Map);
    final id = request['id'];
    if (id == null) return;
    final method = request['method'];
    Object result;
    if (method == 'initialize') {
      final params = request['params'] as Map?;
      final capabilities = params?['capabilities'] as Map?;
      experimentalApiEnabled = capabilities?['experimentalApi'] == true;
      result = <String, Object?>{};
    } else if (method == 'model/list') {
      final params = request['params'] as Map?;
      result = params?['cursor'] == 'models-2'
          ? {
              'data': [
                {'id': 'gpt-5.6-luna'},
                {'model': 'gpt-5.6-sol'},
              ],
              'nextCursor': null,
            }
          : {
              'data': [
                {'id': 'gpt-5.6-terra'},
                {'id': 'gpt-5.6-luna'},
              ],
              'nextCursor': 'models-2',
            };
    } else {
      throw StateError('Unexpected method: $method');
    }
    scheduleMicrotask(
      () => _lines.add(jsonEncode({'id': id, 'result': result})),
    );
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _lines.close();
  }
}
