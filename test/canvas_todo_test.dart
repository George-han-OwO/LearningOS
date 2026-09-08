import 'package:ai_study_os/core/app_controller.dart';
import 'package:ai_study_os/core/security/password_hasher.dart';
import 'package:ai_study_os/data/app_database.dart';
import 'package:ai_study_os/domain/canvas_todo.dart';
import 'package:ai_study_os/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas assignments become pending and completed home items', () async {
    final controller = _CanvasTodoController(await AppDatabase.open());
    addTearDown(controller.dispose);

    await controller.refreshCanvasTodos();

    expect(controller.canvasTodoState.connected, isTrue);
    expect(controller.canvasTodoState.profileName, 'Student');
    expect(controller.canvasTodoState.pending.single.title, 'Essay');
    expect(controller.canvasTodoState.pending.single.missing, isTrue);
    expect(controller.canvasTodoState.completed.single.title, 'Quiz');
    expect(
      controller.canvasTodoState.completed.single.statusLabel,
      contains('90'),
    );
  });

  test('Canvas pending assignments sort by the nearest deadline', () {
    final now = DateTime.now();
    final state = CanvasTodoState(
      connected: true,
      loading: false,
      items: [
        CanvasTodoItem(
          id: 'later',
          courseName: 'Math',
          title: 'Later',
          dueAt: now.add(const Duration(days: 2)),
          completed: false,
          statusLabel: '未提交',
        ),
        CanvasTodoItem(
          id: 'soon',
          courseName: 'Math',
          title: 'Soon',
          dueAt: now.add(const Duration(hours: 2)),
          completed: false,
          statusLabel: '未提交',
        ),
      ],
    );

    expect(state.pending.map((item) => item.id), ['soon', 'later']);
  });
}

class _CanvasTodoController extends AppController {
  _CanvasTodoController(AppDatabase database)
    : super(database, PasswordHasher());

  @override
  AppUser get currentUser => AppUser(
    id: 1,
    email: 'student@example.test',
    displayName: 'Student',
    createdAt: DateTime(2026, 9, 7),
  );

  @override
  Future<Map<String, dynamic>> canvasConnection() async => {
    'connected': true,
    'profile': {'name': 'Student'},
  };

  @override
  Future<Map<String, dynamic>> canvasCourses({String? cursor}) async => {
    'items': [
      {'id': '7', 'name': 'English'},
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
        'id': 'essay',
        'name': 'Essay',
        'due_at': '2026-09-08T12:00:00Z',
        'submission': {'workflow_state': 'unsubmitted', 'missing': true},
      },
      {
        'id': 'quiz',
        'name': 'Quiz',
        'due_at': '2026-09-06T12:00:00Z',
        'points_possible': 100,
        'submission': {
          'workflow_state': 'graded',
          'score': 90,
          'submitted_at': '2026-09-06T11:00:00Z',
        },
      },
    ],
    'next_cursor': null,
  };
}
