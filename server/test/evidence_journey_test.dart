import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server/api/router.dart';
import 'package:server/core/ai/hybrid_ai_service.dart';
import 'package:server/core/ai/pending_word_enrichment.dart';
import 'package:server/core/security/secret_vault.dart';
import 'package:server/data/app_database.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:test/test.dart';

/// An isolated end-to-end evidence run. The records come from the learner's
/// current course materials and the two experiments run on 2026-09-04; it does
/// not use or modify a production account/database.
void main() {
  late HttpServer server;
  late AppDatabase database;
  late Directory dataDirectory;
  late String host;

  setUpAll(() async {
    dataDirectory = await Directory.systemTemp.createTemp('ailo-evidence-');
    database = await AppDatabase.open(
      dataDirectory: dataDirectory,
      secretVault: SecretVault.forTesting(List<int>.filled(32, 61)),
    );
    final aiService = HybridAiService();
    final api = ApiRouter(
      database,
      aiService,
      PendingWordEnrichmentProcessor(database, aiService),
    );
    server = await serve(
      Pipeline().addHandler(api.router.call),
      InternetAddress.loopbackIPv4,
      0,
    );
    host = 'http://127.0.0.1:${server.port}';
  });

  tearDownAll(() async {
    await server.close(force: true);
    await database.close();
    await dataDirectory.delete(recursive: true);
  });

  test(
    'three recent learner records retain their sources and are found again',
    () async {
      final createUser = await http.post(
        Uri.parse('$host/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'evidence-learner@test.local',
          'display_name': 'Evidence Learner',
          'password_hash': '',
          'password_salt': '',
        }),
      );
      expect(createUser.statusCode, 200);
      final created = jsonDecode(createUser.body) as Map<String, dynamic>;
      final userId = (created['user']['id'] as num).toInt();
      final bearer = created['session_token'] as String;
      final authorizedHeaders = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $bearer',
      };

      final records = [
        {
          'title': 'Attention：causal mask 验证',
          'content_en':
              'Ran the causal-attention experiment. Every visible-weight row sums to 1; future tokens receive zero weight.',
          'content_zh': '运行实验04：每行注意力权重和为1，且因果遮罩不偷看未来 token。',
          'source': '课程/实验/04_手搓_attention.py（2026-09-04运行）',
        },
        {
          'title': 'MoE Router：top-k gate',
          'content_en':
              'Ran the MoE-router experiment. Experts 0 and 3 were selected; normalized gates were 0.5183 and 0.4817.',
          'content_zh': '运行实验05：选择专家0、3；归一化 gate 为0.5183、0.4817。',
          'source': '课程/实验/05_手搓_MoE_router.py（2026-09-04运行）',
        },
        {
          'title': 'Chapter 01：权重与概率',
          'content_en':
              'Prepared the six-question check: parameter weights, dot-product matching, softmax, gradients, and context-dependent relevance.',
          'content_zh': '整理第1章6题测试要点；本记录不声称已提交答题或通过。',
          'source': '课程/章节测试/01-权重与概率.md（近期学习材料）',
        },
      ];

      for (final record in records) {
        final response = await http.post(
          Uri.parse('$host/api/notes/$userId'),
          headers: authorizedHeaders,
          body: jsonEncode(record),
        );
        expect(response.statusCode, 200);
      }

      final readBack = await http.get(
        Uri.parse('$host/api/notes/$userId'),
        headers: {'Authorization': 'Bearer $bearer'},
      );
      expect(readBack.statusCode, 200);
      final notes = (jsonDecode(readBack.body) as List)
          .cast<Map<String, dynamic>>();
      expect(notes, hasLength(3));
      expect(
        notes.map((note) => note['source']),
        containsAll(records.map((record) => record['source'])),
      );
      expect(
        notes.map((note) => note['title']),
        containsAll(records.map((record) => record['title'])),
      );
      print(
        jsonEncode({
          'evidence_journey': 'passed',
          'written': records.length,
          'retrieved': notes.length,
          'sources_preserved': notes.map((note) => note['source']).toList(),
        }),
      );

      final anonymous = await http.get(Uri.parse('$host/api/notes/$userId'));
      expect(anonymous.statusCode, 401);

      final outsiderResponse = await http.post(
        Uri.parse('$host/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'evidence-outsider@test.local',
          'display_name': 'Evidence Outsider',
          'password_hash': '',
          'password_salt': '',
        }),
      );
      final outsider =
          jsonDecode(outsiderResponse.body) as Map<String, dynamic>;
      final forbidden = await http.get(
        Uri.parse('$host/api/notes/$userId'),
        headers: {'Authorization': 'Bearer ${outsider['session_token']}'},
      );
      expect(forbidden.statusCode, 403);
    },
  );
}
