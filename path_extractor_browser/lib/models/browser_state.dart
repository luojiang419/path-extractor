import 'file_entry.dart';
import '../services/network_drive_service.dart';

enum ViewMode { list, grid }

enum SortField { name, type }

enum SortOrder { asc, desc }

class BrowserState {
  final String currentPath;
  final List<FileEntry> entries;
  final String? highlightedPath;
  final bool isLoading;
  final String? errorMessage;
  final bool isRootView;
  final ViewMode viewMode;
  final SortField sortField;
  final SortOrder sortOrder;
  final String filterQuery;
  final List<NetworkDriveEntry> networkDrives; // 已保存的网络位置

  const BrowserState({
    required this.currentPath,
    required this.entries,
    this.highlightedPath,
    this.isLoading = false,
    this.errorMessage,
    this.isRootView = true,
    this.viewMode = ViewMode.grid,
    this.sortField = SortField.name,
    this.sortOrder = SortOrder.asc,
    this.filterQuery = '',
    this.networkDrives = const [],
  });

  factory BrowserState.initial() =>
      const BrowserState(currentPath: '', entries: [], isRootView: true);

  /// 经过筛选和排序后的条目
  List<FileEntry> get filteredEntries {
    var result = entries.where((e) {
      if (filterQuery.isEmpty) return true;
      return e.name.toLowerCase().contains(filterQuery.toLowerCase());
    }).toList();

    result.sort((a, b) {
      // 目录始终优先
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      int cmp;
      switch (sortField) {
        case SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortField.type:
          cmp = a.type.index.compareTo(b.type.index);
      }
      return sortOrder == SortOrder.asc ? cmp : -cmp;
    });

    return result;
  }

  BrowserState copyWith({
    String? currentPath,
    List<FileEntry>? entries,
    String? highlightedPath,
    bool clearHighlightedPath = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? isRootView,
    ViewMode? viewMode,
    SortField? sortField,
    SortOrder? sortOrder,
    String? filterQuery,
    List<NetworkDriveEntry>? networkDrives,
  }) {
    return BrowserState(
      currentPath: currentPath ?? this.currentPath,
      entries: entries ?? this.entries,
      highlightedPath: clearHighlightedPath
          ? null
          : (highlightedPath ?? this.highlightedPath),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isRootView: isRootView ?? this.isRootView,
      viewMode: viewMode ?? this.viewMode,
      sortField: sortField ?? this.sortField,
      sortOrder: sortOrder ?? this.sortOrder,
      filterQuery: filterQuery ?? this.filterQuery,
      networkDrives: networkDrives ?? this.networkDrives,
    );
  }
}
