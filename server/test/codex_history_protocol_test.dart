import 'dart:async';
import 'dart:convert';

import 'package:server/core/codex/codex_app_server_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'lists App Server threads and reads only safe conversation text',
    () async {
      final transport = _HistoryTransport();
      final client = CodexAppServerClient(
        requestTimeout: const Duration(seconds: 1),
        transport: transport,
      );
      await client.start(experimentalApi: true);

      final page = await client.listThreads();
      final conversation = await client.readStoredConversation(
        page.threads.single,
      );

      expect(transport.threadListParams['sourceKinds'], contains('appServer'));
      expect(page.threads.single.cwd, r'D:\AI-Study\OSS');
      expect(conversation.isComplete, isTrue);
      expect(conversation.transcript, contains('User:\nExplain competition.'));
      expect(conversation.transcript, contains('Assistant:\nCompetition'));
      expect(conversation.transcript, isNot(contains('private reasoning')));
      expect(conversation.transcript, isNot(contains('SECRET')));

      await client.dispose();
    },
  );
}

class _HistoryTransport implements CodexJsonlTransport {
  final _lines = StreamController<String>();
  final _done = Completer<void>();
  Map<String, dynamic> threadListParams = {};

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
    if (method == 'thread/list') {
      threadListParams = Map<String, dynamic>.from(request['params'] as Map);
    }
    final Object result = switch (method) {
      'initialize' => <String, Object?>{},
      'thread/list' => {
        'data': [
          {
            'id': 'oss-app-server-thread',
            'name': 'Ecology lesson',
            'cwd': r'D:\AI-Study\OSS',
            'updatedAt': 1788243600,
            'source': 'appServer',
          },
        ],
        'nextCursor': null,
      },
      'thread/turns/list' => {
        'data': [
          {
            'id': 'turn-1',
            'status': 'completed',
            'startedAt': 1788240000,
            'items': [
              {
                'type': 'userMessage',
                'content': [
                  {'type': 'text', 'text': 'Explain competition.'},
                ],
              },
              {'type': 'reasoning', 'text': 'private reasoning'},
              {'type': 'commandExecution', 'aggregatedOutput': 'SECRET'},
              {
                'type': 'agentMessage',
                'text': 'Competition occurs when resources overlap.',
              },
            ],
          },
        ],
        'nextCursor': null,
      },
      _ => throw StateError('Unexpected method: $method'),
    };
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
