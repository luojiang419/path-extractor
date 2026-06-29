import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/browser_state.dart';
import '../models/file_entry.dart';
import '../models/infinite_list_state.dart';
import '../providers/app_provider.dart';
import '../providers/browser_provider.dart';
import '../providers/infinite_list_provider.dart';
import '../services/clipboard_service.dart';
import '../services/network_drive_service.dart';
import '../services/path_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_hover_surface.dart';
import '../widgets/breadcrumb_nav.dart';
import '../widgets/drop_zone.dart';
import '../widgets/file_list_item.dart' show FileListItem, fileEntryIconData;
import '../widgets/glass_panel.dart';
import '../widgets/media_thumbnail.dart';
import '../widgets/network_drive_dialog.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  final _searchController = TextEditingController();
  final _pathController = TextEditingController();
  final _pathFocusNode = FocusNode();
  final _filterFocusNode = FocusNode();
  final _pathService = PathServiceImpl();
  bool? _lastPathModeIsInfinite;
  String _currentDisplayPath = '';

  @override
  void initState() {
    super.initState();
    _pathFocusNode.addListener(() {
      if (_pathFocusNode.hasFocus) return;
      _restorePathController();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pathController.dispose();
    _pathFocusNode.dispose();
    _filterFocusNode.dispose();
    super.dispose();
  }

  String _truncatePath(String path) {
    if (path.length <= 50) return path;
    return '...${path.substring(path.length - 50)}';
  }

  @override
  Widget build(BuildContext context) {
    final browserState = ref.watch(browserProvider);
    final browserNotifier = ref.read(browserProvider.notifier);
    final infiniteState = ref.watch(infiniteListProvider);
    final infiniteNotifier = ref.read(infiniteListProvider.notifier);
    final isInfiniteMode = infiniteState.isActive;
    final activeFilter = isInfiniteMode
        ? infiniteState.filterQuery
        : browserState.filterQuery;
    final activeRootView = isInfiniteMode
        ? infiniteState.isRootView
        : browserState.isRootView;
    final activeDisplayPath = activeRootView
        ? ''
        : (isInfiniteMode
              ? infiniteState.currentPath
              : browserState.currentPath);

    _syncSearchController(activeFilter);
    _syncPathController(activeDisplayPath, isInfiniteMode);

    final pathSegments = isInfiniteMode
        ? _infinitePathSegments(infiniteState)
        : _pathService.splitSegments(browserState.currentPath);
    final activeViewMode = isInfiniteMode
        ? infiniteState.viewMode
        : browserState.viewMode;
    final content = isInfiniteMode
        ? _buildInfiniteContent(context, infiniteState, infiniteNotifier)
        : _buildBrowserContent(context, browserState, browserNotifier);
    final contentKey = ValueKey(
      '${isInfiniteMode ? 'infinite' : 'browser'}-'
      '${activeRootView ? 'root' : activeDisplayPath}-${activeViewMode.name}',
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!infiniteState.isActive) return;
          infiniteNotifier.exitAndClear();
          _searchController.clear();
          ref.read(toastProvider.notifier).showSuccess('已退出无限模式');
        },
        const SingleActivator(LogicalKeyboardKey.backspace): () {
          if (_isTextInputFocused()) return;
          if (activeRootView) return;
          if (isInfiniteMode) {
            infiniteNotifier.navigateUp();
          } else {
            browserNotifier.navigateUp();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: DropZone(
          onFilesDropped: (paths) {
            if (isInfiniteMode) {
              infiniteNotifier.appendDroppedEntries(paths);
            } else {
              infiniteNotifier.enterFromDrop(paths);
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              children: [
                GlassPanel(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  borderRadius: BorderRadius.circular(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NavBar(
                        pathSegments: pathSegments,
                        isRootView: activeRootView,
                        canGoUp: !activeRootView,
                        onBack: () {
                          if (isInfiniteMode) {
                            infiniteNotifier.navigateUp();
                          } else {
                            browserNotifier.navigateUp();
                          }
                        },
                        onHome: () {
                          if (isInfiniteMode) {
                            infiniteNotifier.navigateToRoot();
                          } else {
                            browserNotifier.navigateToRoot();
                          }
                        },
                        onSegmentTap: (index) {
                          if (isInfiniteMode) {
                            infiniteNotifier.navigateToSegment(index);
                          } else {
                            browserNotifier.navigateToSegment(index);
                          }
                        },
                        onAddNetwork: () =>
                            _showAddNetworkDialog(context, browserNotifier),
                        isInfiniteMode: isInfiniteMode,
                      ),
                      const SizedBox(height: 6),
                      _Toolbar(
                        pathController: _pathController,
                        pathFocusNode: _pathFocusNode,
                        filterFocusNode: _filterFocusNode,
                        filterQuery: activeFilter,
                        viewMode: activeViewMode,
                        sortField: isInfiniteMode
                            ? infiniteState.sortField
                            : browserState.sortField,
                        sortOrder: isInfiniteMode
                            ? infiniteState.sortOrder
                            : browserState.sortOrder,
                        searchController: _searchController,
                        onPathSubmitted: (value) => _submitPath(
                          value: value,
                          isInfiniteMode: isInfiniteMode,
                          browserNotifier: browserNotifier,
                          infiniteNotifier: infiniteNotifier,
                        ),
                        onFilterChanged: isInfiniteMode
                            ? infiniteNotifier.setFilter
                            : browserNotifier.setFilter,
                        onSortField: isInfiniteMode
                            ? infiniteNotifier.setSortField
                            : browserNotifier.setSortField,
                        onViewMode: isInfiniteMode
                            ? infiniteNotifier.setViewMode
                            : browserNotifier.setViewMode,
                        isInfiniteMode: isInfiniteMode,
                        entryCount: infiniteState.rootEntries.length,
                        onPickFiles: isInfiniteMode
                            ? () => _pickFiles(context, infiniteNotifier)
                            : null,
                        onPickFolder: isInfiniteMode
                            ? () => _pickFolder(context, infiniteNotifier)
                            : null,
                        onClearAll: isInfiniteMode
                            ? () => _showClearDialog(context, infiniteNotifier)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(18),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AnimatedSwitcher(
                        duration: AppMotion.normal,
                        switchInCurve: AppMotion.standard,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offset =
                              Tween<Offset>(
                                begin: const Offset(0, 0.018),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: AppMotion.standard,
                                ),
                              );
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(key: contentKey, child: content),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncSearchController(String filter) {
    if (_searchController.text == filter) return;
    _searchController.value = TextEditingValue(
      text: filter,
      selection: TextSelection.collapsed(offset: filter.length),
    );
  }

  void _syncPathController(String path, bool isInfiniteMode) {
    _currentDisplayPath = path;
    final modeChanged = _lastPathModeIsInfinite != isInfiniteMode;
    _lastPathModeIsInfinite = isInfiniteMode;

    if (_pathFocusNode.hasFocus && !modeChanged) {
      return;
    }
    if (_pathController.text == path) return;
    _pathController.value = TextEditingValue(
      text: path,
      selection: TextSelection.collapsed(offset: path.length),
    );
  }

  void _restorePathController() {
    if (_pathController.text == _currentDisplayPath) return;
    _pathController.value = TextEditingValue(
      text: _currentDisplayPath,
      selection: TextSelection.collapsed(offset: _currentDisplayPath.length),
    );
  }

  bool _isTextInputFocused() {
    if (_pathFocusNode.hasFocus || _filterFocusNode.hasFocus) {
      return true;
    }

    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _submitPath({
    required String value,
    required bool isInfiniteMode,
    required BrowserNotifier browserNotifier,
    required InfiniteListNotifier infiniteNotifier,
  }) async {
    try {
      if (isInfiniteMode) {
        final result = await infiniteNotifier.navigateToSubmittedPath(value);
        if (!mounted) return;

        switch (result) {
          case InfinitePathSubmitResult.handledInInfinite:
            return;
          case InfinitePathSubmitResult.switchToBrowser:
            infiniteNotifier.exitAndClear();
            await _openBrowserSubmittedPath(value, browserNotifier);
            return;
          case InfinitePathSubmitResult.invalid:
            _showPathErrorToast();
            return;
        }
      }

      await _openBrowserSubmittedPath(value, browserNotifier);
    } finally {
      if (mounted) {
        _pathFocusNode.unfocus();
      }
    }
  }

  Future<void> _openBrowserSubmittedPath(
    String value,
    BrowserNotifier browserNotifier, {
    NetworkDriveEntry? credentials,
  }) async {
    final result = await browserNotifier.navigateToSubmittedPath(
      value,
      credentials: credentials,
    );
    if (!mounted) return;

    switch (result.status) {
      case BrowserNavigationStatus.navigated:
        return;
      case BrowserNavigationStatus.invalid:
        _showPathErrorToast(result.message);
        return;
      case BrowserNavigationStatus.authenticationRequired:
        final credentialEntry = await showNetworkCredentialDialog(
          context,
          address: result.authScope ?? value,
          helperText: _buildNetworkHelperText(result.message),
        );
        if (!mounted || credentialEntry == null) return;
        await _openBrowserSubmittedPath(
          value,
          browserNotifier,
          credentials: credentialEntry,
        );
        return;
    }
  }

  String _buildNetworkHelperText(String? message) {
    const defaultMessage = '此网络位置需要账号密码才能访问。';
    if (message == null || message.trim().isEmpty) {
      return defaultMessage;
    }
    return '$defaultMessage\n${message.trim()}';
  }

  void _showPathErrorToast([String? message]) {
    final text = message == null || message.trim().isEmpty
        ? '路径无效或无法访问'
        : message.trim();
    ref.read(toastProvider.notifier).showError(text);
  }

  List<String> _infinitePathSegments(InfiniteListState state) {
    if (state.isRootView || state.currentPath.isEmpty) {
      return const [];
    }

    final anchorPath = state.anchorPath;
    final anchorLabel = state.anchorLabel;
    if (anchorPath == null || anchorLabel == null) {
      return _pathService.splitSegments(state.currentPath);
    }

    final anchorSegments = _pathService.splitSegments(anchorPath);
    final currentSegments = _pathService.splitSegments(state.currentPath);
    return [anchorLabel, ...currentSegments.skip(anchorSegments.length)];
  }

  Future<void> _pickFiles(
    BuildContext context,
    InfiniteListNotifier notifier,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null) return;
    final paths = result.paths.whereType<String>().toList();
    notifier.appendDroppedEntries(paths);
  }

  Future<void> _pickFolder(
    BuildContext context,
    InfiniteListNotifier notifier,
  ) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    notifier.appendDroppedEntries([result]);
  }

  Future<void> _showAddNetworkDialog(
    BuildContext context,
    BrowserNotifier notifier,
  ) async {
    final entry = await showNetworkDriveDialog(context);
    if (entry == null) return;

    await notifier.addNetworkDrive(entry);
    if (!mounted) return;
    ref.read(toastProvider.notifier).showSuccess('已添加网络位置：${entry.label}');
  }

  Widget _buildBrowserContent(
    BuildContext context,
    BrowserState state,
    BrowserNotifier notifier,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return _ErrorView(message: state.errorMessage!);
    }

    final entries = state.filteredEntries;
    if (state.isRootView) {
      return _RootView(
        drives: entries,
        networkDrives: state.networkDrives,
        onDriveTap: (entry) => _onBrowserEntryTap(entry, notifier),
        onDriveCopy: _copyPath,
        onNetworkTap: (entry) => _openBrowserSubmittedPath(
          entry.address,
          notifier,
          credentials: entry.username != null && entry.password != null
              ? entry
              : null,
        ),
        onNetworkCopy: (entry) => _copyPathString(entry.address),
        onNetworkRemove: (entry) => notifier.removeNetworkDrive(entry.address),
        viewMode: state.viewMode,
      );
    }

    if (entries.isEmpty) {
      return _EmptyFolderView(filterQuery: state.filterQuery);
    }

    if (state.viewMode == ViewMode.grid) {
      return _GridView(
        entries: entries,
        highlightedPath: state.highlightedPath,
        onTap: (entry) => _onBrowserEntryTap(entry, notifier),
        onCopyPath: _copyPath,
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return FileListItem(
          entry: entry,
          isHighlighted: entry.path == state.highlightedPath,
          onTap: () => _onBrowserEntryTap(entry, notifier),
          onCopyPath: () => _copyPath(entry),
        );
      },
    );
  }

  Widget _buildInfiniteContent(
    BuildContext context,
    InfiniteListState state,
    InfiniteListNotifier notifier,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return _ErrorView(message: state.errorMessage!);
    }

    final entries = state.filteredEntries;
    if (entries.isEmpty) {
      if (state.isRootView) {
        return const _InfiniteEmptyView();
      }
      return _EmptyFolderView(filterQuery: state.filterQuery);
    }

    if (state.viewMode == ViewMode.grid) {
      return _GridView(
        entries: entries,
        highlightedPath: state.highlightedPath,
        onTap: (entry) => _onInfiniteEntryTap(entry, notifier),
        onCopyPath: (entry) => _copyInfinitePath(entry, notifier),
        onDelete: state.isRootView ? notifier.removeEntry : null,
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return FileListItem(
          entry: entry,
          isHighlighted: entry.path == state.highlightedPath,
          onTap: () => _onInfiniteEntryTap(entry, notifier),
          onCopyPath: () => _copyInfinitePath(entry, notifier),
          onDelete: state.isRootView
              ? () => notifier.removeEntry(entry.path)
              : null,
        );
      },
    );
  }

  Future<void> _onBrowserEntryTap(
    FileEntry entry,
    BrowserNotifier notifier,
  ) async {
    if (entry.isDirectory) {
      await notifier.navigateTo(entry.path);
      return;
    }
    notifier.clearHighlightedPath();
    await _copyPath(entry);
  }

  Future<void> _onInfiniteEntryTap(
    FileEntry entry,
    InfiniteListNotifier notifier,
  ) async {
    if (entry.isDirectory) {
      await notifier.navigateTo(entry.path);
      return;
    }
    await _copyInfinitePath(entry, notifier);
  }

  Future<void> _copyInfinitePath(
    FileEntry entry,
    InfiniteListNotifier notifier,
  ) async {
    final copied = await _copyPath(entry);
    if (copied) {
      notifier.setLastCopied(entry.path);
    }
  }

  Future<bool> _copyPath(FileEntry entry) => _copyPathString(entry.path);

  Future<bool> _copyPathString(String path) async {
    try {
      await ClipboardServiceImpl().copyToClipboard(path);
      if (mounted) {
        ref
            .read(toastProvider.notifier)
            .showSuccess('路径已复制: ${_truncatePath(path)}');
      }
      return true;
    } catch (_) {
      if (mounted) {
        ref.read(toastProvider.notifier).showError('复制失败，请重试');
      }
      return false;
    }
  }

  void _showClearDialog(BuildContext context, InfiniteListNotifier notifier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空列表'),
        content: const Text('确定要清空已拖入的所有条目吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              notifier.clearAll();
              Navigator.of(ctx).pop();
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.pathSegments,
    required this.isRootView,
    required this.canGoUp,
    required this.onBack,
    required this.onHome,
    required this.onSegmentTap,
    required this.onAddNetwork,
    required this.isInfiniteMode,
  });

  final List<String> pathSegments;
  final bool isRootView;
  final bool canGoUp;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final void Function(int) onSegmentTap;
  final VoidCallback onAddNetwork;
  final bool isInfiniteMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回上一级',
            onPressed: canGoUp ? onBack : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: Icon(
                isInfiniteMode ? Icons.inventory_2_outlined : Icons.storage,
                key: ValueKey(isInfiniteMode),
              ),
            ),
            tooltip: isInfiniteMode ? '已拖入项目根列表' : '所有磁盘',
            onPressed: isRootView ? null : onHome,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              switchInCurve: AppMotion.standard,
              child: Align(
                key: ValueKey(
                  isRootView ? 'root-$isInfiniteMode' : pathSegments.join('/'),
                ),
                alignment: Alignment.centerLeft,
                child: isRootView
                    ? Text(
                        isInfiniteMode ? '已拖入项目' : '我的电脑',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : BreadcrumbNav(
                        pathSegments: pathSegments,
                        onTap: onSegmentTap,
                      ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotion.normal,
            child: isInfiniteMode
                ? Container(
                    key: const ValueKey('infinite-mode-chip'),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '按 Esc 退出',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  )
                : TextButton.icon(
                    key: const ValueKey('add-network-button'),
                    onPressed: onAddNetwork,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加网络位置'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.pathController,
    required this.pathFocusNode,
    required this.filterFocusNode,
    required this.filterQuery,
    required this.viewMode,
    required this.sortField,
    required this.sortOrder,
    required this.searchController,
    required this.onPathSubmitted,
    required this.onFilterChanged,
    required this.onSortField,
    required this.onViewMode,
    required this.isInfiniteMode,
    required this.entryCount,
    this.onPickFiles,
    this.onPickFolder,
    this.onClearAll,
  });

  final TextEditingController pathController;
  final FocusNode pathFocusNode;
  final FocusNode filterFocusNode;
  final String filterQuery;
  final ViewMode viewMode;
  final SortField sortField;
  final SortOrder sortOrder;
  final TextEditingController searchController;
  final void Function(String) onPathSubmitted;
  final void Function(String) onFilterChanged;
  final void Function(SortField) onSortField;
  final void Function(ViewMode) onViewMode;
  final bool isInfiniteMode;
  final int entryCount;
  final VoidCallback? onPickFiles;
  final VoidCallback? onPickFolder;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedSize(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.normal,
              switchInCurve: AppMotion.standard,
              child: isInfiniteMode
                  ? Padding(
                      key: const ValueKey('infinite-actions'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildInfiniteActions(context),
                    )
                  : const SizedBox.shrink(key: ValueKey('browser-actions')),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                return _buildResponsiveControls(context, constraints);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfiniteActions(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed: onPickFiles,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加文件'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          FilledButton.tonalIcon(
            onPressed: onPickFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text('添加文件夹'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          Text(
            '共 $entryCount 个根条目',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(onPressed: onClearAll, child: const Text('清空列表')),
        ],
      ),
    );
  }

  Widget _buildResponsiveControls(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final compact = constraints.maxWidth < 760;
    final pathField = _buildPathField();
    final filterField = _buildFilterField();
    final controls = _buildViewControls();

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pathField,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: filterField),
              const SizedBox(width: 8),
              Flexible(child: FittedBox(child: controls)),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 5, child: pathField),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: filterField),
        const SizedBox(width: 8),
        controls,
      ],
    );
  }

  Widget _buildPathField() {
    return SizedBox(
      height: 38,
      child: TextField(
        key: const Key('path-input'),
        controller: pathController,
        focusNode: pathFocusNode,
        onSubmitted: onPathSubmitted,
        textInputAction: TextInputAction.go,
        decoration: _inputDecoration(
          hintText: '输入路径后回车',
          prefixIcon: Icons.drive_folder_upload,
        ),
      ),
    );
  }

  Widget _buildFilterField() {
    return SizedBox(
      height: 38,
      child: TextField(
        key: const Key('filter-input'),
        controller: searchController,
        focusNode: filterFocusNode,
        onChanged: onFilterChanged,
        decoration: _inputDecoration(
          hintText: '筛选文件名...',
          prefixIcon: Icons.search,
          suffixIcon: filterQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    searchController.clear();
                    onFilterChanged('');
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildViewControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SortButton(
          sortField: sortField,
          sortOrder: sortOrder,
          onSortField: onSortField,
        ),
        const SizedBox(width: 4),
        SegmentedButton<ViewMode>(
          segments: const [
            ButtonSegment(
              value: ViewMode.list,
              icon: Icon(Icons.view_list, size: 18),
              tooltip: '列表视图',
            ),
            ButtonSegment(
              value: ViewMode.grid,
              icon: Icon(Icons.grid_view, size: 18),
              tooltip: '缩略图视图',
            ),
          ],
          selected: {viewMode},
          onSelectionChanged: (selection) => onViewMode(selection.first),
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(prefixIcon, size: 18),
      suffixIcon: suffixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 40),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sortField,
    required this.sortOrder,
    required this.onSortField,
  });

  final SortField sortField;
  final SortOrder sortOrder;
  final void Function(SortField) onSortField;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      tooltip: '排序方式',
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 18),
          Icon(
            sortOrder == SortOrder.asc
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            size: 14,
          ),
        ],
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: SortField.name,
          child: Row(
            children: [
              Icon(sortField == SortField.name ? Icons.check : null, size: 16),
              const SizedBox(width: 8),
              const Text('按名称'),
            ],
          ),
        ),
        PopupMenuItem(
          value: SortField.type,
          child: Row(
            children: [
              Icon(sortField == SortField.type ? Icons.check : null, size: 16),
              const SizedBox(width: 8),
              const Text('按类型'),
            ],
          ),
        ),
      ],
      onSelected: onSortField,
    );
  }
}

