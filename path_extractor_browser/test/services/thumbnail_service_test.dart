import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/file_entry.dart';
import 'package:path_extractor_browser/services/thumbnail_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thumbnail_service_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('图片条目直接返回原文件且不触发 ffmpeg', () async {
    final imageFile = File('${tempDir.path}${Platform.pathSeparator}photo.png')
      ..writeAsBytesSync(const [1, 2, 3]);
    var processCalls = 0;
    var locatorCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (_, __) async {
        processCalls++;
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async {
        locatorCalls++;
        return 'ffmpeg';
      },
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(imageFile.path, isDirectory: false),
    );

    expect(result, isNotNull);
    expect(result!.path, imageFile.path);
    expect(result.isGenerated, isFalse);
    expect(processCalls, 0);
    expect(locatorCalls, 0);
  });

  test('视频缩略图命中缓存后不会重复启动 ffmpeg', () async {
    final videoFile = File('${tempDir.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    var processCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (_, arguments) async {
        processCalls++;
        final outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
    );
    final entry = FileEntry.fromPath(videoFile.path, isDirectory: false);

    final first = await service.getThumbnail(entry);
    final second = await service.getThumbnail(entry);

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.path, second!.path);
    expect(first.isGenerated, isTrue);
    expect(processCalls, 1);
  });

  test('同一视频并发请求时只生成一次缩略图', () async {
    final videoFile = File('${tempDir.path}${Platform.pathSeparator}sync.mp4')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    final completer = Completer<void>();
    var processCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (_, arguments) async {
        processCalls++;
        await completer.future;
        final outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
    );
    final entry = FileEntry.fromPath(videoFile.path, isDirectory: false);

    final firstFuture = service.getThumbnail(entry);
    final secondFuture = service.getThumbnail(entry);
    completer.complete();
    final results = await Future.wait([firstFuture, secondFuture]);

    expect(results[0], isNotNull);
    expect(results[1], isNotNull);
    expect(results[0]!.path, results[1]!.path);
    expect(processCalls, 1);
  });

  test('ffmpeg 缺失时返回空结果并回退图标', () async {
    final videoFile = File('${tempDir.path}${Platform.pathSeparator}lost.mp4')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    var processCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (_, __) async {
        processCalls++;
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => null,
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(videoFile.path, isDirectory: false),
    );

    expect(result, isNull);
    expect(processCalls, 0);
  });

  test('ffmpeg 执行失败时删除残留缩略图并返回空结果', () async {
    final videoFile = File('${tempDir.path}${Platform.pathSeparator}broken.mp4')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    late File outputFile;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (_, arguments) async {
        outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 1, '', 'failed');
      },
      ffmpegLocator: () async => 'ffmpeg',
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(videoFile.path, isDirectory: false),
    );

    expect(result, isNull);
    expect(await outputFile.exists(), isFalse);
  });

  test('源视频不存在时直接返回空结果', () async {
    final missingPath = '${tempDir.path}${Platform.pathSeparator}missing.mp4';
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (_, __) async => ProcessResult(0, 0, '', ''),
      ffmpegLocator: () async => 'ffmpeg',
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(missingPath, isDirectory: false),
    );

    expect(result, isNull);
  });
}
