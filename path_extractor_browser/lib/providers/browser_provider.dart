import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/browser_state.dart';
import '../models/file_entry.dart';
import '../services/file_system_service.dart';
import '../services/network_drive_service.dart';
import '../services/path_service.dart';

enum BrowserNavigationStatus { navigated, invalid, authenticationRequired }

class BrowserPathSubmitResult {
  const BrowserPathSubmitResult._({
    required this.status,
    this.authScope,
    this.message,
  });

  const BrowserPathSubmitResult.navigated()
    : this._(status: BrowserNavigationStatus.navigated);

  const BrowserPathSubmitResult.invalid({String? message})
    : this._(status: BrowserNavigationStatus.invalid, message: message);

  const BrowserPathSubmitResult.authenticationRequired({
    required String authScope,
    String? message,
  }) : this._(
         status: BrowserNavigationStatus.authenticationRequired,
         authScope: authScope,
         message: message,
       );

  final BrowserNavigationStatus status;
  final String? authScope;
  final String? message;
}

class BrowserNotifier extends StateNotifier<BrowserState> {
  final FileSystemService _fileSystemService;
  final PathService _pathService;
  final NetworkDriveService _networkDriveService;

  BrowserNotifier(
    this._fileSystemService,
    this._pathService,
    this._networkDriveService,
  ) : super(BrowserState.initial()) {
    _init();
  }

  Future<void> _init() async {
    await _loadNetworkDrives();
    await navigateToRoot();
  }

  Future<void> _loadNetworkDrives() async {
    final drives = await _networkDriveService.loadAll();
    state = state.copyWith(networkDrives: drives);
  }

