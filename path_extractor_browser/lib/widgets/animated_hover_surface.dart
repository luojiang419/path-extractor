import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

typedef AnimatedHoverBuilder =
    Widget Function(BuildContext context, bool isHovered);

class AnimatedHoverSurface extends StatefulWidget {
  const AnimatedHoverSurface({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapUp,
    this.isHighlighted = false,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.hoverColor,
    this.highlightColor,
    this.liftOnHover = true,
  });

  final AnimatedHoverBuilder builder;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final bool isHighlighted;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? hoverColor;
  final Color? highlightColor;
  final bool liftOnHover;

  @override
  State<AnimatedHoverSurface> createState() => _AnimatedHoverSurfaceState();
}

class _AnimatedHoverSurfaceState extends State<AnimatedHoverSurface> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hoverColor =
        widget.hoverColor ??
        scheme.primaryContainer.withValues(alpha: isDark ? 0.24 : 0.42);
    final highlightColor =
        widget.highlightColor ??
        scheme.primaryContainer.withValues(alpha: isDark ? 0.38 : 0.68);
    final activeColor = widget.isHighlighted
        ? highlightColor
        : (_isHovered ? hoverColor : Colors.transparent);
    final shadowColor = scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: AnimatedScale(
          scale: widget.liftOnHover && _isHovered ? 1.012 : 1,
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.standard,
            decoration: BoxDecoration(
              color: activeColor,
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _isHovered || widget.isHighlighted
                    ? scheme.primary.withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
              boxShadow: _isHovered || widget.isHighlighted
                  ? [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: widget.borderRadius,
                child: Padding(
                  padding: widget.padding,
                  child: widget.builder(context, _isHovered),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
