import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/canvas_todo.dart';
import '../shell/app_shell.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({required this.onNavigate, super.key});

  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final stats = controller.todayStats;
    final user = controller.currentUser!;
    final todayJournals = controller.notes
        .where((note) => _isToday(note.updatedAt))
        .length;
    final dueWords = stats.dueWords;
    final canvas = controller.canvasTodoState;

    return AppPage(
      title: '主页',
      subtitle: '${user.displayName} · ${_todayLabel()}',
      actions: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(42, 42),
          onPressed: () => onNavigate(AppDestination.settings),
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
            children: [
              ..._canvasPendingRows(canvas),
              AppGroupRow(
                icon: dueWords == 0
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.book_fill,
                title: dueWords == 0 ? '单词复习已完成' : '复习 $dueWords 个到期单词',
                subtitle: dueWords == 0 ? '今天没有待复习单词' : '进入单词库开始复习',
                tint: dueWords == 0 ? AppPalette.green : AppPalette.blue,
                tintBackground: dueWords == 0
                    ? AppPalette.greenSoft
                    : AppPalette.blueSoft,
                onTap: () => onNavigate(AppDestination.words),
              ),
              AppGroupRow(
                icon: CupertinoIcons.pencil_outline,
                title: todayJournals == 0 ? '写今日 Learning Journal' : '继续记录今日学习',
                subtitle: todayJournals == 0
                    ? '按统一模板记录目标、过程与反思'
                    : '今天已有 $todayJournals 篇学习笔记',
                tint: AppPalette.purple,
                tintBackground: AppPalette.softSurface,
                onTap: () => onNavigate(AppDestination.journal),
              ),
            ],
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
                  onTap: () => onNavigate(AppDestination.settings),
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
                onTap: () => onNavigate(AppDestination.journal),
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
                onTap: () => onNavigate(AppDestination.settings),
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

  List<Widget> _canvasPendingRows(CanvasTodoState state) {
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
          onTap: () => onNavigate(AppDestination.settings),
        ),
      ];
    }
    if (!state.connected) {
      return [
        AppGroupRow(
          icon: CupertinoIcons.cloud,
          title: '连接 Canvas 信息源',
          subtitle: '连接后，作业、截止时间和提交状态会进入待办',
          onTap: () => onNavigate(AppDestination.settings),
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
    return [
      for (final item in pending.take(5))
        AppGroupRow(
          icon: item.overdue
              ? CupertinoIcons.exclamationmark_triangle_fill
              : CupertinoIcons.calendar,
          title: item.title,
          subtitle:
              'Canvas · ${item.courseName} · ${_dueLabel(item.dueAt)} · ${item.statusLabel}',
          tint: item.overdue ? AppPalette.orange : AppPalette.blue,
          tintBackground: item.overdue
              ? AppPalette.orangeSoft
              : AppPalette.blueSoft,
          onTap: () => onNavigate(AppDestination.settings),
        ),
      if (pending.length > 5)
        AppGroupRow(
          icon: CupertinoIcons.ellipsis_circle,
          title: '还有 ${pending.length - 5} 项 Canvas 待办',
          subtitle: '进入 Settings 查看 Canvas 信息源',
          onTap: () => onNavigate(AppDestination.settings),
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