class _GridView extends StatelessWidget {
  const _GridView({
    required this.entries,
    required this.onTap,
    required this.onCopyPath,
    this.highlightedPath,
    this.onDelete,
  });

  final List<FileEntry> entries;
  final String? highlightedPath;
  final void Function(FileEntry) onTap;
  final void Function(FileEntry) onCopyPath;
  final void Function(String path)? onDelete;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _GridItem(
          entry: entry,
          isHighlighted: entry.path == highlightedPath,
          onTap: () => onTap(entry),
          onCopyPath: () => onCopyPath(entry),
          onDelete: onDelete == null ? null : () => onDelete!(entry.path),
        );
      },
    );
  }
}

class _GridItem extends StatefulWidget {
  const _GridItem({
    required this.entry,
    required this.onTap,
    required this.onCopyPath,
    this.onDelete,
    this.isHighlighted = false,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onCopyPath;
  final VoidCallback? onDelete;
  final bool isHighlighted;

  @override
  State<_GridItem> createState() => _GridItemState();
}

class _GridItemState extends State<_GridItem> {
  void _showContextMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 8),
              const Text('复制路径'),
            ],
          ),
        ),
        if (widget.entry.isDirectory)
          PopupMenuItem(
            value: 'open',
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 16),
                const SizedBox(width: 8),
                const Text('打开文件夹'),
              ],
            ),
          ),
        if (widget.onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline, size: 16),
                const SizedBox(width: 8),
                const Text('从列表移除'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'copy') widget.onCopyPath();
      if (value == 'open') widget.onTap();
      if (value == 'delete') widget.onDelete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color) = fileEntryIconData(widget.entry.type);
    final preview = isMediaFileEntry(widget.entry)
        ? MediaThumbnail(
            entry: widget.entry,
            width: 72,
            height: 72,
            borderRadius: BorderRadius.circular(12),
            fallbackIcon: icon,
            fallbackColor: color,
            fallbackIconSize: 32,
          )
        : Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, color: color, size: 40),
          );

    return AnimatedHoverSurface(
      isHighlighted: widget.isHighlighted,
      onTap: widget.onTap,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      padding: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(14),
      builder: (context, isHovered) {
        return Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 72, height: 72, child: Center(child: preview)),
                const SizedBox(height: 8),
                AnimatedDefaultTextStyle(
                  duration: AppMotion.fast,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontSize: 11,
                    fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  child: Text(
                    widget.entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: isHovered ? 1.0 : 0.0,
                duration: AppMotion.fast,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GridQuickAction(
                      tooltip: '复制路径',
                      icon: Icons.copy,
                      onTap: widget.onCopyPath,
                    ),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 4),
                      _GridQuickAction(
                        tooltip: '移除',
                        icon: Icons.close,
                        onTap: widget.onDelete,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GridQuickAction extends StatelessWidget {
  const _GridQuickAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.34),
            ),
          ),
          child: Icon(icon, size: 14),
        ),
      ),
    );
  }
}

