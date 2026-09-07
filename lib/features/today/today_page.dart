import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
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

    return AppPage(
      title: '主页',
      subtitle: '${user.displayName} · ${_todayLabel()}',
      child: Column(
        children: [
          AppGroup(
            title: '今日待办',
            children: [
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
}
