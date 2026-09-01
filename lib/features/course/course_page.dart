import 'package:flutter/cupertino.dart';

import '../../core/app_controller.dart';
import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';

class CoursePage extends StatefulWidget {
  const CoursePage({super.key});

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  String? _selectedChapterId;
  final Map<String, int> _answers = {};
  bool _submitting = false;
  bool _requestedPlan = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedPlan) return;
    _requestedPlan = true;
    AppScope.of(context).refreshCoursePlan();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final chapters = controller.courseChapters;
    final selected = chapters
        .where((chapter) => chapter.chapterId == _selectedChapterId)
        .firstOrNull;
    final dailyPlan = controller.courseDailyPlan;
    final completed = chapters.where((chapter) => chapter.isCompleted).length;
    final progress = chapters.isEmpty ? 0.0 : completed / chapters.length;

    return AppPage(
      title: 'AI 学习课程',
      subtitle: '18 个月 · 章节打卡 · AI 个性化布置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CourseOverview(
            completed: completed,
            total: chapters.length,
            progress: progress,
          ),
          const SizedBox(height: 18),
          _DailyPlanCard(
            plan: dailyPlan,
            loading: controller.busy && dailyPlan == null,
            onRefresh: controller.refreshCoursePlan,
            onOpenChapter: (chapterId) => setState(() {
              _selectedChapterId = chapterId;
              _answers.clear();
            }),
          ),
          const SizedBox(height: 18),
          if (chapters.isEmpty)
            const AppCard(
              child: Text('课程服务尚未返回章节。请确认服务器已更新到课程 API；旧服务器不会影响原有笔记功能。'),
            )
          else ...[
            AppGroup(
              title: '课程地图',
              children: [
                for (final chapter in chapters)
                  _ChapterRow(
                    chapter: chapter,
                    selected: chapter.chapterId == _selectedChapterId,
                    onTap: chapter.isUnlocked
                        ? () => setState(() {
                            _selectedChapterId = chapter.chapterId;
                            _answers.clear();
                          })
                        : null,
                  ),
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 18),
              _ChapterLesson(
                chapter: selected,
                answers: _answers,
                submitting: _submitting,
                onAnswer: (questionId, answer) =>
                    setState(() => _answers[questionId] = answer),
                onSubmit: () => _submit(controller, selected),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _submit(AppController controller, CourseChapter chapter) async {
    if (_answers.length < chapter.questions.length) {
      await showAppMessage(
        context,
        title: '还差几道题',
        message: '请先完成本章全部选择题，再提交章节测试。',
        tone: AppMessageTone.warning,
      );
      return;
    }
    setState(() => _submitting = true);
    final result = await controller.submitCourseAttempt(
      chapterId: chapter.chapterId,
      answers: Map<String, int>.from(_answers),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    await showAppMessage(
      context,
      title: result.passed ? '章节通过' : '需要补课',
      message:
          '${result.message}\n本次得分：${(result.score * 100).round()}%'
          '${result.wrongQuestionIds.isEmpty ? '' : '\n错题：${result.wrongQuestionIds.join('、')}'}',
      tone: result.passed ? AppMessageTone.success : AppMessageTone.info,
    );
  }
}

class _DailyPlanCard extends StatelessWidget {
  const _DailyPlanCard({
    required this.plan,
    required this.loading,
    required this.onRefresh,
    required this.onOpenChapter,
  });

  final CourseDailyPlan? plan;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onOpenChapter;

  @override
  Widget build(BuildContext context) {
    final current = plan;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.calendar_badge_plus),
              const SizedBox(width: 9),
              Expanded(
                child: Text('今日 AI 布置', style: AppTextStyles.sectionTitle),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: loading ? null : onRefresh,
                child: Text(loading ? '生成中…' : '重新生成'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (current == null)
            const Text('正在读取课程进度和学习摘要，生成今天的第一份计划…')
          else ...[
            Text(current.title, style: AppTextStyles.title),
            const SizedBox(height: 4),
            Text(
              '${current.phase} · ${current.aiGenerated ? '根据你的学习记录生成' : '本地保底计划'}',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 10),
            Text(current.rationale, style: AppTextStyles.body),
            const SizedBox(height: 10),
            for (final task in current.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('□ $task', style: AppTextStyles.body),
              ),
            if (current.testFocus.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '测试重点：${current.testFocus.join('、')}',
                style: AppTextStyles.caption,
              ),
            ],
            if (current.chapterId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  onPressed: () => onOpenChapter(current.chapterId),
                  child: const Text('进入本章'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CourseOverview extends StatelessWidget {
  const _CourseOverview({
    required this.completed,
    required this.total,
    required this.progress,
  });

  final int completed;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      tone: LiquidGlassTone.accent,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.sparkles, color: Color(0xFFFFFFFF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '从 AP 统计走到自己的小模型',
                  style: AppTextStyles.title.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
              Text(
                '$completed / $total',
                style: AppTextStyles.body.copyWith(
                  color: const Color(0xE6FFFFFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '每章都有讲解、实验和选择题测试。通过后解锁下一章，失败则保留错题并安排补课。',
            style: AppTextStyles.body.copyWith(color: const Color(0xE6FFFFFF)),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0x40FFFFFF)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0, 1),
                    child: const ColoredBox(color: Color(0xFFFFFFFF)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.selected,
    required this.onTap,
  });

  final CourseChapter chapter;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = chapter.status == CourseChapterStatus.locked;
    final completed = chapter.isCompleted;
    final icon = locked
        ? CupertinoIcons.lock_fill
        : completed
        ? CupertinoIcons.checkmark_circle_fill
        : CupertinoIcons.play_circle_fill;
    final tint = locked
        ? AppPalette.secondaryText
        : completed
        ? AppPalette.green
        : AppPalette.blue;
    final status = locked
        ? '完成上一章后解锁'
        : completed
        ? '已完成 · 掌握 ${(chapter.mastery * 100).round()}%'
        : chapter.attempts == 0
        ? '开始学习'
        : '继续学习 · 上次 ${(chapter.lastScore ?? 0) * 100 ~/ 1}%';
    return AppGroupRow(
      icon: icon,
      title: '${chapter.orderIndex}. ${chapter.title}',
      subtitle: '${chapter.phase} · $status',
      tint: tint,
      tintBackground: selected ? AppPalette.blueSoft : AppPalette.softSurface,
      onTap: onTap,
      trailing: Text(
        '${chapter.questions.length} 题',
        style: AppTextStyles.caption.copyWith(
          color: AppPalette.resolve(context, AppPalette.secondaryText),
        ),
      ),
    );
  }
}

class _ChapterLesson extends StatelessWidget {
  const _ChapterLesson({
    required this.chapter,
    required this.answers,
    required this.submitting,
    required this.onAnswer,
    required this.onSubmit,
  });

  final CourseChapter chapter;
  final Map<String, int> answers;
  final bool submitting;
  final void Function(String questionId, int option) onAnswer;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chapter.title, style: AppTextStyles.title),
              const SizedBox(height: 8),
              Text(chapter.description, style: AppTextStyles.body),
              const SizedBox(height: 16),
              Text(chapter.lesson, style: AppTextStyles.body),
              const SizedBox(height: 16),
              Text('本章目标', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 8),
              for (final objective in chapter.objectives)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('• $objective', style: AppTextStyles.body),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppGroup(
          title: '章节测试 · 全部完成后提交',
          children: [
            for (var index = 0; index < chapter.questions.length; index++)
              _QuestionCard(
                index: index,
                question: chapter.questions[index],
                selectedOption: answers[chapter.questions[index].id],
                onSelected: (option) =>
                    onAnswer(chapter.questions[index].id, option),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AppPrimaryButton(
          label: submitting ? '正在评分…' : '提交章节测试',
          icon: CupertinoIcons.checkmark_seal_fill,
          fullWidth: true,
          onPressed: submitting ? null : onSubmit,
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selectedOption,
    required this.onSelected,
  });

  final int index;
  final CourseQuestion question;
  final int? selectedOption;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${index + 1}. ${question.prompt}', style: AppTextStyles.body),
          const SizedBox(height: 10),
          for (var option = 0; option < question.options.length; option++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _OptionButton(
                label:
                    '${String.fromCharCode(65 + option)}. ${question.options[option]}',
                selected: selectedOption == option,
                onPressed: () => onSelected(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      pressedOpacity: 0.7,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.resolve(context, AppPalette.blueSoft)
              : AppPalette.resolve(context, AppPalette.softSurface),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? AppPalette.resolve(context, AppPalette.blue)
                : AppPalette.resolve(context, AppPalette.separator),
            width: selected ? 1.1 : 0.7,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.largecircle_fill_circle
                  : CupertinoIcons.circle,
              size: 17,
              color: selected
                  ? AppPalette.resolve(context, AppPalette.blue)
                  : AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(label, style: AppTextStyles.body)),
          ],
        ),
      ),
    );
  }
}
