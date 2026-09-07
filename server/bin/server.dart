import 'dart:ffi';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'package:server/api/router.dart';
import 'package:server/data/app_database.dart';
import 'package:server/core/ai/hybrid_ai_service.dart';
import 'package:server/core/ai/pending_word_enrichment.dart';
import 'package:server/core/codex/server_codex_gateway.dart';
import 'package:server/core/security/secret_vault.dart';

void main(List<String> args) async {
  if (args.contains('--generate-master-key')) {
    print(SecretVault.generateMasterKey());
    return;
  }

  _loadBundledSqlite();

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
  final configuredCodexExecutable =
      Platform.environment['AILO_CODEX_EXECUTABLE']?.trim() ?? '';
  final codexGateway = ServerCodexGateway(
    db,
    executable: configuredCodexExecutable.isEmpty
        ? 'codex'
        : configuredCodexExecutable,
  );
  final codexHistoryWorker = CodexHistorySyncWorker(codexGateway);
  codexHistoryWorker.start();
  final pendingWordProcessor = PendingWordEnrichmentProcessor(
    db,
    aiService,
    codexGateway: codexGateway,
  );
  final pendingWordWorker = PendingWordEnrichmentWorker(pendingWordProcessor);
  pendingWordWorker.start();
  print(
    'Codex mobile gateway: ${codexGateway.enabled ? 'enabled' : 'disabled (set AILO_CODEX_GATEWAY_ENABLED=1)'}',
  );

  // Setup Router
  final api = ApiRouter(
    db,
    aiService,
    pendingWordProcessor,
    pendingWordWorker: pendingWordWorker,
    codexGateway: codexGateway,
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

/// AOT executables do not participate in Dart's native-assets build step at
/// runtime. Load the packaged SQLite DLL before sqflite initializes so the FFI
/// resolver can find its symbols in the current process.
void _loadBundledSqlite() {
  if (!Platform.isWindows) return;
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final configured = Platform.environment['AILO_SQLITE3_LIBRARY']?.trim();
  final candidates = <File>[
    if (configured != null && configured.isNotEmpty) File(configured),
    File('${executableDirectory.path}${Platform.pathSeparator}sqlite3.dll'),
    File(
      '${executableDirectory.parent.path}${Platform.pathSeparator}'
      'lib${Platform.pathSeparator}sqlite3.dll',
    ),
  ];
  for (final candidate in candidates) {
    if (!candidate.existsSync()) continue;
    final library = DynamicLibrary.open(candidate.absolute.path);
    if (!library.providesSymbol('sqlite3_initialize')) {
      throw StateError('${candidate.absolute.path} 不是有效的 SQLite 运行库。');
    }
    return;
  }
}
