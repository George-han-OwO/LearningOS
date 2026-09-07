import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/app_controller.dart';
import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';
import '../../domain/security_policy.dart';

class WordBankPage extends StatefulWidget {
  const WordBankPage({super.key});

  @override
  State<WordBankPage> createState() => _WordBankPageState();
}

class _WordBankPageState extends State<WordBankPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final words = controller.words
        .where((word) {
          final query = _query.trim().toLowerCase();
          if (query.isEmpty) return true;
          return word.word.toLowerCase().contains(query) ||
              word.translation.contains(query);
        })
        .toList(growable: false);

    return AppPage(
      title: 'Word Bank',
      subtitle:
          '${controller.words.length} 个词 · ${controller.dueWords.length} 个待复习',
      actions: [
        AppPrimaryButton(
          label: '手动导入',
          icon: CupertinoIcons.add,
          onPressed: controller.busy
              ? null
              : () => _showImportDialog(context, aiAnalysis: false),
        ),
        AppPrimaryButton(
          label: 'AI 导入',
          icon: CupertinoIcons.sparkles,
          onPressed: controller.busy
              ? null
              : () => _showImportDialog(context, aiAnalysis: true),
        ),
      ],
      inlineMobileActions: true,
      child: Column(
        children: [
          CupertinoSearchTextField(
            placeholder: '搜索英文或中文',
            backgroundColor: AppPalette.resolve(
              context,
              AppPalette.raisedSurface,
            ),
            borderRadius: BorderRadius.circular(14),
            style: TextStyle(
              color: AppPalette.resolve(context, AppPalette.text),
              fontSize: 15,
            ),
            placeholderStyle: TextStyle(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
              fontSize: 15,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          if (controller.pendingAiWordCount > 0) ...[
            _TranslationNotice(
              count: controller.pendingAiWordCount,
              state: controller.pendingWordEnrichmentState,
            ),
            const SizedBox(height: 16),
          ] else if (controller.aiReady) ...[
            _AiConnectionNotice(
              provider: controller.activeAiProviderLabel,
              model: controller.activeAiModel,
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              if (words.isEmpty) {
                return _EmptyWordBank(hasQuery: _query.isNotEmpty);
              }
              return constraints.maxWidth >= 680
                  ? _WordTable(words: words)
                  : _WordCards(words: words);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(
    BuildContext pageContext, {
    required bool aiAnalysis,
  }) async {
    final input = TextEditingController();
    await showCupertinoModalPopup<void>(
      context: pageContext,
      barrierColor: const Color(0xA8000000),
      builder: (dialogContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight:
                    MediaQuery.of(dialogContext).size.height -
                    MediaQuery.of(dialogContext).viewInsets.bottom -
                    24,
              ),
              margin: const EdgeInsets.all(12),
              child: LiquidGlassSurface(
                radius: 30,
                blur: 34,
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              aiAnalysis ? 'AI 导入与分析' : '手动导入单词',
                              style: AppTextStyles.title,
                            ),
                          ),
                          AppIconButton(
                            icon: CupertinoIcons.xmark,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        aiAnalysis
                            ? '粘贴学习材料或 AI 对话。当前选中的 AI 会提取单词、分析总结，并生成一篇 Learning Journal。'
                            : '直接粘贴英文单词、段落或每行一个词。系统会提取并去重。',
                        style: AppTextStyles.body.copyWith(
                          color: AppPalette.resolve(
                            dialogContext,
                            AppPalette.secondaryText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      CupertinoTextField(
                        key: const ValueKey('word-import-input'),
                        controller: input,
                        minLines: 7,
                        maxLines: 10,
                        placeholder: aiAnalysis
                            ? '粘贴课文、学习资料或 AI 对话…'
                            : 'abandon\nability\nacademic...',
                        padding: const EdgeInsets.all(14),
                        textInputAction: TextInputAction.newline,
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFFFFFFFF,
                            ).withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppPrimaryButton(
                        key: const ValueKey('word-import-submit'),
                        label: aiAnalysis ? 'AI 分析并导入' : '导入单词',
                        icon: aiAnalysis
                            ? CupertinoIcons.wand_stars
                            : CupertinoIcons.add_circled_solid,
                        fullWidth: true,
                        onPressed: () {
                          if (input.text.length >
                              SecurityPolicy.maxWordBankCharacters) {
                            unawaited(
                              showAppMessage(
                                pageContext,
                                title: '内容过大',
                                message: '为避免一次性输入耗尽内存，单次最多导入 100,000 个字符。',
                                tone: AppMessageTone.warning,
                              ),
                            );
                            return;
                          }
                          final rawText = input.text;
                          if (rawText.trim().isEmpty) {
                            unawaited(
                              showAppMessage(
                                pageContext,
                                title: '还没有内容',
                                message: aiAnalysis
                                    ? '请先粘贴学习材料或 AI 对话。'
                                    : '请先粘贴英文单词或一段英文文本。',
                                tone: AppMessageTone.info,
                              ),
                            );
                            return;
                          }
                          final controller = AppScope.of(pageContext);
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop();
                          if (aiAnalysis) {
                            unawaited(
                              _aiImportInBackground(
                                pageContext: pageContext,
                                controller: controller,
                                rawText: rawText,
                              ),
                            );
                          } else {
                            _showQueuedConfirmation(pageContext);
                            unawaited(
                              _importInBackground(
                                pageContext: pageContext,
                                controller: controller,
                                rawText: rawText,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    input.dispose();
  }

  Future<void> _aiImportInBackground({
    required BuildContext pageContext,
    required AppController controller,
    required String rawText,
  }) async {
    try {
      final result = await controller.importConversation(rawText);
      if (!pageContext.mounted) return;
      await showAppMessage(
        pageContext,
        title: 'AI 导入完成',
        message:
            '已生成「${result.title}」Learning Journal，并新增 ${result.insertedWords} 个单词${result.warning == null ? '。' : '。${result.warning}'}',
        tone: result.warning == null
            ? AppMessageTone.success
            : AppMessageTone.warning,
      );
    } catch (error) {
      if (!pageContext.mounted) return;
      await showAppMessage(
        pageContext,
        title: 'AI 导入失败',
        message: '$error',
        tone: AppMessageTone.warning,
      );
    }
  }

  Future<void> _importInBackground({
    required BuildContext pageContext,
    required AppController controller,
    required String rawText,
  }) async {
    try {
      await controller.importWords(rawText);
    } catch (error) {
      if (!pageContext.mounted) return;
      await showAppMessage(
        pageContext,
        title: '后台导入失败',
        message: '$error',
        tone: AppMessageTone.warning,
      );
    }
  }

  void _showQueuedConfirmation(BuildContext context) {
    unawaited(SystemSound.play(SystemSoundType.click));
    unawaited(HapticFeedback.mediumImpact());
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ImportQueuedOverlay(onFinished: entry.remove),
    );
    overlay.insert(entry);
  }
}

class _ImportQueuedOverlay extends StatefulWidget {
  const _ImportQueuedOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_ImportQueuedOverlay> createState() => _ImportQueuedOverlayState();
}

class _ImportQueuedOverlayState extends State<_ImportQueuedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _cardScale;
  late final Animation<double> _opacity;
  late final Animation<double> _circleProgress;
  late final Animation<double> _ringProgress;
  late final Animation<double> _checkProgress;
  late final Animation<double> _textOpacity;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    // This follows the Apple Pay completion rhythm: a soft card entrance,
    // springing green completion mark, expanding ring, drawn checkmark, then
    // the completion copy fades in before the overlay dismisses.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _cardScale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _circleProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.48, curve: Curves.easeOutBack),
      reverseCurve: const Interval(0.52, 1, curve: Curves.easeIn),
    );
    _ringProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.72, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.3, 1, curve: Curves.easeIn),
    );
    _checkProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.42, 0.73, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.36, 1, curve: Curves.easeIn),
    );
    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.62, 0.92, curve: Curves.easeOut),
      reverseCurve: const Interval(0.28, 1, curve: Curves.easeIn),
    );
    unawaited(_controller.forward());
    _dismissTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: const ColoredBox(color: Color(0x66000000)),
          ),
          Center(
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _cardScale,
                child: Semantics(
                  liveRegion: true,
                  label: 'Success, Ready to queue',
                  child: LiquidGlassSurface(
                    radius: 28,
                    blur: 34,
                    tone: LiquidGlassTone.neutral,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 17,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 280,
                        maxWidth: 360,
                      ),
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Transform.scale(
                                scale: _circleProgress.value,
                                child: CustomPaint(
                                  size: const Size.square(82),
                                  painter: _ApplePayCompletionPainter(
                                    ringProgress: _ringProgress.value,
                                    checkProgress: _checkProgress.value,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 17),
                              Expanded(
                                child: Opacity(
                                  opacity: _textOpacity.value,
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Success',
                                        style: TextStyle(
                                          color: Color(0xFF1C1C1E),
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Ready to queue',
                                        style: TextStyle(
                                          color: Color(0xFF636366),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplePayCompletionPainter extends CustomPainter {
  const _ApplePayCompletionPainter({
    required this.ringProgress,
    required this.checkProgress,
  });

  final double ringProgress;
  final double checkProgress;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final center = size.center(ui.Offset.zero);
    final baseRadius = size.shortestSide * 0.34;
    final ringRadius = baseRadius + size.shortestSide * 0.15 * ringProgress;

    final circlePaint = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(size.width * 0.18, size.height * 0.08),
        ui.Offset(size.width * 0.82, size.height * 0.92),
        const [Color(0xFF7DE35E), Color(0xFF2DAA4A)],
      );
    canvas.drawCircle(center, baseRadius, circlePaint);

    if (ringProgress > 0) {
      final ringPaint = ui.Paint()
        ..color = const Color(
          0xFF7DE35E,
        ).withValues(alpha: 0.72 * (1 - ringProgress))
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    final checkPath = ui.Path()
      ..moveTo(center.dx - baseRadius * 0.45, center.dy)
      ..lineTo(center.dx - baseRadius * 0.08, center.dy + baseRadius * 0.36)
      ..lineTo(center.dx + baseRadius * 0.52, center.dy - baseRadius * 0.34);
    final metrics = checkPath.computeMetrics().first;
    final checkPaint = ui.Paint()
      ..color = CupertinoColors.white
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeWidth = 5;
    canvas.drawPath(
      metrics.extractPath(0, metrics.length * checkProgress),
      checkPaint,
    );
  }

  @override
  bool shouldRepaint(_ApplePayCompletionPainter oldDelegate) =>
      oldDelegate.ringProgress != ringProgress ||
      oldDelegate.checkProgress != checkProgress;
}

class _TranslationNotice extends StatelessWidget {
  const _TranslationNotice({required this.count, required this.state});

  final int count;
  final PendingWordEnrichmentState state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppPalette.orangeSoft,
      child: Row(
        children: [
          Icon(
            CupertinoIcons.wand_stars,
            color: AppPalette.resolve(context, AppPalette.orange),
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.waitingForApiKey
                  ? '$count 个词正在等待 AI。服务器会在有待补全字段时每 30 秒检查；当前所选 AI 来源连接后会自动补齐，无需重新导入。'
                  : state.retrying
                  ? '$count 个词仍在后台队列。本轮连接未成功，服务器会在 30 秒后自动重试。'
                  : state.working
                  ? '正在检查 $count 个待补全词条，处理在服务器后台继续。'
                  : '$count 个词已进入后台队列。服务器每 30 秒自动补齐翻译、音标、词性与双语例句，完成后自动停止。',
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiConnectionNotice extends StatelessWidget {
  const _AiConnectionNotice({required this.provider, required this.model});

  final String provider;
  final String model;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppPalette.greenSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.cloud_fill,
            color: AppPalette.resolve(context, AppPalette.green),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '联网 AI 已开启 · $provider · $model · 导入新词时会自动补齐音标、词性、释义和例句。',
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _WordTable extends StatelessWidget {
  const _WordTable({required this.words});

  final List<StudyWord> words;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _TableRow(
            word: '单词',
            part: '词性',
            translation: '中文释义',
            mastery: '掌握度',
            header: true,
          ),
          for (final word in words)
            _TableRow(
              word: word.word,
              part: word.partOfSpeech,
              translation: word.translation,
              mastery: '${word.mastery}%',
              onTap: () => _showWordDetail(context, word),
            ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.word,
    required this.part,
    required this.translation,
    required this.mastery,
    this.header = false,
    this.onTap,
  });

  final String word;
  final String part;
  final String translation;
  final String mastery;
  final bool header;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = header
        ? AppTextStyles.caption.copyWith(
            color: AppPalette.resolve(context, AppPalette.secondaryText),
            fontWeight: FontWeight.w600,
          )
        : const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: header
            ? AppPalette.resolve(context, AppPalette.softSurface)
            : null,
        border: Border(
          bottom: BorderSide(
            color: AppPalette.resolve(context, AppPalette.separator),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(word, style: textStyle)),
          Expanded(
            flex: 2,
            child: Text(
              part,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              translation,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(mastery, style: textStyle, textAlign: TextAlign.right),
          ),
          if (!header) ...[
            const SizedBox(width: 10),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 15,
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
          ] else
            const SizedBox(width: 25),
        ],
      ),
    );
    if (onTap == null) return row;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.7,
      onPressed: onTap,
      child: row,
    );
  }
}

class _WordCards extends StatelessWidget {
  const _WordCards({required this.words});

  final List<StudyWord> words;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final word in words) ...[
          AppCard(
            onTap: () => _showWordDetail(context, word),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              word.word,
                              style: AppTextStyles.sectionTitle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            word.partOfSpeech,
                            style: AppTextStyles.caption.copyWith(
                              color: AppPalette.resolve(
                                context,
                                AppPalette.secondaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(word.translation, style: AppTextStyles.body),
                      const SizedBox(height: 10),
                      _MasteryBar(value: word.mastery / 100),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${word.mastery}%',
                  style: TextStyle(
                    color: AppPalette.resolve(context, AppPalette.blue),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MasteryBar extends StatelessWidget {
  const _MasteryBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppPalette.resolve(context, AppPalette.softSurface),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1),
              alignment: Alignment.centerLeft,
              child: ColoredBox(
                color: AppPalette.resolve(context, AppPalette.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWordBank extends StatelessWidget {
  const _EmptyWordBank({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            Icon(
              CupertinoIcons.book,
              size: 34,
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            const SizedBox(height: 10),
            Text(
              hasQuery ? '没有匹配的单词' : '词库还是空的',
              style: AppTextStyles.sectionTitle,
            ),
            const SizedBox(height: 5),
            Text(
              hasQuery ? '换一个英文或中文关键词试试。' : '点击右上角“导入”，粘贴你的英文词表。',
              style: AppTextStyles.body.copyWith(
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showWordDetail(BuildContext context, StudyWord word) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.all(12),
          child: LiquidGlassSurface(
            radius: 30,
            blur: 34,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            word.word,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${word.phonetic}  ·  ${word.partOfSpeech}',
                            style: TextStyle(
                              color: AppPalette.resolve(
                                context,
                                AppPalette.secondaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: CupertinoIcons.xmark,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(word.translation, style: AppTextStyles.title),
                const SizedBox(height: 18),
                Text(word.exampleEnglish, style: AppTextStyles.body),
                const SizedBox(height: 4),
                Text(
                  word.exampleChinese,
                  style: AppTextStyles.body.copyWith(
                    color: AppPalette.resolve(
                      context,
                      AppPalette.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: _MasteryBar(value: word.mastery / 100)),
                    const SizedBox(width: 12),
                    Text('掌握度 ${word.mastery}%', style: AppTextStyles.caption),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  word.isDue
                      ? '现在需要复习'
                      : '下次：${word.dueAt.month}月${word.dueAt.day}日',
                  style: AppTextStyles.caption.copyWith(
                    color: AppPalette.resolve(
                      context,
                      word.isDue ? AppPalette.orange : AppPalette.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
