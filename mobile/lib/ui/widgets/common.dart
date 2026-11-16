import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// Soft colour fields behind a screen, tinted by an optional accent.
class Aurora extends StatelessWidget {
  const Aurora({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = accent?.withValues(alpha: context.isDark ? .30 : .18) ?? c.glowA;
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: c.bg)),
      Positioned(top: -160, right: -120, child: _Blob(color: a, size: 420)),
      Positioned(top: 180, left: -180, child: _Blob(color: c.glowB, size: 380)),
      Positioned.fill(child: child),
    ]);
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Shrinks slightly while pressed, then springs back.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = .96, this.haptic = true, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 260),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The primary call to action: a full-width brand-gradient pill.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onTap, this.icon, this.gradient, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Gradient? gradient;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final g = gradient ?? RankdColors.brandGradient;
    return Pressable(
      onTap: busy ? null : onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          gradient: g,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: g.colors.first.withValues(alpha: .45), blurRadius: 28, offset: const Offset(0, 12))],
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 10)],
                Text(label, style: const TextStyle(fontFamily: body, fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
      ),
    );
  }
}

/// A frosted panel for bars that float over content.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 24, this.padding = EdgeInsets.zero});

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: context.isDark ? .72 : .82),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// An item's picture, or a typographic card on the topic's gradient when it has none.
class ItemArt extends StatelessWidget {
  const ItemArt({
    super.key,
    required this.name,
    required this.accent,
    this.imageUrl,
    this.emoji,
    this.radius = 22,
    this.monogramSize = 64,
  });

  final String name;
  final Color accent;
  final String? imageUrl;
  final String? emoji;
  final double radius;
  final double monogramSize;

  String get monogram {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(w[0])).toList();
    if (words.isEmpty) return name.isEmpty ? '?' : name.substring(0, name.length.clamp(0, 2));
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(0, 2));
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: itemGradient(accent, name)),
      child: Stack(fit: StackFit.expand, children: [
        // Light from the top-right corner.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: Alignment(.9, -1), radius: 1.1, colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)]),
          ),
        ),
        if (emoji != null)
          Positioned(
            right: -monogramSize * .18,
            bottom: -monogramSize * .1,
            child: Opacity(opacity: .22, child: Text(emoji!, style: TextStyle(fontSize: monogramSize * 1.25))),
          ),
        Center(
          child: Text(
            monogram,
            style: TextStyle(
              fontFamily: display,
              fontWeight: FontWeight.w800,
              fontSize: monogramSize,
              letterSpacing: -monogramSize * .04,
              color: Colors.white.withValues(alpha: .95),
              shadows: const [Shadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
          ),
        ),
      ]),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: imageUrl == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 220),
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback, // FR-16: media never blocks play
            ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.color, this.filled = false});

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = color ?? c.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? fg.withValues(alpha: .14) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        border: filled ? null : Border.all(color: c.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
        Text(label, style: TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// A thin gradient progress bar.
class GradientProgress extends StatelessWidget {
  const GradientProgress({super.key, required this.value, this.height = 6, this.gradient});

  final double value;
  final double height;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: context.c.surface2,
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: gradient ?? RankdColors.brandGradient, borderRadius: BorderRadius.circular(height)),
                child: SizedBox(height: height),
              ),
            ),
          ),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Row(children: [
          Text(title, style: context.t.titleLarge),
          const Spacer(),
          ?trailing,
        ]),
      );
}

/// The Rankd mark: three rising bars on the brand gradient.
class RankdMark extends StatelessWidget {
  const RankdMark({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: RankdColors.brandGradient,
          borderRadius: BorderRadius.circular(size * .3),
          boxShadow: [BoxShadow(color: RankdColors.brand.withValues(alpha: .5), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: CustomPaint(painter: _BarsPainter()),
      );
}

class _BarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = s.width * .1
      ..strokeCap = StrokeCap.round;
    final base = s.height * .72;
    canvas.drawLine(Offset(s.width * .3, base), Offset(s.width * .3, s.height * .5), p);
    canvas.drawLine(Offset(s.width * .5, base), Offset(s.width * .5, s.height * .28), p);
    canvas.drawLine(Offset(s.width * .7, base), Offset(s.width * .7, s.height * .42), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
