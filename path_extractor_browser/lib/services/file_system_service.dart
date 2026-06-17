import 'dart:io';

import '../models/file_entry.dart';

class PermissionDeniedException implements Exception {
  final String path;
  const PermissionDeniedException(this.path);

  @override
  String toString() => 'PermissionDeniedException: $path';
}

abstract class FileSystemService {
  Future<String> getHomeDirectory();
  Future<List<FileEntry>> listDirectory(String path);
  Future<List<FileEntry>> getDrives();
}

class FileSystemServiceImpl implements FileSystemService {
  @override
  Future<String> getHomeDirectory() async {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/';
  }

  @override
  Future<List<FileEntry>> getDrives() async {
    if (Platform.isWindows) {
      final drives = <FileEntry>[];
      // 检测 A-Z 所有可能的驱动器
      for (var i = 65; i <= 90; i++) {
        final letter = String.fromCharCode(i);
        final drivePath = '$letter:\\';
        if (await Directory(drivePath).exists()) {
          drives.add(
            FileEntry(
              path: drivePath,
              name: '$letter:',
              isDirectory: true,
              type: FileEntryType.directory,
            ),
          );
        }
      }
      return drives;
    } else {
      // macOS/Linux 返回根目录
      return [
        FileEntry(
          path: '/',
          name: '/',
          isDirectory: true,
          type: FileEntryType.directory,
        ),
      ];
    }
  }

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    try {
      final dir = Directory(path);
      final entities = await dir.list().toList();
      final entries = entities.map((entity) {
        final isDir = entity is Directory;
        return FileEntry.fromPath(entity.path, isDirectory: isDir);
      }).toList();
      return _sortEntries(entries);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 5 || e.osError?.errorCode == 13) {
        throw PermissionDeniedException(path);
      }
      rethrow;
    }
  }

  List<FileEntry> _sortEntries(List<FileEntry> entries) {
    final dirs = entries.where((e) => e.isDirectory).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = entries.where((e) => !e.isDirectory).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...dirs, ...files];
  }
}
