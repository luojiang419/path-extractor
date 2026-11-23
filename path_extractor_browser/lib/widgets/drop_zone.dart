import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

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
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: Border.all(
            color: _isDraggingOver ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
