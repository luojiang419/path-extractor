import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/file_entry.dart';
import 'package:path_extractor_browser/services/thumbnail_service.dart';
import 'package:path_extractor_browser/widgets/file_list_item.dart';
import 'package:path_extractor_browser/widgets/media_thumbnail.dart';

void main() {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_list_item_test_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}thumb.png');
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('图片文件显示缩略图组件', (tester) async {
    final entry = FileEntry.fromPath(imageFile.path, isDirectory: false);

    await tester.pumpWidget(
      _buildItem(
        service: _FakeThumbnailService(
          () async => ThumbnailFile(path: imageFile.path, isGenerated: false),
        ),
        entry: entry,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MediaThumbnail), findsOneWidget);
  });

  testWidgets('文档文件保持原图标不显示缩略图组件', (tester) async {
    final docFile = File('${tempDir.path}${Platform.pathSeparator}readme.pdf')
      ..writeAsBytesSync(const [1, 2, 3]);
    final entry = FileEntry.fromPath(docFile.path, isDirectory: false);

    await tester.pumpWidget(
      _buildItem(
        service: _FakeThumbnailService(() async => null),
        entry: entry,
      ),
    );
    await tester.pump();

    expect(find.byType(MediaThumbnail), findsNothing);
    expect(find.byIcon(Icons.description), findsOneWidget);
  });
}

Widget _buildItem({
  required ThumbnailService service,
  required FileEntry entry,
}) {
  return ProviderScope(
    overrides: [thumbnailServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      home: Scaffold(
        body: FileListItem(entry: entry, onTap: () {}, onCopyPath: () {}),
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
