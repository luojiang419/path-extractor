import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/file_entry.dart';

typedef ProcessExecutor =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef TemporaryDirectoryResolver = Future<Directory> Function();
typedef FfmpegLocator = Future<String?> Function();

class ThumbnailFile {
  const ThumbnailFile({required this.path, required this.isGenerated});

  final String path;
  final bool isGenerated;
}

abstract class ThumbnailService {
  Future<ThumbnailFile?> getThumbnail(FileEntry entry);
}

class ThumbnailServiceImpl implements ThumbnailService {
  ThumbnailServiceImpl({
    TemporaryDirectoryResolver? temporaryDirectoryResolver,
    ProcessExecutor? processExecutor,
    FfmpegLocator? ffmpegLocator,
  }) : _temporaryDirectoryResolver =
           temporaryDirectoryResolver ?? getTemporaryDirectory,
       _processExecutor = processExecutor ?? _defaultProcessExecutor,
       _ffmpegLocator = ffmpegLocator;

  static const _bundledFfmpegName = 'ffmpeg.exe';
  static const _developmentFfmpegPath = r'G:\data\ffmpeg\bin\ffmpeg.exe';
  static const _thumbnailAt = '00:00:01';
  static const _thumbnailSize = 320;

  final TemporaryDirectoryResolver _temporaryDirectoryResolver;
  final ProcessExecutor _processExecutor;
  final FfmpegLocator? _ffmpegLocator;

  final Map<String, Future<ThumbnailFile?>> _inFlight = {};

  Directory? _cacheDirectory;
  Future<String?>? _resolvedFfmpegFuture;

  @override
  Future<ThumbnailFile?> getThumbnail(FileEntry entry) async {
    if (entry.isDirectory) {
      return null;
    }

    switch (entry.type) {
      case FileEntryType.image:
        final file = File(entry.path);
        if (!await file.exists()) {
          return null;
        }
        return ThumbnailFile(path: entry.path, isGenerated: false);
      case FileEntryType.video:
        return _getVideoThumbnail(entry.path);
      case FileEntryType.directory:
      case FileEntryType.audio:
      case FileEntryType.code:
      case FileEntryType.document:
      case FileEntryType.archive:
      case FileEntryType.other:
        return null;
    }
  }

  Future<ThumbnailFile?> _getVideoThumbnail(String videoPath) async {
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return null;
    }

    late final FileStat stat;
    try {
      stat = await videoFile.stat();
    } on FileSystemException {
      return null;
    }

    final cacheKey = _buildCacheKey(videoPath, stat);
    final cacheDirectory = await _getCacheDirectory();
    final outputPath = path.join(cacheDirectory.path, '$cacheKey.jpg');
    final outputFile = File(outputPath);
    if (await _isUsableFile(outputFile)) {
      return ThumbnailFile(path: outputPath, isGenerated: true);
    }

    final inflight = _inFlight[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _generateVideoThumbnail(videoPath, outputFile);
    _inFlight[cacheKey] = future;

    try {
      return await future;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<ThumbnailFile?> _generateVideoThumbnail(
    String videoPath,
    File outputFile,
  ) async {
    final ffmpegPath = await _resolveFfmpegPath();
    if (ffmpegPath == null) {
      return null;
    }

    if (await outputFile.exists()) {
      try {
        await outputFile.delete();
      } on FileSystemException {
        return null;
      }
    }

    final result = await _processExecutor(ffmpegPath, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-ss',
      _thumbnailAt,
      '-i',
      videoPath,
      '-frames:v',
      '1',
      '-vf',
      'scale=$_thumbnailSize:$_thumbnailSize:force_original_aspect_ratio=decrease',
      outputFile.path,
    ]);

    if (result.exitCode != 0 || !await _isUsableFile(outputFile)) {
      if (await outputFile.exists()) {
        try {
          await outputFile.delete();
        } on FileSystemException {
          // Ignore cleanup failure and keep fallback behavior.
        }
      }
      return null;
    }

    return ThumbnailFile(path: outputFile.path, isGenerated: true);
  }

  Future<Directory> _getCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) {
      return existing;
    }

    final tempDirectory = await _temporaryDirectoryResolver();
    final cacheDirectory = Directory(
      path.join(tempDirectory.path, 'path_extractor_browser', 'thumbnails'),
    );
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }
    _cacheDirectory = cacheDirectory;
    return cacheDirectory;
  }

  Future<String?> _resolveFfmpegPath() {
    return _resolvedFfmpegFuture ??= (_ffmpegLocator != null
        ? _ffmpegLocator()
        : _locateFfmpeg());
  }

  Future<String?> _locateFfmpeg() async {
    final bundledPath = path.join(
      File(Platform.resolvedExecutable).parent.path,
      _bundledFfmpegName,
    );
    if (await File(bundledPath).exists()) {
      return bundledPath;
    }

    if (await File(_developmentFfmpegPath).exists()) {
      return _developmentFfmpegPath;
    }

    final lookupCommand = Platform.isWindows ? 'where' : 'which';
    final lookupArguments = Platform.isWindows ? ['ffmpeg'] : const ['ffmpeg'];
    try {
      final result = await _processExecutor(lookupCommand, lookupArguments);
      if (result.exitCode != 0) {
        return null;
      }

      final lines = LineSplitter.split(
        '${result.stdout}',
      ).map((line) => line.trim()).where((line) => line.isNotEmpty);
      return lines.firstOrNull;
    } on ProcessException {
      return null;
    }
  }

  String _buildCacheKey(String videoPath, FileStat stat) {
    final payload = [
      videoPath,
      stat.size.toString(),
      stat.modified.millisecondsSinceEpoch.toString(),
    ].join('|');
    return sha1.convert(utf8.encode(payload)).toString();
  }

  Future<bool> _isUsableFile(File file) async {
    if (!await file.exists()) {
      return false;
    }

    try {
      final stat = await file.stat();
      return stat.size > 0;
    } on FileSystemException {
      return false;
    }
  }

  static Future<ProcessResult> _defaultProcessExecutor(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments).timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          ProcessResult(-1, -1, '', 'ffmpeg thumbnail generation timed out'),
    );
  }
}

final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailServiceImpl(),
);