  Future<void> navigateToRoot() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final drives = await _fileSystemService.getDrives();
      final networkDrives = await _networkDriveService.loadAll();
      state = state.copyWith(
        currentPath: '',
        entries: drives,
        clearHighlightedPath: true,
        isLoading: false,
        isRootView: true,
        filterQuery: '',
        networkDrives: networkDrives,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString(), isLoading: false);
    }
  }

  Future<void> navigateTo(String path) async {
    await _navigateToDirectory(path);
  }

  Future<BrowserPathSubmitResult> navigateToSubmittedPath(
    String rawPath, {
    NetworkDriveEntry? credentials,
  }) async {
    final target = _resolveSubmittedPath(rawPath);
    if (target == null) {
      state = state.copyWith(clearError: true, clearHighlightedPath: true);
      return const BrowserPathSubmitResult.invalid();
    }

    switch (target.kind) {
      case _SubmittedTargetKind.localDirectory:
        await _navigateToDirectory(target.path);
        return const BrowserPathSubmitResult.navigated();
      case _SubmittedTargetKind.localFile:
        await _navigateToDirectory(
          File(target.path).parent.path,
          highlightedPath: target.path,
        );
        return const BrowserPathSubmitResult.navigated();
      case _SubmittedTargetKind.networkHostRoot:
        final result = await _networkDriveService.browseWindowsHost(
          target.path,
          credentials: credentials,
        );
        switch (result.status) {
          case NetworkProbeStatus.accessible:
            _showNetworkHostEntries(target.path, result.entries);
            return const BrowserPathSubmitResult.navigated();
          case NetworkProbeStatus.authenticationRequired:
            state = state.copyWith(
              clearError: true,
              clearHighlightedPath: true,
            );
            return BrowserPathSubmitResult.authenticationRequired(
              authScope: result.authScope ?? target.path,
              message: result.message,
            );
          case NetworkProbeStatus.unavailable:
            state = state.copyWith(
              clearError: true,
              clearHighlightedPath: true,
            );
            return BrowserPathSubmitResult.invalid(message: result.message);
        }
      case _SubmittedTargetKind.networkPath:
        final result = await _networkDriveService.probeWindowsPath(
          target.path,
          credentials: credentials,
        );
        switch (result.status) {
          case NetworkProbeStatus.accessible:
            if (result.entityType == FileSystemEntityType.file) {
              await _navigateToDirectory(
                File(target.path).parent.path,
                highlightedPath: target.path,
              );
            } else if (result.entityType == FileSystemEntityType.directory) {
              await _navigateToDirectory(target.path);
            } else {
              state = state.copyWith(
                clearError: true,
                clearHighlightedPath: true,
              );
              return const BrowserPathSubmitResult.invalid();
            }
            return const BrowserPathSubmitResult.navigated();
          case NetworkProbeStatus.authenticationRequired:
            state = state.copyWith(
              clearError: true,
              clearHighlightedPath: true,
            );
            return BrowserPathSubmitResult.authenticationRequired(
              authScope: result.authScope ?? target.path,
              message: result.message,
            );
          case NetworkProbeStatus.unavailable:
            state = state.copyWith(
              clearError: true,
              clearHighlightedPath: true,
            );
            return BrowserPathSubmitResult.invalid(message: result.message);
        }
    }
  }

  Future<void> _navigateToDirectory(
    String path, {
    String? highlightedPath,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entries = await _fileSystemService.listDirectory(path);
      state = state.copyWith(
        currentPath: path,
        entries: entries,
        highlightedPath: highlightedPath,
        clearHighlightedPath: highlightedPath == null,
        isLoading: false,
        isRootView: false,
        filterQuery: '',
        clearError: true,
      );
    } on PermissionDeniedException {
      state = state.copyWith(errorMessage: '权限不足，无法访问该目录', isLoading: false);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString(), isLoading: false);
    }
  }

  Future<void> navigateUp() async {
    if (state.isRootView) return;
    final segments = _pathService.splitSegments(state.currentPath);
    if (segments.length <= 1) {
      await navigateToRoot();
    } else {
      final parentSegments = segments.sublist(0, segments.length - 1);
      final parentPath = _pathService.joinSegments(parentSegments);
      await navigateTo(parentPath);
    }
  }

  Future<void> navigateToSegment(int segmentIndex) async {
    final segments = _pathService.splitSegments(state.currentPath);
    final targetSegments = segments.sublist(0, segmentIndex + 1);
    final targetPath = _pathService.joinSegments(targetSegments);
    await navigateTo(targetPath);
  }

  /// 添加并保存网络驱动器
  Future<void> addNetworkDrive(NetworkDriveEntry entry) async {
    await _networkDriveService.add(entry);
    final updated = await _networkDriveService.loadAll();
    state = state.copyWith(networkDrives: updated);
  }

  /// 移除网络驱动器
  Future<void> removeNetworkDrive(String address) async {
    await _networkDriveService.remove(address);
    final updated = await _networkDriveService.loadAll();
    state = state.copyWith(networkDrives: updated);
  }

  void setViewMode(ViewMode mode) => state = state.copyWith(viewMode: mode);

  void setSortField(SortField field) {
    if (state.sortField == field) {
      final newOrder = state.sortOrder == SortOrder.asc
          ? SortOrder.desc
          : SortOrder.asc;
      state = state.copyWith(sortOrder: newOrder);
    } else {
      state = state.copyWith(sortField: field, sortOrder: SortOrder.asc);
    }
  }

  void setFilter(String query) =>
      state = state.copyWith(filterQuery: query, clearHighlightedPath: true);

  void clearHighlightedPath() {
    state = state.copyWith(clearHighlightedPath: true);
  }

  _SubmittedPathTarget? _resolveSubmittedPath(String rawPath) {
    final submittedPath = _sanitizeSubmittedPath(rawPath);
    if (submittedPath == null) return null;

    final parsedNetworkPath = NetworkDriveService.parseNetworkPath(
      submittedPath,
    );
    if (parsedNetworkPath != null) {
      return _SubmittedPathTarget(
        path: parsedNetworkPath.path,
        kind: parsedNetworkPath.isHostRoot
            ? _SubmittedTargetKind.networkHostRoot
            : _SubmittedTargetKind.networkPath,
      );
    }

    final entityType = FileSystemEntity.typeSync(submittedPath);
    if (entityType == FileSystemEntityType.directory) {
      return _SubmittedPathTarget(
        path: submittedPath,
        kind: _SubmittedTargetKind.localDirectory,
      );
    }
    if (entityType == FileSystemEntityType.file) {
      return _SubmittedPathTarget(
        path: submittedPath,
        kind: _SubmittedTargetKind.localFile,
      );
    }
    return null;
  }

  String? _sanitizeSubmittedPath(String rawPath) {
    var path = rawPath.trim();
    if (path.isEmpty) return null;

    if ((path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1).trim();
    }
    if (path.isEmpty) return null;

    final parsedNetworkPath = NetworkDriveService.parseNetworkPath(path);
    if (parsedNetworkPath != null) {
      return parsedNetworkPath.path;
    }

    path = _pathService.normalize(path);
    if (Platform.isWindows && _isDriveLetter(path)) {
      path = '$path\\';
    }

    if (!_looksAbsolutePath(path)) return null;
    return path;
  }

  bool _looksAbsolutePath(String path) {
    if (Platform.isWindows) {
      return path.startsWith(r'\\') || RegExp(r'^[A-Za-z]:\\').hasMatch(path);
    }
    return path.startsWith('/');
  }

  bool _isDriveLetter(String value) {
    return value.length == 2 && value[1] == ':';
  }

  void _showNetworkHostEntries(String hostRootPath, List<FileEntry> entries) {
    state = state.copyWith(
      currentPath: hostRootPath,
      entries: entries,
      clearHighlightedPath: true,
      isLoading: false,
      isRootView: false,
      filterQuery: '',
      clearError: true,
    );
  }
}

class _SubmittedPathTarget {
  const _SubmittedPathTarget({required this.path, required this.kind});

  final String path;
  final _SubmittedTargetKind kind;
}

enum _SubmittedTargetKind {
  localDirectory,
  localFile,
  networkHostRoot,
  networkPath,
}

final browserProvider = StateNotifierProvider<BrowserNotifier, BrowserState>(
  (ref) => BrowserNotifier(
    FileSystemServiceImpl(),
    PathServiceImpl(),
    NetworkDriveService(),
  ),
);
