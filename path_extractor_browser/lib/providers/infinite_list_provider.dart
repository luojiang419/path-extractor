import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/browser_state.dart';
import '../models/file_entry.dart';
import '../models/infinite_list_state.dart';
import '../services/file_system_service.dart';
import '../services/network_drive_service.dart';
import '../services/path_service.dart';

enum InfinitePathSubmitResult { handledInInfinite, switchToBrowser, invalid }

class InfiniteListNotifier extends StateNotifier<InfiniteListState> {
  InfiniteListNotifier(this._fileSystemService, this._pathService)
    : super(InfiniteListState.initial());

  final FileSystemService _fileSystemService;
  final PathService _pathService;

  void enterFromDrop(List<String> paths) {
    final newEntries = _entriesFromPaths(paths);
    if (newEntries.isEmpty) return;

    state = InfiniteListState(
      isActive: true,
      rootEntries: newEntries,
      currentEntries: newEntries,
      isRootView: true,
      viewMode: state.viewMode,
      sortField: state.sortField,
      sortOrder: state.sortOrder,
    );
  }

  void appendDroppedEntries(List<String> paths) {
    if (!state.isActive) {
      enterFromDrop(paths);
      return;
    }

    final incoming = _entriesFromPaths(paths, existing: state.rootEntries);
    if (incoming.isEmpty) return;

    final updatedRoots = [...state.rootEntries, ...incoming];
    state = state.copyWith(
      isActive: true,
      rootEntries: updatedRoots,
      currentEntries: state.isRootView ? updatedRoots : state.currentEntries,
      clearError: true,
    );
  }

  Future<void> navigateTo(String path) async {
    final anchorPath = state.isRootView ? path : state.anchorPath;
    final anchorLabel = state.isRootView
        ? state.rootEntries
                  .where((entry) => entry.path == path)
                  .map((entry) => entry.name)
                  .firstOrNull ??
              FileEntry.fromPath(path, isDirectory: true).name
        : state.anchorLabel;
    await _navigateToPath(
      path,
      anchorPath: anchorPath,
      anchorLabel: anchorLabel,
    );
  }

  Future<InfinitePathSubmitResult> navigateToSubmittedPath(
    String rawPath,
  ) async {
    final target = _resolveSubmittedPath(rawPath);
    if (target == null) {
      if (NetworkDriveService.isPotentialNetworkInput(rawPath)) {
        return InfinitePathSubmitResult.switchToBrowser;
      }
      return InfinitePathSubmitResult.invalid;
    }

    final anchorRoot = _bestContainingDirectoryRoot(target.directoryPath);
    if (anchorRoot == null) {
      return InfinitePathSubmitResult.switchToBrowser;
    }

    await _navigateToPath(
      target.directoryPath,
      anchorPath: anchorRoot.path,
      anchorLabel: anchorRoot.name,
      highlightedPath: target.highlightedFilePath,
    );
    return InfinitePathSubmitResult.handledInInfinite;
  }