class _RootView extends StatelessWidget {
  const _RootView({
    required this.drives,
    required this.networkDrives,
    required this.onDriveTap,
    required this.onDriveCopy,
    required this.onNetworkTap,
    required this.onNetworkCopy,
    required this.onNetworkRemove,
    required this.viewMode,
  });

  final List<FileEntry> drives;
  final List<NetworkDriveEntry> networkDrives;
  final void Function(FileEntry) onDriveTap;
  final void Function(FileEntry) onDriveCopy;
  final void Function(NetworkDriveEntry) onNetworkTap;
  final void Function(NetworkDriveEntry) onNetworkCopy;
  final void Function(NetworkDriveEntry) onNetworkRemove;
  final ViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '本地磁盘',
            style: textTheme.labelLarge?.copyWith(color: colorScheme.primary),
          ),
        ),
        viewMode == ViewMode.grid
            ? _driveGrid(drives, onDriveTap, onDriveCopy)
            : _driveList(drives, onDriveTap, onDriveCopy),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '网络位置',
            style: textTheme.labelLarge?.copyWith(color: colorScheme.primary),
          ),
        ),
        if (networkDrives.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              '暂无网络位置，点击"添加网络位置"添加',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          )
        else
          ...networkDrives.map(
            (entry) => _NetworkDriveItem(
              entry: entry,
              onTap: () => onNetworkTap(entry),
              onCopy: () => onNetworkCopy(entry),
              onRemove: () => onNetworkRemove(entry),
            ),
          ),
      ],
    );
  }

  Widget _driveGrid(
    List<FileEntry> entries,
    void Function(FileEntry) onTap,
    void Function(FileEntry) onCopy,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries
          .map(
            (entry) => SizedBox(
              width: 110,
              height: 100,
              child: _GridItem(
                entry: entry,
                onTap: () => onTap(entry),
                onCopyPath: () => onCopy(entry),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _driveList(
    List<FileEntry> entries,
    void Function(FileEntry) onTap,
    void Function(FileEntry) onCopy,
  ) {
    return Column(
      children: entries
          .map(
            (entry) => FileListItem(
              entry: entry,
              onTap: () => onTap(entry),
              onCopyPath: () => onCopy(entry),
            ),
          )
          .toList(),
    );
  }
}

class _NetworkDriveItem extends StatefulWidget {
  const _NetworkDriveItem({
    required this.entry,
    required this.onTap,
    required this.onCopy,
    required this.onRemove,
  });

  final NetworkDriveEntry entry;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onRemove;

  @override
  State<_NetworkDriveItem> createState() => _NetworkDriveItemState();
}

class _NetworkDriveItemState extends State<_NetworkDriveItem> {
  void _showContextMenu(BuildContext context, Offset pos) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      pos & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 8),
              const Text('复制路径'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 16),
              const SizedBox(width: 8),
              const Text('移除'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') widget.onCopy();
      if (value == 'remove') widget.onRemove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedHoverSurface(
      onTap: widget.onTap,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      padding: const EdgeInsets.only(left: 14, right: 4, top: 8, bottom: 8),
      borderRadius: BorderRadius.circular(12),
      hoverColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.40),
      builder: (context, isHovered) {
        return Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: Icon(Icons.lan, color: colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.entry.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.entry.address,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.entry.username != null)
                    Text(
                      '用户：${widget.entry.username}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: isHovered ? 1.0 : 0.0,
              duration: AppMotion.fast,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: '复制路径',
                    child: IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: widget.onCopy,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Tooltip(
                    message: '移除',
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: widget.onRemove,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfiniteEmptyView extends StatelessWidget {
  const _InfiniteEmptyView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: AppMotion.slow,
        curve: AppMotion.standard,
        builder: (context, value, child) {
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(scale: value, child: child),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.42),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 42,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text('将文件或文件夹拖拽到此处', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('或使用上方按钮添加文件/文件夹', style: textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '点击文件夹可继续浏览，按 Esc 返回普通浏览器',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFolderView extends StatelessWidget {
  const _EmptyFolderView({required this.filterQuery});

  final String filterQuery;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = filterQuery.isEmpty ? '此文件夹为空' : '没有匹配的文件';

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: AppMotion.slow,
        curve: AppMotion.standard,
        builder: (context, value, child) {
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(scale: value, child: child),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filterQuery.isEmpty
                  ? Icons.folder_open_outlined
                  : Icons.manage_search,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: AppMotion.slow,
        curve: AppMotion.standard,
        builder: (context, value, child) {
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(scale: value, child: child),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.72),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 34,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
