import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class GlowBackground extends StatefulWidget {
  const GlowBackground({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant GlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) return;
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColors = isDark
        ? const [Color(0xFF080C18), Color(0xFF101629), Color(0xFF0B1020)]
        : const [Color(0xFFEFF4FF), Color(0xFFF8FAFF), Color(0xFFEAF7F4)];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: baseColors,
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _GlowPainter(
              progress: _controller.value,
              isDark: isDark,
              scheme: theme.colorScheme,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter({
    required this.progress,
    required this.isDark,
    required this.scheme,
  });

  final double progress;
  final bool isDark;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final eased = Curves.easeInOut.transform(progress);
    _paintGlow(
      canvas,
      center: Offset(size.width * (0.18 + eased * 0.04), size.height * 0.18),
      radius: size.shortestSide * 0.55,
      color: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
    );
    _paintGlow(
      canvas,
      center: Offset(size.width * 0.86, size.height * (0.16 + eased * 0.10)),
      radius: size.shortestSide * 0.42,
      color: scheme.tertiary.withValues(alpha: isDark ? 0.16 : 0.12),
    );
    _paintGlow(
      canvas,
      center: Offset(size.width * (0.58 - eased * 0.06), size.height * 0.96),
      radius: size.shortestSide * 0.48,
      color: scheme.secondary.withValues(alpha: isDark ? 0.15 : 0.11),
    );
  }

  void _paintGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(center, radius, [
        color,
        color.withValues(alpha: 0),
      ]);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.scheme != scheme;
  }
}
