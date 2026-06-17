import 'browser_state.dart';
import 'file_entry.dart';

class InfiniteListState {
  final bool isActive;
  final List<FileEntry> rootEntries;
  final List<FileEntry> currentEntries;
  final String currentPath;
  final String? anchorPath;
  final String? anchorLabel;
  final String? highlightedPath;
  final bool isRootView;
  final bool isLoading;
  final String? errorMessage;
  final ViewMode viewMode;
  final SortField sortField;
  final SortOrder sortOrder;
  final String filterQuery;
  final String? lastCopiedPath;

  const InfiniteListState({
    this.isActive = false,
    this.rootEntries = const [],
    this.currentEntries = const [],
    this.currentPath = '',
    this.anchorPath,
    this.anchorLabel,
    this.highlightedPath,
    this.isRootView = true,
    this.isLoading = false,
    this.errorMessage,
    this.viewMode = ViewMode.grid,
    this.sortField = SortField.name,
    this.sortOrder = SortOrder.asc,
    this.filterQuery = '',
    this.lastCopiedPath,
  });

  factory InfiniteListState.initial() => const InfiniteListState();

  List<FileEntry> get filteredEntries {
    final query = filterQuery.toLowerCase();
    final result = currentEntries.where((entry) {
      if (query.isEmpty) return true;
      return entry.name.toLowerCase().contains(query);
    }).toList();

    result.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      final int cmp;
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

  InfiniteListState copyWith({
    bool? isActive,
    List<FileEntry>? rootEntries,
    List<FileEntry>? currentEntries,
    String? currentPath,
    String? anchorPath,
    String? anchorLabel,
    bool clearAnchor = false,
    String? highlightedPath,
    bool clearHighlightedPath = false,
    bool? isRootView,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    ViewMode? viewMode,
    SortField? sortField,
    SortOrder? sortOrder,
    String? filterQuery,
    String? lastCopiedPath,
    bool clearLastCopied = false,
  }) {
    return InfiniteListState(
      isActive: isActive ?? this.isActive,
      rootEntries: rootEntries ?? this.rootEntries,
      currentEntries: currentEntries ?? this.currentEntries,
      currentPath: currentPath ?? this.currentPath,
      anchorPath: clearAnchor ? null : (anchorPath ?? this.anchorPath),
      anchorLabel: clearAnchor ? null : (anchorLabel ?? this.anchorLabel),
      highlightedPath: clearHighlightedPath
          ? null
          : (highlightedPath ?? this.highlightedPath),
      isRootView: isRootView ?? this.isRootView,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      viewMode: viewMode ?? this.viewMode,
      sortField: sortField ?? this.sortField,
      sortOrder: sortOrder ?? this.sortOrder,
      filterQuery: filterQuery ?? this.filterQuery,
      lastCopiedPath: clearLastCopied
          ? null
          : (lastCopiedPath ?? this.lastCopiedPath),
    );
  }
}
