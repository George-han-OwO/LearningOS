import 'dart:io';

import 'package:flutter/cupertino.dart';

import 'app.dart';
import 'core/ai/hybrid_ai_service.dart';
import 'core/app_controller.dart';
import 'core/app_scope.dart';
import 'core/codex/local_chatgpt_auth_service.dart';
import 'core/codex/remote_chatgpt_auth_service.dart';
import 'core/security/password_hasher.dart';
import 'data/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final database = await AppDatabase.open();
    await database.restoreSession();
    // Phones never ship or launch a Codex executable. They use the trusted
    // HTTPS device-code gateway, while desktop keeps the local App Server.
    final chatGptAuthService = Platform.isAndroid || Platform.isIOS
        ? RemoteCodexChatGptAuthService(database)
        : LocalCodexChatGptAuthService();
    final controller = AppController(
      database,
      PasswordHasher(),
      const HybridAiService(),
      chatGptAuthService,
    );
    await controller.initialize();

    runApp(AppScope(controller: controller, child: const AiStudyOsApp()));
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'AILearningOS bootstrap',
      ),
    );
    runApp(BootFailureApp(error: error));
  }
}
