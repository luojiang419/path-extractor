import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/file_entry.dart';
import 'package:path_extractor_browser/services/special_image_thumbnail_service.dart';
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

  test('PSD 条目优先使用原生生成结果并命中缓存', () async {
    final psdFile = File('${tempDir.path}${Platform.pathSeparator}cover.psd')
      ..writeAsBytesSync(const [1, 2, 3]);
    var generatorCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      specialImageThumbnailGenerator: ({
        required path,
        required formatHint,
        required maxEdge,
      }) async {
        generatorCalls++;
        expect(path, psdFile.path);
        expect(formatHint, SpecialImageFormatHint.psd);
        expect(maxEdge, 320);
        return Uint8List.fromList(base64Decode(_tinyPngBase64));
      },
      processExecutor: (_, __) async => ProcessResult(0, 0, '', ''),
    );

    final first = await service.getThumbnail(
      FileEntry.fromPath(psdFile.path, isDirectory: false),
    );
    final second = await service.getThumbnail(
      FileEntry.fromPath(psdFile.path, isDirectory: false),
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.path, isNot(psdFile.path));
    expect(first.path, second!.path);
    expect(first.isGenerated, isTrue);
    expect(await File(first.path).exists(), isTrue);
    expect(generatorCalls, 1);
  });

  test('PSD 原生生成失败后回退到 ffmpeg 生成缩略图', () async {
    final psdFile = File('${tempDir.path}${Platform.pathSeparator}cover.psd')
      ..writeAsBytesSync(const [1, 2, 3]);
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      specialImageThumbnailGenerator: ({
        required path,
        required formatHint,
        required maxEdge,
      }) async => null,
      processExecutor: (_, arguments) async {
        final outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(psdFile.path, isDirectory: false),
    );

    expect(result, isNotNull);
    expect(result!.isGenerated, isTrue);
    expect(await File(result.path).exists(), isTrue);
  });

  test('RAW 原生生成失败时返回空结果', () async {
    final rawFile = File('${tempDir.path}${Platform.pathSeparator}shot.cr3')
      ..writeAsBytesSync(const [1, 2, 3]);
    var processCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      specialImageThumbnailGenerator: ({
        required path,
        required formatHint,
        required maxEdge,
      }) async => null,
      processExecutor: (_, __) async {
        processCalls++;
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(rawFile.path, isDirectory: false),
    );

    expect(result, isNull);
    expect(processCalls, 0);
  });

  test('视频缩略图命中缓存后不会重复启动 ffmpeg', () async {
    final videoFile = File('${tempDir.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    var processCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (executable, arguments) async {
        if (executable == 'ffprobe') {
          return ProcessResult(
            0,
            0,
            '{"streams":[{"codec_type":"video"}],"format":{"duration":"4.2"}}',
            '',
          );
        }
        processCalls++;
        final outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
      ffprobeLocator: () async => 'ffprobe',
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
      processExecutor: (executable, arguments) async {
        if (executable == 'ffprobe') {
          return ProcessResult(
            0,
            0,
            '{"streams":[{"codec_type":"video"}],"format":{"duration":"4.2"}}',
            '',
          );
        }
        processCalls++;
        await completer.future;
        final outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
      ffprobeLocator: () async => 'ffprobe',
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

  test('ffmpeg 或 ffprobe 缺失时返回空结果并回退图标', () async {
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
      ffprobeLocator: () async => null,
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
      processExecutor: (executable, arguments) async {
        if (executable == 'ffprobe') {
          return ProcessResult(
            0,
            0,
            '{"streams":[{"codec_type":"video"}],"format":{"duration":"4.2"}}',
            '',
          );
        }
        outputFile = File(arguments.last);
        await outputFile.writeAsBytes(const [7, 8, 9]);
        return ProcessResult(0, 1, '', 'failed');
      },
      ffmpegLocator: () async => 'ffmpeg',
      ffprobeLocator: () async => 'ffprobe',
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
      ffprobeLocator: () async => 'ffprobe',
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(missingPath, isDirectory: false),
    );

    expect(result, isNull);
  });

  test('ffprobe 无法识别视频流时直接回退图标', () async {
    final videoFile = File('${tempDir.path}${Platform.pathSeparator}audio.mov')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    var ffmpegCalls = 0;
    final service = ThumbnailServiceImpl(
      temporaryDirectoryResolver: () async => tempDir,
      processExecutor: (executable, arguments) async {
        if (executable == 'ffprobe') {
          return ProcessResult(
            0,
            0,
            '{"streams":[],"format":{"duration":"2.5"}}',
            '',
          );
        }
        ffmpegCalls++;
        return ProcessResult(0, 0, '', '');
      },
      ffmpegLocator: () async => 'ffmpeg',
      ffprobeLocator: () async => 'ffprobe',
    );

    final result = await service.getThumbnail(
      FileEntry.fromPath(videoFile.path, isDirectory: false),
    );

    expect(result, isNull);
    expect(ffmpegCalls, 0);
  });
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+5d8AAAAASUVORK5CYII=';
