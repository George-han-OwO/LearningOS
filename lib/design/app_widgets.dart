import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';

import 'app_theme.dart';

enum LiquidGlassTone { neutral, accent, danger, success }

enum AppMessageTone { info, warning, success }

class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.tone = LiquidGlassTone.neutral,
    this.blur = 24,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final LiquidGlassTone tone;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final colors = switch (tone) {
      LiquidGlassTone.neutral => [
        const Color(0x3DFFFFFF),
        const Color(0x1FFFFFFF),
        const Color(0x38000000),
      ],
      LiquidGlassTone.accent => [
        const Color(0xB2359CFF),
        const Color(0x8A0868D8),
        const Color(0x623B68FF),
      ],
      LiquidGlassTone.danger => [
        const Color(0xD45C1017),
        const Color(0xB22E070B),
        const Color(0xA0A20D1A),
      ],
      LiquidGlassTone.success => [
        const Color(0xA3236E3A),
        const Color(0x7A103D23),
        const Color(0x7420A253),
      ],
    };
    final borderColor = const Color(
      0xFFFFFFFF,
    ).withValues(alpha: highContrast ? 0.42 : 0.2);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.34),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: colors.first.withValues(alpha: 0.18),
            blurRadius: 18,
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xB30A0A0C),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 0.48, 1],
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.mobileActions,
    this.inlineMobileActions = false,
    this.padding,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final List<Widget>? mobileActions;
  final bool inlineMobileActions;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF000000),
                  Color(0xFF080A0E),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),
          Positioned(
            top: -150,
            right: -120,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppPalette.resolve(
                    context,
                    AppPalette.blue,
                  ).withValues(alpha: 0.08),
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.resolve(
                        context,
                        AppPalette.purple,
                      ).withValues(alpha: 0.09),
                      blurRadius: 120,
                      spreadRadius: 45,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding:
                      padding ??
                      EdgeInsets.symmetric(
                        horizontal: MediaQuery.sizeOf(context).width >= 850
                            ? 30
                            : 16,
                        vertical: MediaQuery.sizeOf(context).width >= 700
                            ? 22
                            : 16,
                      ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PageHeader(
                              title: title,
                              subtitle: subtitle,
                              actions: actions,
                              mobileActions: mobileActions,
                              inlineMobileActions: inlineMobileActions,
                            ),
                            const SizedBox(height: 20),
                            child,
                            const SizedBox(height: 34),
                          ],
                        ),
                      ),
                    ),
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

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.mobileActions,
    required this.inlineMobileActions,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget>? mobileActions;
  final bool inlineMobileActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.largeTitle.copyWith(
                fontSize: compact ? 30 : null,
                color: AppPalette.resolve(context, AppPalette.text),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppPalette.resolve(context, AppPalette.secondaryText),
                ),
              ),
            ],
          ],
        );

        final visibleActions = compact ? (mobileActions ?? actions) : actions;
        if (visibleActions.isEmpty) return heading;

        final actionBar = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: visibleActions,
        );

        // Long mobile titles must get the full row. This prevents action
        // buttons from squeezing a title down to a single character per line.
        if (compact && !inlineMobileActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 14), actionBar],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            actionBar,
          ],
        );
      },
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.radius = 20,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final baseColor = AppPalette.resolve(context, color ?? AppPalette.surface);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(const Color(0x12FFFFFF), baseColor),
            Color.alphaBlend(const Color(0x16000000), baseColor),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.09),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.38),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      pressedOpacity: 0.78,
      child: card,
    );
  }
}

