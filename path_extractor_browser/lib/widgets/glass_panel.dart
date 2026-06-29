import 'dart:ui';

import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blur = 18,
    this.tint,
    this.borderColor,
    this.shadows,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadiusGeometry borderRadius;
  final double blur;
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final resolvedRadius = borderRadius.resolve(Directionality.of(context));
    final panelTint =
        tint ??
        (isDark
            ? const Color(0xFF12192C).withValues(alpha: 0.70)
            : Colors.white.withValues(alpha: 0.66));
    final highlightTint = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white.withValues(alpha: 0.26);

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: resolvedRadius,
          boxShadow:
              shadows ??
              [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
        ),
        child: ClipRRect(
          borderRadius: resolvedRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: panelTint,
                borderRadius: resolvedRadius,
                border: Border.all(
                  color:
                      borderColor ??
                      (isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : scheme.outlineVariant.withValues(alpha: 0.48)),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    highlightTint,
                    panelTint,
                    scheme.primary.withValues(alpha: isDark ? 0.050 : 0.035),
                  ],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
