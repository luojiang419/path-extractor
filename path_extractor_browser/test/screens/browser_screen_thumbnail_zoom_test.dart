import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/browser_state.dart';
import 'package:path_extractor_browser/models/file_entry.dart';
import 'package:path_extractor_browser/providers/browser_provider.dart';
import 'package:path_extractor_browser/providers/infinite_list_provider.dart';
import 'package:path_extractor_browser/providers/thumbnail_view_settings_provider.dart';
import 'package:path_extractor_browser/screens/browser_screen.dart';
import 'package:path_extractor_browser/services/file_system_service.dart';
import 'package:path_extractor_browser/services/network_drive_service.dart';
import 'package:path_extractor_browser/services/path_service.dart';
import 'package:path_extractor_browser/services/thumbnail_view_settings_service.dart';

void main() {
  late Directory contentDir;
  late Directory settingsDir;

  setUp(() async {
    contentDir = await Directory.systemTemp.createTemp(
      'browser_thumbnail_content_',
    );
    settingsDir = await Directory.systemTemp.createTemp(
      'browser_thumbnail_settings_',
    );

    for (var i = 0; i < 40; i++) {
      final file = File(
        '${contentDir.path}${Platform.pathSeparator}file_$i.txt',
      );
      await file.writeAsString('file-$i');
    }
  });

  tearDown(() async {
    if (await contentDir.exists()) {
      await contentDir.delete(recursive: true);
    }
    if (await settingsDir.exists()) {
      await settingsDir.delete(recursive: true);
    }
  });

  testWidgets('缩略图视图显示尺寸滑杆，列表视图隐藏', (tester) async {
    final container = await _pumpBrowserScreen(tester, settingsDir);

    await container.read(browserProvider.notifier).navigateTo(contentDir.path);
    await _pumpUi(tester);

    expect(find.byKey(const Key('thumbnail-size-controls')), findsOneWidget);

    container.read(browserProvider.notifier).setViewMode(ViewMode.list);
    await _pumpUi(tester);

    expect(find.byKey(const Key('thumbnail-size-controls')), findsNothing);
  });

  testWidgets('拖动滑杆后普通浏览和无限模式共用同一缩略图尺寸', (tester) async {
    final container = await _pumpBrowserScreen(tester, settingsDir);
    final firstFilePath =
        '${contentDir.path}${Platform.pathSeparator}file_0.txt';

    await container.read(browserProvider.notifier).navigateTo(contentDir.path);
    await _pumpUi(tester);

    final initialSize = tester.getSize(
      find.byKey(Key('grid-item-$firstFilePath')),
    );

    await tester.drag(
      find.byKey(const Key('thumbnail-size-slider')),
      const Offset(240, 0),
    );
    await _pumpUi(tester);

    final resizedSize = tester.getSize(
      find.byKey(Key('grid-item-$firstFilePath')),
    );
    expect(resizedSize.width, greaterThan(initialSize.width));

    container.read(infiniteListProvider.notifier).enterFromDrop([
      contentDir.path,
    ]);
    await _pumpUi(tester);

    final infiniteRootSize = tester.getSize(
      find.byKey(Key('grid-item-${contentDir.path}')),
    );
    expect(infiniteRootSize.width, closeTo(resizedSize.width, 1.0));
    expect(find.byKey(const Key('thumbnail-size-controls')), findsOneWidget);
  });

  testWidgets('普通滚轮滚动列表，Ctrl 加滚轮缩放缩略图', (tester) async {
    final container = await _pumpBrowserScreen(tester, settingsDir);

    await container.read(browserProvider.notifier).navigateTo(contentDir.path);
    await _pumpUi(tester);

    final scrollableState = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('thumbnail-grid-view')),
        matching: find.byType(Scrollable),
      ),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final hoverLocation = tester.getCenter(
      find.byKey(const Key('thumbnail-grid-view')),
    );

    await tester.sendEventToBinding(pointer.hover(hoverLocation));
    await tester.pump();

    final sizeBefore = _thumbnailSizeValue(tester);
    final scrollOffsetBefore = scrollableState.position.pixels;

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 240)));
    await _pumpUi(tester);

    final sizeAfterRegularScroll = _thumbnailSizeValue(tester);
    final scrollOffsetAfterRegularScroll = scrollableState.position.pixels;
    expect(sizeAfterRegularScroll, sizeBefore);
    expect(scrollOffsetAfterRegularScroll, greaterThan(scrollOffsetBefore));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await _pumpUi(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    final sizeAfterCtrlScroll = _thumbnailSizeValue(tester);
    final scrollOffsetAfterCtrlScroll = scrollableState.position.pixels;
    expect(sizeAfterCtrlScroll, greaterThan(sizeAfterRegularScroll));
    expect(
      scrollOffsetAfterCtrlScroll,
      closeTo(scrollOffsetAfterRegularScroll, 0.1),
    );
  });
}

Future<ProviderContainer> _pumpBrowserScreen(
  WidgetTester tester,
  Directory settingsDir,
) async {
  final container = ProviderContainer(
    overrides: [
      browserProvider.overrideWith((ref) => _TestBrowserNotifier()),
      infiniteListProvider.overrideWith(
        (ref) =>
            InfiniteListNotifier(_TestFileSystemService(), PathServiceImpl()),
      ),
      thumbnailViewSettingsStoreProvider.overrideWithValue(
        FileThumbnailViewSettingsStore(
          directoryProvider: () async => settingsDir,
        ),
      ),
    ],
  );

  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
    ),
  );
  await _pumpUi(tester);
  return container;
}

int _thumbnailSizeValue(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.byKey(const Key('thumbnail-size-value')),
  );
  return int.parse(text.data!);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

class _TestFileSystemService implements FileSystemService {
  @override
  Future<List<FileEntry>> getDrives() async => const [];

  @override
  Future<String> getHomeDirectory() async => '';

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final entities = Directory(path).listSync();
    final entries = entities.map((entity) {
      return FileEntry.fromPath(entity.path, isDirectory: entity is Directory);
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

class _TestNetworkDriveService extends NetworkDriveService {
  @override
  Future<void> add(NetworkDriveEntry entry) async {}

  @override
  Future<List<NetworkDriveEntry>> loadAll() async => const [];

  @override
  Future<void> remove(String address) async {}
}

class _TestBrowserNotifier extends BrowserNotifier {
  _TestBrowserNotifier()
    : _fileSystemService = _TestFileSystemService(),
      super(
        _TestFileSystemService(),
        PathServiceImpl(),
        _TestNetworkDriveService(),
      );

  final _TestFileSystemService _fileSystemService;

  @override
  Future<void> navigateToRoot() async {
    state = state.copyWith(
      currentPath: '',
      entries: const [],
      clearHighlightedPath: true,
      isLoading: false,
      isRootView: true,
      filterQuery: '',
      networkDrives: const [],
      clearError: true,
    );
  }

  @override
  Future<void> navigateTo(String path) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entries = await _fileSystemService.listDirectory(path);
      state = state.copyWith(
        currentPath: path,
        entries: entries,
        clearHighlightedPath: true,
        isLoading: false,
        isRootView: false,
        filterQuery: '',
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(errorMessage: error.toString(), isLoading: false);
    }
  }
}
