import 'package:flutter/cupertino.dart';

import 'core/app_scope.dart';
import 'design/app_theme.dart';
import 'features/auth/auth_page.dart';
import 'features/shell/app_shell.dart';

class AiStudyOsApp extends StatelessWidget {
  const AiStudyOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return CupertinoApp(
      title: 'AILearningOS',
      debugShowCheckedModeBanner: false,
      theme: buildCupertinoTheme(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: controller.authenticated
            ? const AppShell(key: ValueKey('app-shell'))
            : const AuthPage(key: ValueKey('auth-page')),
      ),
    );
  }
}

class BootFailureApp extends StatelessWidget {
  const BootFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'AILearningOS',
      debugShowCheckedModeBanner: false,
      theme: buildCupertinoTheme(),
      home: CupertinoPageScaffold(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 44,
                    color: AppPalette.red,
                  ),
                  const SizedBox(height: 16),
                  const Text('AILearningOS 无法启动', style: AppTextStyles.title),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
