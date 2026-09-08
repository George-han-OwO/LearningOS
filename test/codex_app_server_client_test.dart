import 'dart:async';
import 'dart:convert';

import 'package:ai_study_os/core/codex/codex_app_server_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed transport is not a reusable initialized client', () async {
    final transport = _FakeCodexTransport();
    final client = CodexAppServerClient(transport: transport);
    await client.start();
    expect(client.isInitialized, isTrue);
    await transport.close();
    await Future<void>.delayed(Duration.zero);
    expect(client.isInitialized, isFalse);
    await client.dispose();
  });

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
      expect(
        transport.lastThreadListParams?['sourceKinds'],
        contains('appServer'),
      );
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

  test('reads every visible model/list page and de-duplicates ids', () async {
    final transport = _FakeCodexTransport();
    final client = CodexAppServerClient(
      requestTimeout: const Duration(seconds: 1),
      transport: transport,
    );
    await client.start(experimentalApi: true);

    expect(await client.listModels(), [
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-5.6-sol',
    ]);
    await client.dispose();
  });

  test('device-code login completes from App Server notification', () async {
    final transport = _FakeCodexTransport();
    final client = CodexAppServerClient(
      requestTimeout: const Duration(seconds: 1),
      transport: transport,
    );
    await client.start(experimentalApi: true);

    final challenge = await client.startChatGptDeviceCodeLogin();
    expect(challenge.loginId, 'login-device-1');
    expect(
      challenge.verificationUrl.toString(),
      'https://auth.openai.com/codex/device',
    );
    expect(challenge.userCode, 'ABCD-1234');

    final state = await client.completeChatGptLogin(
      challenge,
      timeout: const Duration(seconds: 1),
    );
    expect(state.authenticated, isTrue);
    expect(state.account?.type, 'chatgpt');
    expect(state.account?.planType, 'plus');
    await client.dispose();
  });
}

class _FakeCodexTransport implements CodexJsonlTransport {
  final StreamController<String> _lines = StreamController<String>();
  final Completer<void> _done = Completer<void>();
  Map<String, dynamic>? lastThreadListParams;

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
      lastThreadListParams = Map<String, dynamic>.from(
        request['params'] as Map,
      );
    }
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
      'model/list' =>
        (request['params'] as Map?)?['cursor'] == 'models-2'
            ? {
                'data': [
                  // Repeated ids are legal across a changing paginated catalog.
                  {'id': 'gpt-5.6-luna'},
                  {'model': 'gpt-5.6-sol', 'isDefault': true},
                ],
                'nextCursor': null,
              }
            : {
                'data': [
                  {'id': 'gpt-5.6-terra', 'displayName': 'GPT-5.6 Terra'},
                  {'id': 'gpt-5.6-luna', 'displayName': 'GPT-5.6 Luna'},
                ],
                'nextCursor': 'models-2',
              },
      'account/login/start' => {
        'type': 'chatgptDeviceCode',
        'loginId': 'login-device-1',
        'verificationUrl': 'https://auth.openai.com/codex/device',
        'userCode': 'ABCD-1234',
      },
      'account/read' => {
        'account': {
          'type': 'chatgpt',
          'accountId': 'account-1',
          'email': 'learner@example.test',
          'planType': 'plus',
        },
        'requiresOpenaiAuth': false,
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
    if (method == 'account/login/start') {
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        _lines.add(
          jsonEncode({
            'method': 'account/login/completed',
            'params': {
              'loginId': 'login-device-1',
              'success': true,
              'error': null,
            },
          }),
        );
      });
    }
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _lines.close();
  }
}
