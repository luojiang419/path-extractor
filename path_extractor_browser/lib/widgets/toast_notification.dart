import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

class ToastOverlay extends ConsumerWidget {
  final Widget child;

  const ToastOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toastState = ref.watch(toastProvider);

    return Stack(
      children: [
        child,
        if (toastState.isVisible && toastState.message != null)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: _ToastWidget(
                key: ValueKey(toastState.message!.createdAt),
                message: toastState.message!.text,
                isError: toastState.message!.isError,
                onDismiss: () => ref.read(toastProvider.notifier).dismiss(),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _ToastWidget({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Trigger animation on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = widget.isError
        ? colorScheme.errorContainer
        : colorScheme.primaryContainer;
    final textColor = widget.isError
        ? colorScheme.onErrorContainer
        : colorScheme.onPrimaryContainer;

    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 1),
      duration: AppMotion.normal,
      curve: AppMotion.standard,
      child: AnimatedScale(
        scale: _visible ? 1 : 0.96,
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: AppMotion.fast,
          child: GlassPanel(
            blur: 16,
            tint: backgroundColor.withValues(alpha: 0.78),
            borderColor: textColor.withValues(alpha: 0.16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: BorderRadius.circular(16),
            shadows: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: textColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