  Future<void> _navigateToPath(
    String path, {
    required String? anchorPath,
    required String? anchorLabel,
    String? highlightedPath,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entries = await _fileSystemService.listDirectory(path);
      state = state.copyWith(
        currentPath: path,
        currentEntries: entries,
        anchorPath: anchorPath,
        anchorLabel: anchorLabel,
        highlightedPath: highlightedPath,
        clearHighlightedPath: highlightedPath == null,
        isRootView: false,
        isLoading: false,
        filterQuery: '',
        clearError: true,
      );
    } on PermissionDeniedException {
      state = state.copyWith(isLoading: false, errorMessage: '权限不足，无法访问该目录');
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> navigateUp() async {
    if (state.isRootView) return;
    if (state.anchorPath != null && state.currentPath == state.anchorPath) {
      navigateToRoot();
      return;
    }
    final segments = _pathService.splitSegments(state.currentPath);
    if (segments.length <= 1) {
      navigateToRoot();
      return;
    }
    final parentPath = _pathService.joinSegments(
      segments.sublist(0, segments.length - 1),
    );
    await navigateTo(parentPath);
  }

  Future<void> navigateToSegment(int segmentIndex) async {
    final anchorPath = state.anchorPath;
    if (anchorPath == null) {
      navigateToRoot();
      return;
    }
    if (segmentIndex == 0) {
      await _navigateToPath(
        anchorPath,
        anchorPath: anchorPath,
        anchorLabel: state.anchorLabel,
      );
      return;
    }

    final anchorSegments = _pathService.splitSegments(anchorPath);
    final currentSegments = _pathService.splitSegments(state.currentPath);
    final extraCount = segmentIndex;
    final targetPath = _pathService.joinSegments([
      ...anchorSegments,
      ...currentSegments.skip(anchorSegments.length).take(extraCount),
    ]);
    await _navigateToPath(
      targetPath,
      anchorPath: anchorPath,
      anchorLabel: state.anchorLabel,
    );
  }

  void navigateToRoot() {
    state = state.copyWith(
      currentPath: '',
      currentEntries: state.rootEntries,
      clearAnchor: true,
      clearHighlightedPath: true,
      isRootView: true,
      isLoading: false,
      filterQuery: '',
      clearError: true,
    );
  }

  void removeEntry(String path) {
    final updatedRoots = state.rootEntries
        .where((entry) => entry.path != path)
        .toList();
    state = state.copyWith(
      rootEntries: updatedRoots,
      currentEntries: state.isRootView ? updatedRoots : state.currentEntries,
      clearHighlightedPath: state.highlightedPath == path,
      clearLastCopied: state.lastCopiedPath == path,
    );
  }

  void clearAll() {
    state = state.copyWith(
      rootEntries: const [],
      currentEntries: const [],
      currentPath: '',
      clearAnchor: true,
      clearHighlightedPath: true,
      isRootView: true,
      clearLastCopied: true,
      clearError: true,
      filterQuery: '',
    );
  }

  void exitAndClear() {
    state = InfiniteListState.initial().copyWith(
      viewMode: state.viewMode,
      sortField: state.sortField,
      sortOrder: state.sortOrder,
    );
  }

  void setLastCopied(String path) {
    state = state.copyWith(lastCopiedPath: path, highlightedPath: path);
  }

  void setViewMode(ViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void setSortField(SortField field) {
    if (state.sortField == field) {
      final newOrder = state.sortOrder == SortOrder.asc
          ? SortOrder.desc
          : SortOrder.asc;
      state = state.copyWith(sortOrder: newOrder);
      return;
    }

    state = state.copyWith(sortField: field, sortOrder: SortOrder.asc);
  }

  void setFilter(String query) {
    state = state.copyWith(filterQuery: query, clearHighlightedPath: true);
  }

  FileEntry? _bestContainingDirectoryRoot(String path) {
    final normalizedPath = _normalizeForCompare(path);
    final directoryRoots =
        state.rootEntries.where((entry) => entry.isDirectory).toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));

    for (final root in directoryRoots) {
      if (_isSameOrDescendant(
        _normalizeForCompare(root.path),
        normalizedPath,
      )) {
        return root;
      }
    }
    return null;
  }

  _SubmittedPathTarget? _resolveSubmittedPath(String rawPath) {
    final submittedPath = _sanitizeSubmittedPath(rawPath);
    if (submittedPath == null) return null;

    final entityType = FileSystemEntity.typeSync(submittedPath);
    if (entityType == FileSystemEntityType.directory) {
      return _SubmittedPathTarget(directoryPath: submittedPath);
    }
    if (entityType == FileSystemEntityType.file) {
      return _SubmittedPathTarget(
        directoryPath: File(submittedPath).parent.path,
        highlightedFilePath: submittedPath,
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

    path = _pathService.normalize(path);
    if (Platform.isWindows && _isDriveLetter(path)) {
      path = '$path\\';
    }

    if (!_looksAbsolutePath(path)) return null;
    return path;
  }

  String _normalizeForCompare(String path) {
    final normalizedPath = _pathService.normalize(path);
    if (Platform.isWindows) {
      return normalizedPath.toLowerCase();
    }
    return normalizedPath;
  }

  bool _isSameOrDescendant(String base, String candidate) {
    if (candidate == base) return true;
    final separator = Platform.isWindows ? '\\' : '/';
    return candidate.startsWith('$base$separator');
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

  List<FileEntry> _entriesFromPaths(
    List<String> paths, {
    List<FileEntry> existing = const [],
  }) {
    final existingPaths = existing.map((entry) => entry.path).toSet();
    final seen = <String>{...existingPaths};
    final entries = <FileEntry>[];

    for (final path in paths) {
      if (path.isEmpty || seen.contains(path)) continue;
      seen.add(path);
      entries.add(
        FileEntry.fromPath(
          path,
          isDirectory: FileSystemEntity.isDirectorySync(path),
        ),
      );
    }

    return entries;
  }
}

class _SubmittedPathTarget {
  const _SubmittedPathTarget({
    required this.directoryPath,
    this.highlightedFilePath,
  });

  final String directoryPath;
  final String? highlightedFilePath;
}

final infiniteListProvider =
    StateNotifierProvider<InfiniteListNotifier, InfiniteListState>(
      (ref) => InfiniteListNotifier(FileSystemServiceImpl(), PathServiceImpl()),
    );
