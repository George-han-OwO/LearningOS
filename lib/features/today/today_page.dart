import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';
import '../shell/app_shell.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({required this.onNavigate, super.key});

  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final stats = controller.todayStats;
    final user = controller.currentUser!;

    return AppPage(
      title: '今日 Note',
      subtitle: '${user.displayName} · ${_todayLabel()}',
      actions: [
        AppIconButton(
          icon: CupertinoIcons.person,
          semanticLabel: '打开设置',
          onPressed: () => onNavigate(AppDestination.profile),
        ),
      ],
      inlineMobileActions: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final hero = _TodayHero(
            dueCount: stats.dueWords,
            newCount: stats.newWords,
            progress: stats.progress,
            completed: stats.reviewsCompleted,
            onStart: controller.dueWords.isEmpty
                ? null
                : () => _openReview(context, controller.dueWords),
          );
          final summary = _TodaySummary(
            stats: stats,
            onCheckIn: stats.checkedIn
                ? null
                : () async {
                    await controller.checkIn();
                    if (!context.mounted) return;
                    await showAppMessage(
                      context,
                      title: '今日已打卡',
                      message: '记录已安全保存在本机。保持这个节奏。',
                      tone: AppMessageTone.success,
                    );
                  },
          );

          return Column(
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: hero),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: summary),
                  ],
                )
              else ...[
                hero,
                const SizedBox(height: 16),
                summary,
              ],
              const SizedBox(height: 20),
              _TodayNotes(
                notes: [
                  for (final note in controller.notes)
                    if (_isToday(note.updatedAt)) note,
                ],
                onOpenLibrary: () => onNavigate(AppDestination.notes),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openReview(BuildContext context, List<StudyWord> words) async {
    await showCupertinoModalPopup<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReviewSheet(words: List.of(words)),
    );
  }

  static String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${now.year}年${now.month}月${now.day}日 · ${weekdays[now.weekday - 1]}';
  }

  static bool _isToday(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }
}

class _TodayNotes extends StatelessWidget {
  const _TodayNotes({required this.notes, required this.onOpenLibrary});