class AppGroup extends StatelessWidget {
  const AppGroup({
    required this.children,
    this.title,
    this.trailing,
    super.key,
  });

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 15, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!, style: AppTextStyles.sectionTitle),
                  ),
                  ?trailing,
                ],
              ),
            ),
          for (var index = 0; index < children.length; index += 1) ...[
            if (index > 0 || title != null)
              Padding(
                padding: const EdgeInsets.only(left: 62),
                child: Container(
                  height: 0.6,
                  color: AppPalette.resolve(context, AppPalette.separator),
                ),
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

class AppGroupRow extends StatelessWidget {
  const AppGroupRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.tint = AppPalette.blue,
    this.tintBackground = AppPalette.blueSoft,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color tint;
  final Color tintBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppPalette.resolve(context, tintBackground),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: AppPalette.resolve(context, tint),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppPalette.resolve(
                        context,
                        AppPalette.secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.65,
      onPressed: onTap,
      child: content,
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
    this.fullWidth = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final foreground = onPressed == null
        ? AppPalette.resolve(context, AppPalette.secondaryText)
        : filled
        ? const Color(0xFFFFFFFF)
        : AppPalette.resolve(context, AppPalette.blue);
    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 7),
        ],
        Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    final button = LiquidGlassSurface(
      padding: EdgeInsets.zero,
      radius: 22,
      tone: filled ? LiquidGlassTone.accent : LiquidGlassTone.neutral,
      blur: 20,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
        minimumSize: const Size(44, 44),
        borderRadius: BorderRadius.circular(22),
        pressedOpacity: 0.72,
        onPressed: onPressed,
        child: child,
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: LiquidGlassSurface(
        padding: EdgeInsets.zero,
        radius: 21,
        blur: 20,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(42, 42),
          borderRadius: BorderRadius.circular(21),
          onPressed: onPressed,
          child: Icon(
            icon,
            size: 18,
            color: AppPalette.resolve(context, AppPalette.text),
          ),
        ),
      ),
    );
  }
}

class AppProgressRing extends StatelessWidget {
  const AppProgressRing({
    required this.progress,
    required this.label,
    this.size = 112,
    super.key,
  });

  final double progress;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ProgressRingPainter(
          progress: progress.clamp(0, 1),
          track: AppPalette.resolve(context, AppPalette.softSurface),
          fill: AppPalette.resolve(context, AppPalette.blue),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: AppPalette.resolve(context, AppPalette.text),
              fontSize: size * 0.22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.track != track ||
        oldDelegate.fill != fill;
  }
}

Future<void> showAppMessage(
  BuildContext context, {
  required String title,
  required String message,
  AppMessageTone tone = AppMessageTone.info,
}) {
  final glassTone = switch (tone) {
    AppMessageTone.info => LiquidGlassTone.neutral,
    AppMessageTone.warning => LiquidGlassTone.danger,
    AppMessageTone.success => LiquidGlassTone.success,
  };
  final icon = switch (tone) {
    AppMessageTone.info => CupertinoIcons.info_circle_fill,
    AppMessageTone.warning => CupertinoIcons.exclamationmark_triangle_fill,
    AppMessageTone.success => CupertinoIcons.check_mark_circled_solid,
  };

  return showCupertinoModalPopup<void>(
    context: context,
    barrierColor: const Color(0xB8000000),
    builder: (popupContext) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: LiquidGlassSurface(
              tone: glassTone,
              radius: 30,
              blur: 34,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.22),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: const Color(0xFFFFFFFF), size: 24),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.title.copyWith(
                      color: const Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: const Color(0xE6FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: LiquidGlassSurface(
                      padding: EdgeInsets.zero,
                      radius: 22,
                      tone: glassTone,
                      blur: 18,
                      child: CupertinoButton(
                        borderRadius: BorderRadius.circular(22),
                        onPressed: () => Navigator.of(popupContext).pop(),
                        child: const Text(
                          '好',
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<bool> showAppConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final tone = destructive ? LiquidGlassTone.danger : LiquidGlassTone.accent;
  return await showCupertinoModalPopup<bool>(
        context: context,
        barrierColor: const Color(0xB8000000),
        builder: (popupContext) => SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: LiquidGlassSurface(
                  tone: tone,
                  radius: 30,
                  blur: 34,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        destructive
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.question_circle_fill,
                        color: const Color(0xFFFFFFFF),
                        size: 34,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.title.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: const Color(0xE6FFFFFF),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: LiquidGlassSurface(
                              padding: EdgeInsets.zero,
                              radius: 22,
                              child: CupertinoButton(
                                borderRadius: BorderRadius.circular(22),
                                onPressed: () =>
                                    Navigator.of(popupContext).pop(false),
                                child: Text(
                                  cancelLabel,
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LiquidGlassSurface(
                              padding: EdgeInsets.zero,
                              radius: 22,
                              tone: tone,
                              child: CupertinoButton(
                                borderRadius: BorderRadius.circular(22),
                                onPressed: () =>
                                    Navigator.of(popupContext).pop(true),
                                child: Text(
                                  confirmLabel,
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontWeight: FontWeight.w700,
                                  ),
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
          ),
        ),
      ) ??
      false;
}
