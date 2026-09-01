import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'package:server/api/router.dart';
import 'package:server/data/app_database.dart';
import 'package:server/core/ai/hybrid_ai_service.dart';
import 'package:server/core/ai/pending_word_enrichment.dart';
import 'package:server/core/security/secret_vault.dart';

void main(List<String> args) async {
  if (args.contains('--generate-master-key')) {
    print(SecretVault.generateMasterKey());
    return;
  }

  // Initialize Database
  final configuredDataDirectory =
      Platform.environment['AILO_DATA_DIRECTORY']?.trim() ?? '';
  final db = await AppDatabase.open(
    dataDirectory: configuredDataDirectory.isEmpty
        ? null
        : Directory(configuredDataDirectory),
  );
  print('Database initialized at ${db.filePath}');
  print(
    'Secret vault: ${db.secretVaultReady ? 'AES-256-GCM ready' : 'not configured'}',
  );

  // Initialize AI Services
  final aiService = HybridAiService();
  final pendingWordProcessor = PendingWordEnrichmentProcessor(db, aiService);
  final pendingWordWorker = PendingWordEnrichmentWorker(pendingWordProcessor);
  pendingWordWorker.start();

  // Setup Router
  final api = ApiRouter(
    db,
    aiService,
    pendingWordProcessor,
    pendingWordWorker: pendingWordWorker,
  );

  // Setup Pipeline
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(api.router.call);

  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
