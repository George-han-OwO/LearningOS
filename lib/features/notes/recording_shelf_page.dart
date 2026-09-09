import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../domain/models.dart';

class RecordingShelfPage extends StatefulWidget {
  const RecordingShelfPage({super.key});
  @override
  State<RecordingShelfPage> createState() => _RecordingShelfPageState();
}

class _RecordingShelfPageState extends State<RecordingShelfPage> {
  final _pages = PageController(initialPage: 100000, viewportFraction: .76);
  int _index = 100000;
  bool _refreshing = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await AppScope.of(context).refresh();
    } catch (_) {
      if (mounted) setState(() => _error = '同步失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes =
        AppScope.of(
            context,
          ).notes.where((n) => n.source.startsWith('飞书录音每日总结:')).toList()
          ..sort((a, b) => b.source.compareTo(a.source));
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF090B10),
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('录音日记'),
        trailing: _refreshing
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _refresh,
                child: const Icon(
                  CupertinoIcons.refresh,
                  semanticLabel: '同步录音日记',
                ),
              ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CupertinoColors.systemOrange),
                ),
              ),
            const SizedBox(height: 32),
            const Text(
              '每天，都值得被收藏。',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF1F3F9),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              notes.isEmpty ? '等待第一段录音' : '${notes.length} 天声音记忆 · 左右滑动翻阅',
              style: const TextStyle(fontSize: 13, color: Color(0xFF929BAD)),
            ),
            Expanded(
              child: notes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(36),
                        child: Text(
                          '飞书录音转写同步后，当天的 AI 摘要会自动收进这里。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF929BAD),
                            height: 1.8,
                          ),
                        ),
                      ),
                    )
                  : PageView.builder(
                      controller: _pages,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (context, index) {
                        final note =
                            notes[((index - 100000) % notes.length +
                                    notes.length) %
                                notes.length];
                        final date = note.source.split(':').last;
                        return Center(
                          child: AnimatedScale(
                            scale: index == _index ? 1 : .86,
                            duration: const Duration(milliseconds: 240),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _open(note),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 350,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: SweepGradient(
                                              colors: [
                                                Color(0xFFC6D2E2),
                                                Color(0xFF6A7485),
                                                Color(0xFFE7C8EC),
                                                Color(0xFFB5E1DC),
                                                Color(0xFFF4F1DF),
                                                Color(0xFF727F94),
                                                Color(0xFFC6D2E2),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0x55000000),
                                                blurRadius: 32,
                                                offset: Offset(0, 20),
                                              ),
                                            ],
                                          ),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              for (final fraction in [
                                                .94,
                                                .88,
                                                .82,
                                                .44,
                                              ])
                                                FractionallySizedBox(
                                                  widthFactor: fraction,
                                                  heightFactor: fraction,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: const Color(
                                                          0x35FFFFFF,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              const Align(
                                                alignment: Alignment(0, -.57),
                                                child: Text(
                                                  'DAILY RECORDINGS',
                                                  style: TextStyle(
                                                    color: Color(0xFF303644),
                                                    fontSize: 10,
                                                    letterSpacing: 2,
                                                  ),
                                                ),
                                              ),
                                              FractionallySizedBox(
                                                widthFactor: .18,
                                                heightFactor: .18,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF090B10,
                                                    ),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFC0C6CE,
                                                      ),
                                                      width: 6,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Align(
                                                alignment: const Alignment(
                                                  0,
                                                  .58,
                                                ),
                                                child: Text(
                                                  date,
                                                  style: const TextStyle(
                                                    color: Color(0xFF242B38),
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 1,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  Text(
                                    date,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFF1F3F9),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '点击光盘 · 打开今日总结',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF929BAD),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CupertinoButton(
                      onPressed: _index > 0
                          ? () => _pages.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            )
                          : null,
                      child: const Icon(CupertinoIcons.arrow_left),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '声音档案',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF929BAD),
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => _pages.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      ),
                      child: const Icon(CupertinoIcons.arrow_right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _open(StudyNote note) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            transitionBetweenRoutes: false,
            middle: Text(note.source.split(':').last),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title, style: AppTextStyles.title),
                  const SizedBox(height: 24),
                  SelectableText(
                    note.contentChinese,
                    style: AppTextStyles.body.copyWith(height: 1.8),
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
