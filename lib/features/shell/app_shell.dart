import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../capture/capture_page.dart';
import '../course/course_page.dart';
import '../notes/notes_page.dart';
import '../profile/profile_page.dart';
import '../safety/safety_page.dart';
import '../today/today_page.dart';
import '../words/word_bank_page.dart';

enum AppDestination { today, course, capture, words, notes, safety, profile }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _selected = AppDestination.today;

  void _select(AppDestination destination) {
    setState(() => _selected = destination);
  }

  Widget _page(AppDestination destination) {
    return switch (destination) {
      AppDestination.today => TodayPage(onNavigate: _select),
      AppDestination.course => const CoursePage(),
      AppDestination.capture => const CapturePage(),
      AppDestination.words => const WordBankPage(),
      AppDestination.notes => const NotesPage(),
      AppDestination.safety => const SafetyPage(),
      AppDestination.profile => ProfilePage(
        onOpenSafety: () => _select(AppDestination.safety),
      ),
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
    return CupertinoPageScaffold(
      child: Row(
        children: [
          _DesktopSidebar(
            selected: _selected,
            onSelected: _select,
            userName: AppScope.of(context).currentUser?.displayName ?? '我的',
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(_selected),
                child: _page(_selected),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final destinations = [
      AppDestination.today,
      AppDestination.words,
      AppDestination.notes,
    ];
    final mobileSelected = destinations.contains(_selected)
        ? _selected
        : AppDestination.today;
    final index = destinations.indexOf(mobileSelected);
    final mainPages = <Widget>[
      TodayPage(onNavigate: _select),
      const WordBankPage(),
      const NotesPage(),
    ];

    return CupertinoPageScaffold(
      child: Column(
        children: [
          Expanded(
            child: _selected == AppDestination.profile
                ? ProfilePage(
                    onOpenSafety: () => _select(AppDestination.safety),
                  )
                : _selected == AppDestination.safety
                ? SafetyPage(
                    showBackButton: true,
                    onBack: () => _select(AppDestination.profile),
                  )
                : IndexedStack(index: index, children: mainPages),
          ),
          ColoredBox(
            color: const Color(0xFF000000),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: LiquidGlassSurface(
                padding: EdgeInsets.zero,
                radius: 30,
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
                      label: '今日',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.book),
                      activeIcon: Icon(CupertinoIcons.book_fill),
                      label: 'Word Bank',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.doc_text),
                      activeIcon: Icon(CupertinoIcons.doc_text_fill),
                      label: 'Library',
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
  const _DesktopSidebar({
    required this.selected,
    required this.onSelected,
    required this.userName,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final String userName;

  static const destinations = [
    (
      destination: AppDestination.today,
      icon: CupertinoIcons.calendar,
      selectedIcon: CupertinoIcons.calendar_today,
      label: '今日',
    ),
    (
      destination: AppDestination.words,
      icon: CupertinoIcons.book,
      selectedIcon: CupertinoIcons.book_fill,
      label: 'Word Bank',
    ),
    (
      destination: AppDestination.notes,
      icon: CupertinoIcons.doc_text,
      selectedIcon: CupertinoIcons.doc_text_fill,
      label: '双语笔记',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: 224,
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
                        const Text(
                          'AILearningOS',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
                      label: item.destination == AppDestination.notes
                          ? '$userName Library'
                          : item.label,
                      selected: selected == item.destination,
                      onPressed: () => onSelected(item.destination),
                    ),
                  const Spacer(),
                  _SidebarItem(
                    icon: selected == AppDestination.profile
                        ? CupertinoIcons.person_fill
                        : CupertinoIcons.person,
                    label: '我的与设置',
                    selected: selected == AppDestination.profile,
                    onPressed: () => onSelected(AppDestination.profile),
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        minimumSize: const Size(42, 42),
        pressedOpacity: 0.68,
        borderRadius: BorderRadius.circular(11),
        color: selected ? const Color(0x26FFFFFF) : null,
        onPressed: onPressed,
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? AppPalette.resolve(context, AppPalette.blue)
                  : AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            const SizedBox(width: 11),
            Text(
              label,
              style: TextStyle(
                color: AppPalette.resolve(context, AppPalette.text),
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
