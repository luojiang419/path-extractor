import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_entry.dart';
import '../services/thumbnail_service.dart';

class MediaThumbnail extends ConsumerStatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.entry,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.fallbackIconSize = 24,
  });

  final FileEntry entry;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  @override
  ConsumerState<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends ConsumerState<MediaThumbnail> {
  late Future<ThumbnailFile?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.entry.type != widget.entry.type) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Future<ThumbnailFile?> _loadThumbnail() {
    return ref.read(thumbnailServiceProvider).getThumbnail(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          ),
          child: FutureBuilder<ThumbnailFile?>(
            future: _thumbnailFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: SizedBox(
                    width: widget.fallbackIconSize,
                    height: widget.fallbackIconSize,
                    child: const CircularProgressIndicator(
                      key: Key('media-thumbnail-loading'),
                      strokeWidth: 2,
                    ),
                  ),
                );
              }

              final thumbnail = snapshot.data;
              if (thumbnail == null) {
                return _FallbackThumbnail(
                  icon: widget.fallbackIcon,
                  color: widget.fallbackColor,
                  iconSize: widget.fallbackIconSize,
                );
              }

              return Image.file(
                File(thumbnail.path),
                key: const Key('media-thumbnail-image'),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _FallbackThumbnail(
                    icon: widget.fallbackIcon,
                    color: widget.fallbackColor,
                    iconSize: widget.fallbackIconSize,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FallbackThumbnail extends StatelessWidget {
  const _FallbackThumbnail({
    required this.icon,
    required this.color,
    required this.iconSize,
  });

  final IconData icon;
  final Color color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        key: const Key('media-thumbnail-fallback'),
        color: color,
        size: iconSize,
      ),
    );
  }
}

bool isMediaFileEntry(FileEntry entry) {
  return entry.type == FileEntryType.image || entry.type == FileEntryType.video;
}
