import 'package:ai_study_os/core/app_controller.dart';
import 'package:ai_study_os/core/app_scope.dart';
import 'package:ai_study_os/core/security/password_hasher.dart';
import 'package:ai_study_os/data/app_database.dart';
import 'package:ai_study_os/design/app_theme.dart';
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

    await tester.tap(find.text('单词'));
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

    await tester.tap(find.text('学习笔记'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AI 分析'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
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

    await tester.tap(find.text('主页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('ChatGPT-Codex'), findsWidgets);
    expect(find.textContaining('Canvas'), findsNothing);
    if (_writePreviews) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/mobile_profile.png'),
      );
    }
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
