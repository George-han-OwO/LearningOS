import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/canvas_todo.dart';
import '../shell/app_shell.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({required this.onNavigate, super.key});

  final ValueChanged<AppDestination> onNavigate;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  String? _expandedCourse;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final stats = controller.todayStats;
    final user = controller.currentUser!;
    final todayJournals = controller.notes
        .where((note) => _isToday(note.updatedAt))
        .length;
    final canvas = controller.canvasTodoState;

    return AppPage(
      title: '主页',
      subtitle: '${user.displayName} · ${_todayLabel()}',
      actions: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(42, 42),
          onPressed: () => widget.onNavigate(AppDestination.settings),
          child: _HomeAvatar(name: user.displayName),
        ),
      ],
      inlineMobileActions: true,
      child: Column(
        children: [
          AppGroup(
            title: '今日待办',
            trailing: AppIconButton(
              icon: CupertinoIcons.refresh,
              semanticLabel: '刷新 Canvas 待办',
              onPressed: canvas.loading ? null : controller.refreshCanvasTodos,
            ),
            children: [..._canvasCourseRows(canvas)],
          ),
          const SizedBox(height: 20),
          AppGroup(
            title: '已完成',
            children: [
              for (final item in canvas.completed.take(3))
                AppGroupRow(
                  icon: CupertinoIcons.check_mark_circled_solid,
                  title: item.title,
                  subtitle: 'Canvas · ${item.courseName} · ${item.statusLabel}',
                  tint: AppPalette.green,
                  tintBackground: AppPalette.greenSoft,
                  onTap: () => widget.onNavigate(AppDestination.settings),
                ),
              AppGroupRow(
                icon: CupertinoIcons.check_mark_circled_solid,
                title: '${stats.reviewsCompleted} 次单词复习',
                subtitle: '今天已完成的主动回忆',
                tint: AppPalette.green,
                tintBackground: AppPalette.greenSoft,
              ),
              AppGroupRow(
                icon: CupertinoIcons.doc_text_fill,
                title: '$todayJournals 篇 Learning Journal',
                subtitle: '今天已保存的学习记录',
                tint: AppPalette.blue,
                tintBackground: AppPalette.blueSoft,
                onTap: () => widget.onNavigate(AppDestination.journal),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppGroup(
            children: [
              AppGroupRow(
                icon: CupertinoIcons.settings,
                title: 'Settings',
                subtitle: '账号、DeepSeek 与 ChatGPT-Codex 切换',
                onTap: () => widget.onNavigate(AppDestination.settings),
              ),
            ],
          ),
        ],
      ),
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

  List<Widget> _canvasCourseRows(CanvasTodoState state) {
    if (state.loading && state.items.isEmpty) {
      return const [
        AppGroupRow(
          icon: CupertinoIcons.cloud_download,
          title: '正在同步 Canvas 作业',
          subtitle: '由另一台电脑上的 AILearningOS 后端读取',
          trailing: CupertinoActivityIndicator(),
        ),
      ];
    }
    if (state.error != null) {
      return [
        AppGroupRow(
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          title: 'Canvas 同步失败',
          subtitle: state.error,
          tint: AppPalette.orange,
          tintBackground: AppPalette.orangeSoft,
          onTap: () => widget.onNavigate(AppDestination.settings),
        ),
      ];
    }
    if (!state.connected) {
      return [
        AppGroupRow(
          icon: CupertinoIcons.cloud,
          title: '连接 Canvas 信息源',
          subtitle: '连接后，作业、截止时间和提交状态会进入待办',
          onTap: () => widget.onNavigate(AppDestination.settings),
        ),
      ];
    }
    final pending = state.pending;
    if (pending.isEmpty) {
      return const [
        AppGroupRow(
          icon: CupertinoIcons.check_mark_circled_solid,
          title: 'Canvas 待办已清空',
          subtitle: '当前没有未提交作业',
          tint: AppPalette.green,
          tintBackground: AppPalette.greenSoft,
        ),
      ];
    }
    final courses = <String, List<CanvasTodoItem>>{};
    for (final item in pending) {
      courses.putIfAbsent(item.courseName, () => []).add(item);
    }
    return [
      for (final entry in courses.entries)
        _CourseTodoCard(
          courseName: entry.key,
          assignments: entry.value,
          expanded: _expandedCourse == entry.key,
          onTap: () => setState(() {
            _expandedCourse = _expandedCourse == entry.key ? null : entry.key;
          }),
        ),
    ];
  }

  static String _dueLabel(DateTime? dueAt) {
    if (dueAt == null) return '无截止时间';
    final value = dueAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    if (value.isBefore(now)) return '已逾期 · ${value.month}月${value.day}日 $time';
    if (date == today) return '今天 $time';
    if (date == today.add(const Duration(days: 1))) return '明天 $time';
    return '${value.month}月${value.day}日 $time';
  }
}

class _CourseTodoCard extends StatelessWidget {
  const _CourseTodoCard({
    required this.courseName,
    required this.assignments,
    required this.expanded,
    required this.onTap,
  });

  final String courseName;
  final List<CanvasTodoItem> assignments;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overdueCount = assignments.where((item) => item.overdue).length;
    final nearestDue = assignments
        .map((item) => item.dueAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (nearest, due) =>
              nearest == null || due.isBefore(nearest) ? due : nearest,
        );
    final accent = overdueCount > 0 ? AppPalette.orange : AppPalette.blue;
    final accentSoft = overdueCount > 0
        ? AppPalette.orangeSoft
        : AppPalette.blueSoft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton(
          key: ValueKey('today-course-$courseName'),
          padding: EdgeInsets.zero,
          pressedOpacity: 0.72,
          onPressed: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 14, 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(context, accentSoft),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.book_fill,
                    size: 19,
                    color: AppPalette.resolve(context, accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        courseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppPalette.resolve(context, AppPalette.text),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overdueCount > 0
                            ? '${assignments.length} 项作业 · $overdueCount 项逾期'
                            : '${assignments.length} 项作业${nearestDue == null ? '' : ' · 最近 ${_TodayPageState._dueLabel(nearestDue)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppPalette.resolve(
                            context,
                            AppPalette.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 17,
                    color: AppPalette.resolve(
                      context,
                      AppPalette.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  children: [
                    for (final item in assignments) _AssignmentRow(item: item),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.item});

  final CanvasTodoItem item;

  @override
  Widget build(BuildContext context) {
    final tint = item.overdue ? AppPalette.orange : AppPalette.secondaryText;
    return Container(
      margin: const EdgeInsets.fromLTRB(67, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppPalette.resolve(context, AppPalette.softSurface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              item.overdue
                  ? CupertinoIcons.exclamationmark_circle_fill
                  : CupertinoIcons.circle,
              size: 16,
              color: AppPalette.resolve(context, tint),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 15,
                    color: AppPalette.resolve(context, AppPalette.text),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_TodayPageState._dueLabel(item.dueAt)} · ${item.statusLabel}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppPalette.resolve(context, tint),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAvatar extends StatelessWidget {
  const _HomeAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    return Semantics(
      label: '打开账号与设置',
      button: true,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              AppPalette.resolve(context, AppPalette.blue),
              AppPalette.resolve(context, AppPalette.purple),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
