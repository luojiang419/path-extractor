import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/file_entry.dart';
import 'special_image_thumbnail_service.dart';

typedef ProcessExecutor =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef TemporaryDirectoryResolver = Future<Directory> Function();
typedef FfmpegLocator = Future<String?> Function();
typedef FfprobeLocator = Future<String?> Function();
typedef SpecialImageThumbnailGenerator =
    Future<Uint8List?> Function({
      required String path,
      required SpecialImageFormatHint formatHint,
      required int maxEdge,
    });

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
    FfprobeLocator? ffprobeLocator,
    SpecialImageThumbnailGenerator? specialImageThumbnailGenerator,
  }) : _temporaryDirectoryResolver =
           temporaryDirectoryResolver ?? getTemporaryDirectory,
       _processExecutor = processExecutor ?? _defaultProcessExecutor,
       _ffmpegLocator = ffmpegLocator,
       _ffprobeLocator = ffprobeLocator,
       _specialImageThumbnailGenerator =
           specialImageThumbnailGenerator ??
           SpecialImageThumbnailService.generateThumbnail;

  static const _bundledFfmpegName = 'ffmpeg.exe';
  static const _bundledFfprobeName = 'ffprobe.exe';
  static const _thumbnailSize = 320;
  static const _rawImageExts = {
    'cr2',
    'cr3',
    'crw',
    'dng',
    'nef',
    'nrw',
    'arw',
    'raf',
    'rw2',
    'orf',
    'pef',
    'srw',
    'x3f',
  };

  final TemporaryDirectoryResolver _temporaryDirectoryResolver;
  final ProcessExecutor _processExecutor;
  final FfmpegLocator? _ffmpegLocator;
  final FfprobeLocator? _ffprobeLocator;
  final SpecialImageThumbnailGenerator _specialImageThumbnailGenerator;

  final Map<String, Future<ThumbnailFile?>> _inFlight = {};

  Directory? _cacheDirectory;
  Future<String?>? _resolvedFfmpegFuture;
  Future<String?>? _resolvedFfprobeFuture;

  @override
  Future<ThumbnailFile?> getThumbnail(FileEntry entry) async {
    if (entry.isDirectory) {
      return null;
    }

    switch (entry.type) {
      case FileEntryType.image:
        return _getImageThumbnail(entry.path);
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

  Future<ThumbnailFile?> _getImageThumbnail(String imagePath) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      return null;
    }

    final formatHint = _specialImageFormatForPath(imagePath);
    if (formatHint == null) {
      return ThumbnailFile(path: imagePath, isGenerated: false);
    }

    late final FileStat stat;
    try {
      stat = await imageFile.stat();
    } on FileSystemException {
      return null;
    }

    final cacheKey = _buildCacheKey('image:$imagePath', stat);
    final cacheDirectory = await _getCacheDirectory();
    final outputPath = path.join(cacheDirectory.path, '$cacheKey.png');
    final outputFile = File(outputPath);
    if (await _isUsableFile(outputFile)) {
      return ThumbnailFile(path: outputPath, isGenerated: true);
    }

    final inflight = _inFlight[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _generateSpecialImageThumbnail(
      imagePath: imagePath,
      formatHint: formatHint,
      outputFile: outputFile,
    );
    _inFlight[cacheKey] = future;

    try {
      return await future;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<ThumbnailFile?> _generateSpecialImageThumbnail({
    required String imagePath,
    required SpecialImageFormatHint formatHint,
    required File outputFile,
  }) async {
    final bytes = await _specialImageThumbnailGenerator(
      path: imagePath,
      formatHint: formatHint,
      maxEdge: _thumbnailSize,
    );

    if (bytes != null && bytes.isNotEmpty) {
      try {
        await outputFile.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        return null;
      }

      if (await _isUsableFile(outputFile)) {
        return ThumbnailFile(path: outputFile.path, isGenerated: true);
      }
    }

    if (formatHint == SpecialImageFormatHint.psd) {
      return _generatePsdFallbackThumbnail(imagePath, outputFile);
    }

    return null;
  }

  Future<ThumbnailFile?> _generatePsdFallbackThumbnail(
    String imagePath,
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
      '-i',
      imagePath,
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
    final ffprobePath = await _resolveFfprobePath();
    final ffmpegPath = await _resolveFfmpegPath();
    if (ffprobePath == null || ffmpegPath == null) {
      return null;
    }

    final probe = await _probeVideoFile(ffprobePath, videoPath);
    if (probe == null || !probe.hasVideoStream) {
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
      '-i',
      videoPath,
      '-frames:v',
      '1',
      '-vf',
      'thumbnail=100,scale=$_thumbnailSize:$_thumbnailSize:force_original_aspect_ratio=decrease',
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

  Future<_VideoProbeResult?> _probeVideoFile(
    String ffprobePath,
    String videoPath,
  ) async {
    final result = await _processExecutor(ffprobePath, [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=codec_type',
      '-show_entries',
      'format=duration',
      '-of',
      'json',
      videoPath,
    ]);

    if (result.exitCode != 0) {
      return null;
    }

    try {
      final decoded = jsonDecode('${result.stdout}');
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final streams = decoded['streams'];
      final hasVideoStream = streams is List && streams.isNotEmpty;
      final format = decoded['format'];
      final durationSeconds = format is Map<String, dynamic>
          ? double.tryParse('${format['duration'] ?? ''}')
          : null;
      return _VideoProbeResult(
        hasVideoStream: hasVideoStream,
        duration: durationSeconds == null
            ? null
            : Duration(milliseconds: (durationSeconds * 1000).round()),
      );
    } on FormatException {
      return null;
    }
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
        ? _ffmpegLocator!()
        : _locateExecutable(_bundledFfmpegName, 'ffmpeg'));
  }

  Future<String?> _resolveFfprobePath() {
    return _resolvedFfprobeFuture ??= (_ffprobeLocator != null
        ? _ffprobeLocator!()
        : _locateExecutable(_bundledFfprobeName, 'ffprobe'));
  }

  Future<String?> _locateExecutable(
    String bundledName,
    String commandName,
  ) async {
    final bundledPath = path.join(
      File(Platform.resolvedExecutable).parent.path,
      bundledName,
    );
    if (await File(bundledPath).exists()) {
      return bundledPath;
    }

    final lookupCommand = Platform.isWindows ? 'where' : 'which';
    final lookupArguments = Platform.isWindows
        ? [commandName]
        : <String>[commandName];
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

  SpecialImageFormatHint? _specialImageFormatForPath(String imagePath) {
    final ext = path.extension(imagePath).toLowerCase().replaceFirst('.', '');
    if (ext == 'psd') {
      return SpecialImageFormatHint.psd;
    }
    if (_rawImageExts.contains(ext)) {
      return SpecialImageFormatHint.raw;
    }
    return null;
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

class _VideoProbeResult {
  const _VideoProbeResult({required this.hasVideoStream, this.duration});

  final bool hasVideoStream;
  final Duration? duration;
}
