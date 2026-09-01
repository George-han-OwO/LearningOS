import 'dart:async';

import 'package:ai_study_os/core/app_controller.dart';
import 'package:ai_study_os/core/app_scope.dart';
import 'package:ai_study_os/core/security/password_hasher.dart';
import 'package:ai_study_os/data/app_database.dart';
import 'package:ai_study_os/design/app_theme.dart';
import 'package:ai_study_os/design/app_widgets.dart';
import 'package:ai_study_os/domain/models.dart';
import 'package:ai_study_os/features/words/word_bank_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('word import closes immediately and continues in background', (
    tester,
  ) async {
    final database = await AppDatabase.open();
    final controller = _QueuedImportController(database);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: CupertinoApp(
          theme: buildCupertinoTheme(),
          home: const WordBankPage(),
        ),
      ),
    );

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入英文词表'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('word-import-input')),
      'epistemology',
    );
    final submit = tester.widget<AppPrimaryButton>(
      find.byKey(const ValueKey('word-import-submit')),
    );
    submit.onPressed!();
    await tester.pumpAndSettle();

    expect(controller.importStarted, isTrue);
    expect(find.text('导入英文词表'), findsNothing);
    expect(controller.importCompleted, isFalse);

    controller.completeImport();
    await tester.pump(const Duration(seconds: 2));
    expect(controller.importCompleted, isTrue);
  });
}

class _QueuedImportController extends AppController {
  _QueuedImportController(AppDatabase database)
    : super(database, PasswordHasher());

  final Completer<void> _gate = Completer<void>();
  bool importStarted = false;
  bool importCompleted = false;

  @override
  List<StudyWord> get words => const [];

  @override
  List<StudyWord> get dueWords => const [];

  @override
  bool get busy => false;

  @override
  Future<WordImportResult> importWords(String rawText) async {
    importStarted = true;
    await _gate.future;
    importCompleted = true;
    return const WordImportResult(insertedCount: 1, aiEnrichedCount: 0);
  }

  void completeImport() {
    if (!_gate.isCompleted) _gate.complete();
  }
}
