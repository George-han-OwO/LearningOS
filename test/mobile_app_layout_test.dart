import 'package:ai_study_os/core/app_controller.dart';
import 'package:ai_study_os/core/app_scope.dart';
import 'package:ai_study_os/core/codex/chatgpt_auth_service.dart';
import 'package:ai_study_os/core/security/password_hasher.dart';
import 'package:ai_study_os/data/app_database.dart';
import 'package:ai_study_os/design/app_theme.dart';
import 'package:ai_study_os/design/app_widgets.dart';
import 'package:ai_study_os/domain/canvas_todo.dart';
import 'package:ai_study_os/domain/models.dart';
import 'package:ai_study_os/features/shell/app_shell.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const _writePreviews = bool.fromEnvironment('AIL_UI_PREVIEWS');

void main() {
  testWidgets('primary mobile pages render without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = await AppDatabase.open();
    final controller = _PreviewController(database);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: CupertinoApp(
          theme: buildCupertinoTheme(),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (_writePreviews) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/mobile_today.png'),
      );
    }

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('AP Statistics'), findsOneWidget);
    expect(find.text('Submit statistics project'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('today-course-AP Statistics')));
    await tester.pumpAndSettle();
    expect(find.text('Submit statistics project'), findsOneWidget);
    final mobileTabBar = tester.widget<CupertinoTabBar>(
      find.byType(CupertinoTabBar),
    );
    expect(
      mobileTabBar.items.map((item) => item.label),
      orderedEquals(['Home', 'Words', 'Journal', 'Setting']),
    );
    final bottomBarSurface = tester.widget<LiquidGlassSurface>(
      find.byKey(const ValueKey('mobile-bottom-bar-surface')),
    );
    expect(bottomBarSurface.radius, 0);

    await tester.tap(find.text('Words'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('手动导入'), findsOneWidget);
    expect(find.text('AI 导入'), findsOneWidget);
    if (_writePreviews) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/mobile_word_bank.png'),
      );
    }

    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AI 分析'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('Evidence Pack'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('evidence-pack-entry')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('角色查询'), findsOneWidget);
    expect(find.text('Learner'), findsWidgets);
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('MEL'), findsWidgets);
    expect(find.byKey(const ValueKey('evidence-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-weekly')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('evidence-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('录音日记'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('每天，都值得被收藏。'), findsOneWidget);
    if (_writePreviews) {
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/recording_shelf.png'),
      );
    }
    await tester.tap(find.byIcon(CupertinoIcons.arrow_right));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-09-09').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('今日录音测试摘要'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    final journalField = tester.widget<CupertinoTextField>(
      find.descendant(
        of: find.byKey(const ValueKey('journal-editor')),
        matching: find.byType(CupertinoTextField),
      ),
    );
    expect(journalField.controller!.text, startsWith('# Learning Journal'));
    expect(journalField.controller!.text, contains('## 8. 自由记录'));
    await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
    await tester.pumpAndSettle();
    if (_writePreviews) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/mobile_library.png'),
      );
    }

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setting'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('ChatGPT-Codex'), findsWidgets);
    expect(find.text('Canvas LMS'), findsOneWidget);
    expect(find.text('AI 用量 / 剩余额度'), findsOneWidget);
    if (_writePreviews) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/mobile_profile.png'),
      );
    }
  });

  testWidgets('desktop uses a three-column social feed layout', (tester) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _PreviewController(await AppDatabase.open());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: CupertinoApp(
          theme: buildCupertinoTheme(),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Georgehan'), findsWidgets);
    expect(find.text('Canvas'), findsOneWidget);
    expect(find.text('剩余 62%'), findsOneWidget);
    expect(find.text('剩余 70%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PreviewController extends AppController {
  _PreviewController(AppDatabase database) : super(database, PasswordHasher());

  final _now = DateTime.now();

  @override
  AppUser get currentUser => AppUser(
    id: 1,
    email: 'georgehan@example.com',
    displayName: 'Georgehan',
    createdAt: _now,
  );

  @override
  List<StudyWord> get words => [
    _word(1, 'population', '/ˌpɒpjəˈleɪʃən/', '总体', 72),
    _word(2, 'sample', '/ˈsɑːmpəl/', '样本', 48),
    _word(3, 'variable', '/ˈveəriəbəl/', '变量', 20),
  ];

  @override
  List<StudyWord> get dueWords => words;

  @override
  List<StudyNote> get notes => [
    StudyNote(
      id: 50,
      userId: 1,
      title: '2026-09-09 · 录音日记',
      contentEnglish: '',
      contentChinese: '今日录音测试摘要',
      source: '飞书录音每日总结:2026-09-09',
      updatedAt: _now,
    ),
    StudyNote(
      id: 1,
      userId: 1,
      title: 'AP Statistics：总体、样本与变量',
      contentEnglish:
          'The lesson explains how a sample represents a population and how variables describe observations.',
      contentChinese: '本节课区分了总体、样本和变量，并解释随机抽样为什么能够降低选择偏差。',
      source: 'soundcore Work · 录音豆',
      updatedAt: _now,
    ),
    StudyNote(
      id: 2,
      userId: 1,
      title: 'DeepSeek V4 权重与相关度入门',
      contentEnglish:
          'An introductory discussion of tokens, embeddings, attention, and model weights.',
      contentChinese: '从 token、向量和注意力开始理解模型如何计算相关度，并为后续微积分做准备。',
      source: 'ChatGPT 自动摘要',
      updatedAt: _now,
    ),
  ];

  @override
  TodayStats get todayStats => const TodayStats(
    dueWords: 3,
    newWords: 1,
    reviewsCompleted: 2,
    minutes: 47,
    checkedIn: false,
  );

  @override
  ConversationSyncState get conversationSyncState => ConversationSyncState(
    enabled: true,
    intervalMinutes: 15,
    status: ConversationSyncStatus.synced,
    lastSyncedAt: _now,
    lastSyncedTitle: 'AP Statistics：总体、样本与变量',
    scheduleConfigured: true,
  );

  @override
  bool get aiReady => true;

  @override
  String get activeAiProviderLabel => 'DeepSeek API';

  @override
  CanvasTodoState get canvasTodoState => CanvasTodoState(
    connected: true,
    loading: false,
    profileName: 'Georgehan',
    refreshedAt: _now,
    items: [
      CanvasTodoItem(
        id: 'canvas-1',
        courseName: 'AP Statistics',
        title: 'Submit statistics project',
        dueAt: _now.add(const Duration(hours: 6)),
        completed: false,
        statusLabel: '未提交',
      ),
      CanvasTodoItem(
        id: 'canvas-2',
        courseName: 'Calculus',
        title: 'Limits quiz',
        submittedAt: _now.subtract(const Duration(hours: 2)),
        completed: true,
        statusLabel: '已评分 · 得分 90',
      ),
    ],
  );

  @override
  ChatGptAuthState get chatGptAuth => const ChatGptAuthState(
    available: true,
    authenticated: true,
    planType: 'plus',
  );

  @override
  ChatGptCodexQuotaState get codexQuota => ChatGptCodexQuotaState(
    available: true,
    planType: 'plus',
    primaryUsedPercent: 38,
    primaryWindowMinutes: 300,
    primaryResetsAt: _now.add(const Duration(hours: 2)),
    secondaryUsedPercent: 30,
    secondaryWindowMinutes: 10080,
    secondaryResetsAt: _now.add(const Duration(days: 3)),
  );

  @override
  String get activeAiModel => 'deepseek-v4-flash';

  StudyWord _word(
    int id,
    String value,
    String phonetic,
    String translation,
    int mastery,
  ) => StudyWord(
    id: id,
    userId: 1,
    word: value,
    phonetic: phonetic,
    partOfSpeech: 'noun',
    translation: translation,
    exampleEnglish: 'This is a focused example for $value.',
    exampleChinese: '这是一个关于“$translation”的例句。',
    mastery: mastery,
    intervalDays: 1,
    dueAt: _now.subtract(const Duration(hours: 1)),
    createdAt: _now.subtract(const Duration(days: 2)),
  );
}
