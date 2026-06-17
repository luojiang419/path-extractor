import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/file_entry.dart';
import 'package:path_extractor_browser/services/thumbnail_service.dart';
import 'package:path_extractor_browser/widgets/media_thumbnail.dart';

void main() {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_thumbnail_test_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}thumb.png');
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('加载中显示占位态', (tester) async {
    final completer = Completer<ThumbnailFile?>();

    await tester.pumpWidget(
      _buildTestApp(
        service: _FakeThumbnailService(() => completer.future),
        entry: FileEntry.fromPath(
          '${tempDir.path}${Platform.pathSeparator}video.mp4',
          isDirectory: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('media-thumbnail-loading')), findsOneWidget);
  });

  testWidgets('成功时显示缩略图图片', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        service: _FakeThumbnailService(
          () async => ThumbnailFile(path: imageFile.path, isGenerated: true),
        ),
        entry: FileEntry.fromPath(
          '${tempDir.path}${Platform.pathSeparator}video.mp4',
          isDirectory: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('media-thumbnail-image')), findsOneWidget);
  });

  testWidgets('失败时回退到图标态', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        service: _FakeThumbnailService(() async => null),
        entry: FileEntry.fromPath(
          '${tempDir.path}${Platform.pathSeparator}video.mp4',
          isDirectory: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('media-thumbnail-fallback')), findsOneWidget);
  });
}

Widget _buildTestApp({
  required ThumbnailService service,
  required FileEntry entry,
}) {
  return ProviderScope(
    overrides: [thumbnailServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaThumbnail(
            entry: entry,
            width: 64,
            height: 64,
            borderRadius: BorderRadius.circular(12),
            fallbackIcon: Icons.video_file,
            fallbackColor: Colors.purple,
          ),
        ),
      ),
    ),
  );
}

class _FakeThumbnailService implements ThumbnailService {
  _FakeThumbnailService(this._loader);

  final Future<ThumbnailFile?> Function() _loader;

  @override
  Future<ThumbnailFile?> getThumbnail(FileEntry entry) {
    return _loader();
  }
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+5d8AAAAASUVORK5CYII=';
