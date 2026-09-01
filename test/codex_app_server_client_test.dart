import 'dart:async';
import 'dart:convert';

import 'package:ai_study_os/core/codex/codex_app_server_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reads ChatGPT Codex quota windows from the official protocol',
    () async {
      final transport = _FakeCodexTransport();
      final client = CodexAppServerClient(
        requestTimeout: const Duration(seconds: 1),
        transport: transport,
      );
      await client.start(experimentalApi: true);

      final quota = await client.readRateLimits();

      expect(quota.planType, 'team');
      expect(quota.limitId, 'codex');
      expect(quota.primary?.usedPercent, 38);
      expect(quota.primary?.remainingPercent, 62);
      expect(quota.primary?.windowDurationMinutes, 300);
      expect(quota.secondary?.usedPercent, 30);
      expect(quota.secondary?.windowDurationMinutes, 10080);
      await client.dispose();
    },
  );

  test(
    'reads stored messages but excludes reasoning and tool output',
    () async {
      final transport = _FakeCodexTransport();
      final client = CodexAppServerClient(
        requestTimeout: const Duration(seconds: 1),
        transport: transport,
      );
      await client.start(experimentalApi: true);

      final page = await client.listThreads();
      final conversation = await client.readStoredConversation(
        page.threads.single,
      );

      expect(page.threads.single.cwd, r'C:\Users\George\Documents\OSS');
      expect(conversation.isComplete, isTrue);
      expect(conversation.turnCount, 1);
      expect(conversation.transcript, contains('User:\nExplain entropy.'));
      expect(conversation.transcript, contains('Assistant:\nEntropy measures'));
      expect(
        conversation.transcript,
        isNot(contains('private chain of thought')),
      );
      expect(conversation.transcript, isNot(contains('SECRET=abc')));
      await client.dispose();
    },
  );
}

class _FakeCodexTransport implements CodexJsonlTransport {
  final StreamController<String> _lines = StreamController<String>();
  final Completer<void> _done = Completer<void>();

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
    final Object result = switch (method) {
      'initialize' => <String, Object?>{},
      'account/rateLimits/read' => {
        'planType': 'team',
        'rateLimits': {
          'limitId': 'codex',
          'primary': {
            'usedPercent': 38,
            'windowDurationMins': 300,
            'resetsAt': 1788249600,
          },
          'secondary': {
            'usedPercent': 30,
            'windowDurationMins': 10080,
            'resetsAt': 1788768000,
          },
        },
        'credits': {'hasCredits': false, 'unlimited': false},
      },
      'thread/list' => {
        'data': [
          {
            'id': 'thread-oss-1',
            'name': 'Entropy lesson',
            'cwd': r'C:\Users\George\Documents\OSS',
            'createdAt': 1788240000,
            'updatedAt': 1788243600,
            'source': 'vscode',
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
            'completedAt': 1788240010,
            'items': [
              {
                'type': 'userMessage',
                'content': [
                  {'type': 'text', 'text': 'Explain entropy.'},
                ],
              },
              {'type': 'reasoning', 'text': 'private chain of thought'},
              {'type': 'commandExecution', 'aggregatedOutput': 'SECRET=abc'},
              {'type': 'agentMessage', 'text': 'Entropy measures uncertainty.'},
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
