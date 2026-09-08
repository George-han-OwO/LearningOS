import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../notes/learning_journal_page.dart';
import '../settings/settings_page.dart';
import '../today/today_page.dart';
import '../words/word_bank_page.dart';

enum AppDestination { home, words, journal, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _selected = AppDestination.home;

  void _select(AppDestination destination) {
    setState(() => _selected = destination);
  }

  Widget _page(AppDestination destination) {
    return switch (destination) {
      AppDestination.home => TodayPage(onNavigate: _select),
      AppDestination.words => const WordBankPage(),
      AppDestination.journal => const LearningJournalPage(),
      AppDestination.settings => const SettingsPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        return desktop ? _buildDesktop(context) : _buildMobile(context);
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final showRightRail = MediaQuery.sizeOf(context).width >= 1180;
    return CupertinoPageScaffold(
      child: Row(
        children: [
          _DesktopSidebar(selected: _selected, onSelected: _select),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: AppPalette.resolve(context, AppPalette.separator),
                    width: 0.6,
                  ),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(_selected),
                  child: _page(_selected),
                ),
              ),
            ),
          ),
          if (showRightRail)
            _DesktopRightRail(
              onOpenSettings: () => _select(AppDestination.settings),
            ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final destinations = [
      AppDestination.home,
      AppDestination.words,
      AppDestination.journal,
      AppDestination.settings,
    ];
    final index = destinations.indexOf(_selected);
    final mainPages = <Widget>[
      TodayPage(onNavigate: _select),
      const WordBankPage(),
      const LearningJournalPage(),
      const SettingsPage(),
    ];

    return CupertinoPageScaffold(
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(index: index, children: mainPages),
          ),
          ColoredBox(
            color: const Color(0xFF000000),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: LiquidGlassSurface(
                key: const ValueKey('mobile-bottom-bar-surface'),
                padding: EdgeInsets.zero,
                radius: 0,
                blur: 30,
                child: CupertinoTabBar(
                  currentIndex: index,
                  backgroundColor: const Color(0x00000000),
                  activeColor: const Color(0xFFFFFFFF),
                  inactiveColor: AppPalette.resolve(
                    context,
                    AppPalette.secondaryText,
                  ),
                  border: null,
                  onTap: (next) => _select(destinations[next]),
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.calendar),
                      activeIcon: Icon(CupertinoIcons.calendar_today),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.book),
                      activeIcon: Icon(CupertinoIcons.book_fill),
                      label: 'Words',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.doc_text),
                      activeIcon: Icon(CupertinoIcons.doc_text_fill),
                      label: 'Journal',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.settings),
                      activeIcon: Icon(CupertinoIcons.settings_solid),
                      label: 'Setting',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({required this.selected, required this.onSelected});

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  static const destinations = [
    (
      destination: AppDestination.home,
      icon: CupertinoIcons.calendar,
      selectedIcon: CupertinoIcons.calendar_today,
      label: '主页',
    ),
    (
      destination: AppDestination.words,
      icon: CupertinoIcons.book,
      selectedIcon: CupertinoIcons.book_fill,
      label: '单词',
    ),
    (
      destination: AppDestination.journal,
      icon: CupertinoIcons.doc_text,
      selectedIcon: CupertinoIcons.doc_text_fill,
      label: '学习笔记',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: 248,
          decoration: BoxDecoration(
            color: const Color(0xB30B0B0E),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x2EFFFFFF), Color(0x12000000)],
            ),
            border: Border(
              right: BorderSide(
                color: AppPalette.resolve(context, AppPalette.separator),
                width: 0.6,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 17),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppPalette.resolve(context, AppPalette.blue),
                                AppPalette.resolve(context, AppPalette.purple),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            CupertinoIcons.sparkles,
                            color: Color(0xFFFFFFFF),
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'AILearningOS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final item in destinations)
                    _SidebarItem(
                      icon: selected == item.destination
                          ? item.selectedIcon
                          : item.icon,
                      label: item.label,
                      selected: selected == item.destination,
                      onPressed: () => onSelected(item.destination),
                    ),
                  const Spacer(),
                  _SidebarItem(
                    icon: selected == AppDestination.settings
                        ? CupertinoIcons.settings_solid
                        : CupertinoIcons.settings,
                    label: 'Settings',
                    selected: selected == AppDestination.settings,
                    onPressed: () => onSelected(AppDestination.settings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        minimumSize: const Size(46, 46),
        pressedOpacity: 0.68,
        borderRadius: BorderRadius.circular(11),
        color: selected ? const Color(0x26FFFFFF) : null,
        onPressed: onPressed,
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? AppPalette.resolve(context, AppPalette.blue)
                  : AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            const SizedBox(width: 11),
            Text(
              label,
              style: TextStyle(
                color: AppPalette.resolve(context, AppPalette.text),
                fontSize: 17,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopRightRail extends StatelessWidget {
  const _DesktopRightRail({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.currentUser!;
    final canvas = controller.canvasTodoState;
    final quota = controller.codexQuota;
    return Container(
      width: 320,
      color: const Color(0xFF000000),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onOpenSettings,
              child: AppCard(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    _AccountAvatar(name: user.displayName, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.sectionTitle,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _RailCard(
              title: 'AI',
              icon: CupertinoIcons.sparkles,
              trailing: controller.activeAiProviderLabel,
              child: controller.chatGptAuth.authenticated && quota.available
                  ? Column(
                      children: [
                        _RailQuota(
                          label: '短周期',
                          remaining: quota.primaryRemainingPercent,
                        ),
                        const SizedBox(height: 10),
                        _RailQuota(
                          label: '长周期',
                          remaining: quota.secondaryRemainingPercent,
                        ),
                      ],
                    )
                  : Text(
                      controller.chatGptAuth.authenticated
                          ? (quota.message ?? '点击 Settings 刷新 Codex 额度')
                          : 'DeepSeek 与 ChatGPT-Codex 可手动切换',
                      style: AppTextStyles.caption,
                    ),
            ),
            const SizedBox(height: 14),
            _RailCard(
              title: 'Canvas',
              icon: CupertinoIcons.calendar,
              trailing: canvas.connected ? '已连接' : '未连接',
              child: Text(
                canvas.connected
                    ? '${canvas.pending.length} 项待办 · ${canvas.completed.length} 项已完成'
                    : '连接后作业会进入主页信息流',
                style: AppTextStyles.caption,
              ),
            ),
            const SizedBox(height: 14),
            CupertinoButton.filled(
              borderRadius: BorderRadius.circular(22),
              onPressed: onOpenSettings,
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppPalette.resolve(context, AppPalette.blue),
            AppPalette.resolve(context, AppPalette.purple),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.title,
    required this.icon,
    required this.trailing,
    required this.child,
  });

  final String title;
  final IconData icon;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: AppPalette.resolve(context, AppPalette.blue),
            ),
            const SizedBox(width: 7),
            Text(title, style: AppTextStyles.sectionTitle),
            const Spacer(),
            Flexible(
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _RailQuota extends StatelessWidget {
  const _RailQuota({required this.label, required this.remaining});

  final String label;
  final double? remaining;

  @override
  Widget build(BuildContext context) {
    final fraction = ((remaining ?? 0) / 100).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.caption)),
            Text(
              remaining == null ? '--' : '剩余 ${remaining!.toStringAsFixed(0)}%',
              style: AppTextStyles.caption,
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 6,
            color: AppPalette.resolve(context, AppPalette.softSurface),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: ColoredBox(
                color: AppPalette.resolve(context, AppPalette.blue),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
