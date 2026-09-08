import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server/api/router.dart';
import 'package:server/core/ai/hybrid_ai_service.dart';
import 'package:server/core/ai/pending_word_enrichment.dart';
import 'package:server/core/codex/codex_app_server_client.dart';
import 'package:server/core/codex/server_codex_gateway.dart';
import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:server/domain/models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late AppUser owner;
  late _Gateway gateway;
  late List<_Client> clients;
  late List<String> homes;
  var authorized = false;
  var failures = false;
  late DateTime now;
  Completer<CodexAccountState>? accountBarrier;
  final vault = SecretVault.forTesting(List.filled(32, 23));

  Future<CodexAppServerClient> factory(Directory home) async {
    homes.add(home.path);
    final client = _Client(() async {
      if (accountBarrier != null) return accountBarrier!.future;
      if (failures) throw StateError('test protocol failure');
      return CodexAccountState(
        account: authorized
            ? const CodexAccount(
                type: 'chatgpt',
                email: 'canvas-owner@example.test',
                planType: 'plus',
              )
            : null,
        requiresOpenaiAuth: true,
      );
    });
    clients.add(client);
    return client;
  }

  Future<Map<String, Object?>> begin() async {
    final attempt = await gateway.startDeviceLogin(owner: owner);
    await gateway.reconcilePendingLogins();
    return attempt;
  }

  Future<ServerCodexLoginResult?> complete(
    Map<String, Object?> attempt, {
    AppUser? requester,
  }) => gateway.completeDeviceLogin(
    attemptId: attempt['attempt_id'] as String,
    attemptSecret: attempt['attempt_secret'] as String,
    requester: requester ?? owner,
  );

  setUp(() async {
    authorized = false;
    failures = false;
    now = DateTime.utc(2026, 9, 8, 12);
    accountBarrier = null;
    clients = [];
    homes = [];
    directory = await Directory.systemTemp.createTemp('ailo-login-recovery-');
    db = await AppDatabase.open(dataDirectory: directory, secretVault: vault);
    owner = await db.createUser(
      email: 'existing-learning-user@test.local',
      displayName: 'Existing',
      passwordHash: '',
      passwordSalt: '',
    );
    await db.saveAiSettings(
      owner.id,
      const AiConnectionSettings(
        enabled: true,
        apiKey: 'preserve-this-deepseek-key',
        model: AiConnectionSettings.defaultModel,
      ),
    );
    gateway = _Gateway(db, clientFactory: factory, clock: () => now);
  });
  tearDown(() async {
    if (accountBarrier != null && !accountBarrier!.isCompleted) {
      accountBarrier!.complete(
        const CodexAccountState(account: null, requiresOpenaiAuth: true),
      );
    }
    await gateway.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'HTTP routes retain bearer owner, return 202, then replay completion',
    () async {
      const ai = HybridAiService();
      final api = ApiRouter(
        db,
        ai,
        PendingWordEnrichmentProcessor(db, ai, codexGateway: gateway),
        codexGateway: gateway,
      );
      final session = await db.createAuthSession(owner.id);
      Future<Response> post(
        String endpoint,
        Map<String, Object?> body, {
        String? token,
      }) => api.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost$endpoint'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer ${token ?? session.token}',
          },
          body: jsonEncode(body),
        ),
      );
      const startPath = '/api/auth/chatgpt/device/start';
      expect(
        (await post(startPath, {}, token: 'invalid-test-token')).statusCode,
        401,
      );
      final started = await post(startPath, {});
      expect(started.statusCode, 200);
      final attempt = jsonDecode(await started.readAsString()) as Map;
      await gateway.reconcilePendingLogins();
      final endpoint =
          '/api/auth/chatgpt/device/${attempt['attempt_id']}/complete';
      final body = {'attempt_secret': attempt['attempt_secret']};
      final pending = await post(endpoint, body);
      expect(pending.statusCode, 202);
      expect(jsonDecode(await pending.readAsString())['pending'], true);
      authorized = true;
      await gateway.reconcilePendingLogins();
      final rejected = await post(endpoint, body, token: 'invalid-test-token');
      expect(rejected.statusCode, 400);
      final completed = await post(endpoint, body);
      final replay = await post(endpoint, body);
      expect(completed.statusCode, 200);
      expect(replay.statusCode, 200);
      final first = jsonDecode(await completed.readAsString()) as Map;
      final second = jsonDecode(await replay.readAsString()) as Map;
      expect(first['user']['id'], owner.id);
      expect(first['auth']['authenticated'], true);
      expect(first['session_token'], second['session_token']);
      expect((await db.aiSettings(owner.id)).provider, AiProvider.deepSeek);
    },
  );

  test('HTTP start reports a structured five-second quiet period', () async {
    const ai = HybridAiService();
    final api = ApiRouter(
      db,
      ai,
      PendingWordEnrichmentProcessor(db, ai, codexGateway: gateway),
      codexGateway: gateway,
    );
    final session = await db.createAuthSession(owner.id);
    Future<Response> start() => api.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/api/auth/chatgpt/device/start'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${session.token}',
        },
        body: '{}',
      ),
    );

    expect((await start()).statusCode, 200);
    final throttled = await start();
    expect(throttled.statusCode, 429);
    final payload = jsonDecode(await throttled.readAsString()) as Map;
    expect(payload['code'], 'codex_login_quiet_period');
    expect(payload['retry_after_seconds'], 5);
    expect(payload['cancelled_attempts'], 1);
  });

  test(
    'missed notification binds existing account without accountId or provider switch',
    () async {
      await db.saveCanvasConnection(owner.id, {
        'token': 'canvas-test-only',
        'base_url': 'https://school.instructure.com',
      });
      final attempt = await begin();
      expect(await complete(attempt), isNull);
      authorized = true;
      await gateway.reconcilePendingLogins();
      final result = await complete(attempt);
      expect(result!.user.id, owner.id);
      expect(result.auth['authenticated'], true);
      expect(result.auth['account_id'], isNull);
      expect(await db.codexHomeIdForUser(owner.id), isNotNull);
      expect((await db.aiSettings(owner.id)).provider, AiProvider.deepSeek);
      expect(
        (await db.aiSettings(owner.id)).apiKey,
        'preserve-this-deepseek-key',
      );
      expect(
        (await db.canvasConnection(owner.id))!['token'],
        'canvas-test-only',
      );
      expect(clients.single.disposed, false);
    },
  );

  test(
    'lost completion response and concurrent retries reuse session; late cancel is harmless',
    () async {
      final attempt = await begin();
      authorized = true;
      await gateway.reconcilePendingLogins();
      final results = await Future.wait([complete(attempt), complete(attempt)]);
      expect(results[0]!.session.token, results[1]!.session.token);
      await gateway.cancelDeviceLogin(
        attemptId: attempt['attempt_id'] as String,
        attemptSecret: attempt['attempt_secret'] as String,
        requester: owner,
      );
      expect(clients.single.disposed, false);
      expect(
        (await complete(attempt))!.session.token,
        results.first!.session.token,
      );
    },
  );

  test(
    'rapid starts cancel only the same owner and require five quiet seconds',
    () async {
      final first = await begin();
      CodexLoginQuietPeriodException? firstCooldown;
      try {
        await gateway.startDeviceLogin(owner: owner);
      } on CodexLoginQuietPeriodException catch (error) {
        firstCooldown = error;
      }
      expect(firstCooldown, isNotNull);
      expect(firstCooldown!.cancelledAttempts, 1);
      expect(firstCooldown.retryAfterSeconds, 5);
      expect(clients.single.cancelled, true);
      expect(clients.single.disposed, true);
      await expectLater(
        complete(first),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('频繁登录'),
          ),
        ),
      );

      now = now.add(const Duration(seconds: 4));
      await expectLater(
        gateway.startDeviceLogin(owner: owner),
        throwsA(
          isA<CodexLoginQuietPeriodException>().having(
            (error) => error.cancelledAttempts,
            'cancelledAttempts',
            0,
          ),
        ),
      );
      expect(clients, hasLength(1));

      // The rejected request above restarted the five-second quiet timer.
      now = now.add(const Duration(seconds: 5));
      final replacement = await gateway.startDeviceLogin(owner: owner);
      expect(replacement['attempt_id'], isNot(first['attempt_id']));
      expect(clients, hasLength(2));
    },
  );

  test('login debounce never cancels another LearningOS user', () async {
    final first = await begin();
    final other = await db.createUser(
      email: 'debounce-other@test.local',
      displayName: 'Other',
      passwordHash: '',
      passwordSalt: '',
    );
    final second = await gateway.startDeviceLogin(owner: other);
    expect(second['attempt_id'], isNot(first['attempt_id']));
    expect(clients, hasLength(2));
    expect(clients.every((client) => !client.cancelled), true);
  });

  test(
    'anonymous login debounce is isolated by random client instance',
    () async {
      final firstClient = List.filled(43, 'A').join();
      final secondClient = List.filled(43, 'B').join();
      final first = await gateway.startDeviceLogin(
        clientInstanceId: firstClient,
      );
      await expectLater(
        gateway.startDeviceLogin(clientInstanceId: firstClient),
        throwsA(isA<CodexLoginQuietPeriodException>()),
      );
      final other = await gateway.startDeviceLogin(
        clientInstanceId: secondClient,
      );
      expect(other['attempt_id'], isNot(first['attempt_id']));
      expect(clients, hasLength(2));
    },
  );

  test('quiet period survives a backend restart', () async {
    await begin();
    await expectLater(
      gateway.startDeviceLogin(owner: owner),
      throwsA(isA<CodexLoginQuietPeriodException>()),
    );
    await gateway.dispose();
    gateway = _Gateway(db, clientFactory: factory, clock: () => now);

    now = now.add(const Duration(seconds: 1));
    await expectLater(
      gateway.startDeviceLogin(owner: owner),
      throwsA(isA<CodexLoginQuietPeriodException>()),
    );
    now = now.add(const Duration(seconds: 5));
    expect(
      await gateway.startDeviceLogin(owner: owner),
      contains('attempt_id'),
    );
  });

  test(
    'exited child restarts in same isolated home and recovers signed-in state',
    () async {
      final attempt = await begin();
      clients.single.alive = false;
      authorized = true;
      await gateway.reconcilePendingLogins();
      expect(clients.length, 2);
      expect(homes.first, homes.last);
      expect(clients.first.disposed, true);
      expect((await complete(attempt))!.user.id, owner.id);
      expect(clients.last.disposed, false);
    },
  );

  test(
    'pending login survives backend and database restart without storing capability plaintext',
    () async {
      final attempt = await begin();
      final stored = (await db.activeCodexLoginAttempts()).single;
      expect(stored.values, isNot(contains(attempt['attempt_secret'])));
      await gateway.dispose();
      await db.close();
      db = await AppDatabase.open(dataDirectory: directory, secretVault: vault);
      gateway = _Gateway(db, clientFactory: factory);
      authorized = true;
      await gateway.reconcilePendingLogins();
      expect((await complete(attempt))!.user.id, owner.id);
      expect(homes.first, homes.last);
    },
  );

  test(
    'completed login is replayable after backend restart without rebinding',
    () async {
      final attempt = await begin();
      authorized = true;
      await gateway.reconcilePendingLogins();
      final bound = await db.codexHomeIdForUser(owner.id);
      await gateway.dispose();
      gateway = _Gateway(db, clientFactory: factory);
      expect((await complete(attempt))!.user.id, owner.id);
      expect(await db.codexHomeIdForUser(owner.id), bound);
      expect(clients.length, 1);
    },
  );

  test('owner and attempt secret must both match', () async {
    final attempt = await begin();
    final other = await db.createUser(
      email: 'other@test.local',
      displayName: 'Other',
      passwordHash: '',
      passwordSalt: '',
    );
    await expectLater(complete(attempt, requester: other), throwsStateError);
    await expectLater(
      gateway.completeDeviceLogin(
        attemptId: attempt['attempt_id'] as String,
        attemptSecret: 'wrong',
        requester: owner,
      ),
      throwsStateError,
    );
    await expectLater(
      gateway.completeDeviceLogin(
        attemptId: attempt['attempt_id'] as String,
        attemptSecret: attempt['attempt_secret'] as String,
      ),
      throwsStateError,
    );
    expect(await db.codexHomeIdForUser(other.id), isNull);
  });

  test(
    'cancel while account verification is in flight cannot bind or kill an older session',
    () async {
      final attempt = await begin();
      accountBarrier = Completer<CodexAccountState>();
      final verifying = gateway.reconcilePendingLogins();
      await Future<void>.delayed(Duration.zero);
      await gateway.cancelDeviceLogin(
        attemptId: attempt['attempt_id'] as String,
        attemptSecret: attempt['attempt_secret'] as String,
        requester: owner,
      );
      accountBarrier!.complete(
        const CodexAccountState(
          account: CodexAccount(type: 'chatgpt'),
          requiresOpenaiAuth: true,
        ),
      );
      await verifying;
      expect(await db.codexHomeIdForUser(owner.id), isNull);
      await expectLater(complete(attempt), throwsStateError);
    },
  );

  test('slow protocol query keeps HTTP completion poll non-blocking', () async {
    final attempt = await begin();
    accountBarrier = Completer<CodexAccountState>();
    expect(await complete(attempt).timeout(const Duration(seconds: 1)), isNull);
    accountBarrier!.complete(
      const CodexAccountState(account: null, requiresOpenaiAuth: true),
    );
    await gateway.reconcilePendingLogins();
  });

  test(
    'persistent account-read errors become an actionable failure instead of eternal pending',
    () async {
      final attempt = await begin();
      failures = true;
      for (var i = 0; i < 3; i++) {
        await gateway.reconcilePendingLogins();
      }
      await expectLater(
        complete(attempt),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('无法确认'),
          ),
        ),
      );
      expect(await db.codexHomeIdForUser(owner.id), isNull);
    },
  );
}

class _Gateway extends ServerCodexGateway {
  _Gateway(super.database, {super.clientFactory, super.clock});
  @override
  bool get enabled => true;
}

class _Client extends CodexAppServerClient {
  _Client(this.read);
  final Future<CodexAccountState> Function() read;
  bool alive = true;
  bool disposed = false;
  bool cancelled = false;
  final _notifications = StreamController<CodexLoginCompleted>.broadcast();
  @override
  bool get isInitialized => alive && !disposed;
  @override
  Stream<CodexLoginCompleted> get loginCompletions => _notifications.stream;
  @override
  Future<CodexChatGptLogin> startChatGptDeviceCodeLogin() async =>
      const CodexChatGptLogin(loginId: 'test-login', userCode: 'FAKE-CODE');
  @override
  Future<CodexAccountState> readAccount({bool refreshToken = false}) => read();
  @override
  Future<void> cancelLogin(String loginId) async {
    cancelled = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _notifications.close();
  }
}
