import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import 'media_thumbnail.dart';

class FileListItem extends StatefulWidget {
  const FileListItem({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onCopyPath,
    this.onDelete,
    this.isHighlighted = false,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onCopyPath;
  final VoidCallback? onDelete;
  final bool isHighlighted;

  @override
  State<FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<FileListItem> {
  bool _isHovered = false;

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 8),
              const Text('复制路径'),
            ],
          ),
        ),
        if (widget.entry.isDirectory)
          PopupMenuItem(
            value: 'open',
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 16),
                const SizedBox(width: 8),
                const Text('打开文件夹'),
              ],
            ),
          ),
        if (widget.onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline, size: 16),
                const SizedBox(width: 8),
                const Text('从列表移除'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'copy') widget.onCopyPath();
      if (value == 'open') widget.onTap();
      if (value == 'delete') widget.onDelete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            color: widget.isHighlighted
                ? colorScheme.primaryContainer
                : _isHovered
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            padding: const EdgeInsets.only(
              left: 16,
              right: 4,
              top: 6,
              bottom: 6,
            ),
            child: Row(
              children: [
                _LeadingEntryVisual(entry: widget.entry),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.entry.path,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: '复制路径',
                        child: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: widget.onCopyPath,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      if (widget.onDelete != null)
                        Tooltip(
                          message: '移除',
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: widget.onDelete,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
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

class _LeadingEntryVisual extends StatelessWidget {
  const _LeadingEntryVisual({required this.entry});

  final FileEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = fileEntryIconData(entry.type);

    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: isMediaFileEntry(entry)
            ? MediaThumbnail(
                entry: entry,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(8),
                fallbackIcon: icon,
                fallbackColor: color,
              )
            : fileEntryIcon(entry.type),
      ),
    );
  }
}

Widget fileEntryIcon(FileEntryType type) {
  final (icon, color) = fileEntryIconData(type);
  return Icon(icon, color: color, size: 24);
}

(IconData, Color) fileEntryIconData(FileEntryType type) {
  switch (type) {
    case FileEntryType.directory:
      return (Icons.folder, Colors.amber);
    case FileEntryType.image:
      return (Icons.image, Colors.blue);
    case FileEntryType.video:
      return (Icons.video_file, Colors.purple);
    case FileEntryType.audio:
      return (Icons.audio_file, Colors.green);
    case FileEntryType.code:
      return (Icons.code, Colors.teal);
    case FileEntryType.document:
      return (Icons.description, Colors.orange);
    case FileEntryType.archive:
      return (Icons.archive, Colors.brown);
    case FileEntryType.other:
      return (Icons.insert_drive_file, Colors.grey);
  }
}
