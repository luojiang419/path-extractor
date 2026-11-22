import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/thumbnail_view_settings.dart';

abstract class ThumbnailViewSettingsStore {
  Future<ThumbnailViewSettings> load();

  Future<void> save(ThumbnailViewSettings settings);
}

class FileThumbnailViewSettingsStore implements ThumbnailViewSettingsStore {
  FileThumbnailViewSettingsStore({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const fileName = 'thumbnail_view_settings.json';

  final Future<Directory> Function() _directoryProvider;

  Future<File> _getFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<ThumbnailViewSettings> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return ThumbnailViewSettings.initial();
      }

      final content = await file.readAsString();
      final payload = jsonDecode(content);
      if (payload is! Map<String, dynamic>) {
        return ThumbnailViewSettings.initial();
      }

      return ThumbnailViewSettings.fromJson(payload);
    } catch (_) {
      return ThumbnailViewSettings.initial();
    }
  }

  @override
  Future<void> save(ThumbnailViewSettings settings) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}
