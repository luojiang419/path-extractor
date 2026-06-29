import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../theme/app_theme.dart';

class DropZone extends StatefulWidget {
  final Widget child;
  final void Function(List<String> paths) onFilesDropped;

  const DropZone({
    super.key,
    required this.child,
    required this.onFilesDropped,
  });

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _isDraggingOver = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingOver = true),
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (details) {
        setState(() => _isDraggingOver = false);
        final paths = details.files.map((f) => f.path).toList();
        widget.onFilesDropped(paths);
      },
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          border: Border.all(
            color: _isDraggingOver
                ? colorScheme.primary.withValues(alpha: 0.72)
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: _isDraggingOver
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isDraggingOver ? 1 : 0,
                  duration: AppMotion.fast,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.24,
                      ),
                    ),
                    child: Center(
                      child: AnimatedScale(
                        scale: _isDraggingOver ? 1 : 0.96,
                        duration: AppMotion.normal,
                        curve: AppMotion.standard,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.24,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_upload_outlined,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '松开以添加',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(color: colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
