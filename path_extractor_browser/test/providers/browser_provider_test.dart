import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/file_entry.dart';
import 'package:path_extractor_browser/providers/browser_provider.dart';
import 'package:path_extractor_browser/services/file_system_service.dart';
import 'package:path_extractor_browser/services/network_drive_service.dart';
import 'package:path_extractor_browser/services/path_service.dart';

void main() {
  late Directory tempDir;
  late BrowserNotifier notifier;
  late _FakeNetworkDriveService networkDriveService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('path_extractor_browser_');
    networkDriveService = _FakeNetworkDriveService();
    notifier = BrowserNotifier(
      _FakeFileSystemService(),
      PathServiceImpl(),
      networkDriveService,
    );
    await _settleNotifier();
  });

  tearDown(() async {
    notifier.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('输入目录路径后会进入目标目录', () async {
    final folder = Directory('${tempDir.path}${Platform.pathSeparator}folder')
      ..createSync();

    final result = await notifier.navigateToSubmittedPath(folder.path);

    expect(result.status, BrowserNavigationStatus.navigated);
    expect(notifier.state.currentPath, folder.path);
    expect(notifier.state.isRootView, isFalse);
    expect(notifier.state.highlightedPath, isNull);
  });

  test('输入文件路径后会进入父目录并高亮文件', () async {
    final folder = Directory('${tempDir.path}${Platform.pathSeparator}folder')
      ..createSync();
    final file = File('${folder.path}${Platform.pathSeparator}note.txt')
      ..writeAsStringSync('note');

    final result = await notifier.navigateToSubmittedPath(file.path);

    expect(result.status, BrowserNavigationStatus.navigated);
    expect(notifier.state.currentPath, folder.path);
    expect(notifier.state.highlightedPath, file.path);
    expect(
      notifier.state.filteredEntries.any((entry) => entry.path == file.path),
      isTrue,
    );
  });

  test('输入无效路径后保持当前位置并返回 invalid', () async {
    final currentPath = notifier.state.currentPath;
    final invalidPath = '${tempDir.path}${Platform.pathSeparator}missing.txt';

    final result = await notifier.navigateToSubmittedPath(invalidPath);

    expect(result.status, BrowserNavigationStatus.invalid);
    expect(notifier.state.currentPath, currentPath);
    expect(notifier.state.highlightedPath, isNull);
  });

  test('输入网络主机地址后会展示共享列表', () async {
    networkDriveService.hostBrowseResults[r'\\10.10.10.10'] =
        const NetworkHostBrowseResult(
          status: NetworkProbeStatus.accessible,
          entries: [
            FileEntry(
              path: r'\\10.10.10.10\Public',
              name: 'Public',
              isDirectory: true,
              type: FileEntryType.directory,
            ),
          ],
        );

    final result = await notifier.navigateToSubmittedPath('10.10.10.10');

    expect(result.status, BrowserNavigationStatus.navigated);
    expect(notifier.state.currentPath, r'\\10.10.10.10');
    expect(notifier.state.entries.map((entry) => entry.path), [
      r'\\10.10.10.10\Public',
    ]);
  });

  test('输入受保护的网络主机地址时会请求认证', () async {
    networkDriveService.hostBrowseResults[r'\\10.10.10.20'] =
        const NetworkHostBrowseResult(
          status: NetworkProbeStatus.authenticationRequired,
          authScope: r'\\10.10.10.20',
          message: 'Access is denied',
        );

    final result = await notifier.navigateToSubmittedPath('10.10.10.20');

    expect(result.status, BrowserNavigationStatus.authenticationRequired);
    expect(result.authScope, r'\\10.10.10.20');
  });
}

class _FakeFileSystemService implements FileSystemService {
  @override
  Future<String> getHomeDirectory() async => '';

  @override
  Future<List<FileEntry>> getDrives() async => const [];

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final entries = await Directory(path).list().map((entity) {
      final isDirectory = entity is Directory;
      return FileEntry.fromPath(entity.path, isDirectory: isDirectory);
    }).toList();

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}

class _FakeNetworkDriveService extends NetworkDriveService {
  final Map<String, NetworkHostBrowseResult> hostBrowseResults = {};
  final Map<String, NetworkPathProbeResult> pathProbeResults = {};

  @override
  Future<List<NetworkDriveEntry>> loadAll() async => const [];

  @override
  Future<void> add(NetworkDriveEntry entry) async {}

  @override
  Future<void> remove(String address) async {}

  @override
  Future<NetworkHostBrowseResult> browseWindowsHost(
    String hostRootPath, {
    NetworkDriveEntry? credentials,
  }) async {
    return hostBrowseResults[hostRootPath] ??
        const NetworkHostBrowseResult(status: NetworkProbeStatus.unavailable);
  }

  @override
  Future<NetworkPathProbeResult> probeWindowsPath(
    String path, {
    NetworkDriveEntry? credentials,
  }) async {
    return pathProbeResults[path] ??
        const NetworkPathProbeResult(
          status: NetworkProbeStatus.unavailable,
          entityType: FileSystemEntityType.notFound,
        );
  }
}

Future<void> _settleNotifier() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
