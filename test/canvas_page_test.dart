import 'package:ai_study_os/core/app_controller.dart';
import 'package:ai_study_os/core/security/password_hasher.dart';
import 'package:ai_study_os/data/app_database.dart';
import 'package:ai_study_os/design/app_theme.dart';
import 'package:ai_study_os/features/canvas/canvas_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('connect clears token and courses load assignments on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _CanvasController(await AppDatabase.open());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(),
        home: CanvasPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      'https://school.instructure.com',
    );
    await tester.enterText(
      find.byType(CupertinoTextField).at(1),
      'test-only-token',
    );
    await tester.tap(find.text('验证并连接'));
    await tester.pumpAndSettle();
    expect(find.text('已连接：Student'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField).at(1))
          .controller!
          .text,
      isEmpty,
    );
    await tester.ensureVisible(find.text('Math →'));
    await tester.tap(find.text('Math →'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Algebra exercise'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Algebra exercise'), findsOneWidget);
    expect(find.text('已评分 · 得分 90'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CanvasController extends AppController {
  _CanvasController(AppDatabase database) : super(database, PasswordHasher());
  @override
  Future<Map<String, dynamic>> canvasConnection() async => {'connected': false};
  @override
  Future<Map<String, dynamic>> connectCanvas(
    String baseUrl,
    String token,
  ) async => {
    'connected': true,
    'base_url': baseUrl,
    'profile': {'name': 'Student'},
  };
  @override
  Future<Map<String, dynamic>> canvasCourses({String? cursor}) async => {
    'items': [
      {'id': '7', 'name': 'Math'},
    ],
    'next_cursor': null,
  };
  @override
  Future<Map<String, dynamic>> canvasAssignments(
    String courseId, {
    String? cursor,
  }) async => {
    'items': [
      {
        'id': '9',
        'name': 'Algebra exercise',
        'due_at': '2026-10-01T12:00:00Z',
        'submission': {'workflow_state': 'graded', 'score': 90},
        'points_possible': 100,
      },
    ],
    'next_cursor': null,
  };
}