  final List<StudyNote> notes;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final visible = notes.take(5).toList(growable: false);
    return AppGroup(
      title: '今日自动摘要',
      children: [
        if (visible.isEmpty)
          AppGroupRow(
            icon: CupertinoIcons.waveform,
            title: '等待新的学习输入',
            subtitle: 'ChatGPT、录音豆、Outlook、QQ 邮箱会自动汇总到这里',
            tint: AppPalette.purple,
            tintBackground: AppPalette.softSurface,
          )
        else ...[
          for (final note in visible)
            AppGroupRow(
              icon: _sourceIcon(note.source),
              title: note.title,
              subtitle: '${note.source} · ${_preview(note.contentChinese)}',
              tint: AppPalette.blue,
              tintBackground: AppPalette.blueSoft,
              onTap: onOpenLibrary,
            ),
          AppGroupRow(
            icon: CupertinoIcons.arrow_right,
            title: '打开 ${notes.length} 篇今日 Note',
            subtitle:
                '进入 ${AppScope.of(context).currentUser?.displayName ?? '我的'} Library 查看完整摘要',
            onTap: onOpenLibrary,
          ),
        ],
      ],
    );
  }

  static IconData _sourceIcon(String source) {
    final normalized = source.toLowerCase();
    if (normalized.contains('飞书') || normalized.contains('feishu')) {
      return CupertinoIcons.waveform;
    }
    if (normalized.contains('chatgpt')) return CupertinoIcons.chat_bubble_2;
    if (normalized.contains('outlook') || normalized.contains('qq')) {
      return CupertinoIcons.envelope;
    }
    return CupertinoIcons.doc_text;
  }

  static String _preview(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 70) return cleaned;
    return '${cleaned.substring(0, 70)}…';
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.dueCount,
    required this.newCount,
    required this.progress,
    required this.completed,
    required this.onStart,
  });

  final int dueCount;
  final int newCount;
  final int completed;
  final double progress;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final nothingDue = dueCount == 0;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 370;
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppPalette.resolve(context, AppPalette.blueSoft),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '间隔重复 · 主动回忆',
              style: TextStyle(
                color: AppPalette.resolve(context, AppPalette.blue),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          final heading = Text(
            nothingDue ? '今日复习已清空' : '$dueCount 个知识点\n等待你回忆',
            style: AppTextStyles.title,
          );
          final description = Text(
            nothingDue
                ? '新内容会按照遗忘曲线安排到最合适的日期。'
                : '先尝试从记忆中说出答案，再翻面核对。今天另有 $newCount 个新词。',
            style: AppTextStyles.body.copyWith(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
          );
          final startButton = AppPrimaryButton(
            label: nothingDue ? '已完成' : '开始复习',
            icon: nothingDue
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.play_fill,
            onPressed: onStart,
          );
          final ring = AppProgressRing(
            progress: progress,
            label: '$completed',
            size: compact ? 94 : 106,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [badge, const Spacer(), ring],
                ),
                const SizedBox(height: 12),
                heading,
                const SizedBox(height: 8),
                description,
                const SizedBox(height: 20),
                startButton,
              ],
            );
          }

          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              badge,
              const SizedBox(height: 16),
              heading,
              const SizedBox(height: 8),
              description,
              const SizedBox(height: 20),
              startButton,
            ],
          );

          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 18),
              ring,
            ],
          );
        },
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.stats, required this.onCheckIn});

  final TodayStats stats;
  final VoidCallback? onCheckIn;

  @override
  Widget build(BuildContext context) {
    return AppGroup(
      title: '今日概览',
      children: [
        AppGroupRow(
          icon: CupertinoIcons.arrow_2_circlepath,
          title: '${stats.reviewsCompleted} 次复习',
          subtitle: '已完成的主动回忆',
          tint: AppPalette.blue,
          tintBackground: AppPalette.blueSoft,
        ),
        AppGroupRow(
          icon: CupertinoIcons.clock_fill,
          title: '${stats.minutes} 分钟',
          subtitle: '今日专注时间',
          tint: AppPalette.purple,
          tintBackground: AppPalette.softSurface,
        ),
        AppGroupRow(
          icon: stats.checkedIn
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.flame_fill,
          title: stats.checkedIn ? '今天已打卡' : '完成今日打卡',
          subtitle: stats.checkedIn ? '记录仅保存在本地数据库' : '打卡后锁定今日进度',
          tint: AppPalette.orange,
          tintBackground: AppPalette.orangeSoft,
          onTap: onCheckIn,
          trailing: stats.checkedIn
              ? Icon(
                  CupertinoIcons.check_mark,
                  color: AppPalette.resolve(context, AppPalette.green),
                  size: 18,
                )
              : null,
        ),
      ],
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.words});

  final List<StudyWord> words;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _index = 0;
  bool _revealed = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.words[_index];
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
          margin: const EdgeInsets.all(12),
          child: LiquidGlassSurface(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            radius: 30,
            blur: 34,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '${_index + 1} / ${widget.words.length}',
                      style: AppTextStyles.caption,
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: CupertinoIcons.xmark,
                      semanticLabel: '退出复习',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  word.word,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  word.phonetic,
                  style: TextStyle(
                    color: AppPalette.resolve(
                      context,
                      AppPalette.secondaryText,
                    ),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _revealed
                      ? Column(
                          key: const ValueKey('answer'),
                          children: [
                            Text(
                              word.translation,
                              style: AppTextStyles.title,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              word.exampleEnglish,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              word.exampleChinese,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body.copyWith(
                                color: AppPalette.resolve(
                                  context,
                                  AppPalette.secondaryText,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '先在心里说出中文释义与例句，再查看答案。',
                          key: const ValueKey('prompt'),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: AppPalette.resolve(
                              context,
                              AppPalette.secondaryText,
                            ),
                          ),
                        ),
                ),
                const Spacer(),
                if (!_revealed)
                  AppPrimaryButton(
                    label: '显示答案',
                    icon: CupertinoIcons.eye_fill,
                    fullWidth: true,
                    onPressed: () => setState(() => _revealed = true),
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final rating in ReviewRating.values)
                        LiquidGlassSurface(
                          padding: EdgeInsets.zero,
                          radius: 19,
                          blur: 18,
                          tone: _ratingTone(rating),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            borderRadius: BorderRadius.circular(19),
                            onPressed: _saving
                                ? null
                                : () => _rate(word, rating),
                            child: Text(
                              rating.label,
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  LiquidGlassTone _ratingTone(ReviewRating rating) {
    return switch (rating) {
      ReviewRating.again => LiquidGlassTone.danger,
      ReviewRating.hard => LiquidGlassTone.neutral,
      ReviewRating.good => LiquidGlassTone.accent,
      ReviewRating.easy => LiquidGlassTone.success,
    };
  }

  Future<void> _rate(StudyWord word, ReviewRating rating) async {
    setState(() => _saving = true);
    await AppScope.of(context).reviewWord(word, rating);
    if (!mounted) return;
    if (_index + 1 >= widget.words.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _index += 1;
      _revealed = false;
      _saving = false;
    });
  }
}
