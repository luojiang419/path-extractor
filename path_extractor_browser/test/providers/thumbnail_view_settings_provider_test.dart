import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/thumbnail_view_settings.dart';
import 'package:path_extractor_browser/providers/thumbnail_view_settings_provider.dart';
import 'package:path_extractor_browser/services/thumbnail_view_settings_service.dart';

void main() {
  late Directory settingsDir;
  late FileThumbnailViewSettingsStore store;

  setUp(() async {
    settingsDir = await Directory.systemTemp.createTemp(
      'thumbnail_view_settings_',
    );
    store = FileThumbnailViewSettingsStore(
      directoryProvider: () async => settingsDir,
    );
  });

  tearDown(() async {
    if (await settingsDir.exists()) {
      await settingsDir.delete(recursive: true);
    }
  });

  test('首次加载时使用默认缩略图大小', () async {
    final notifier = ThumbnailViewSettingsNotifier(store);
    addTearDown(notifier.dispose);
    await _settle();

    expect(notifier.state.gridSize, ThumbnailViewSettings.defaultGridSize);
  });

  test('修改后会保存并在下次加载时恢复', () async {
    final notifier = ThumbnailViewSettingsNotifier(store);
    addTearDown(notifier.dispose);
    await _settle();

    notifier.setGridSize(168);
    await _settle();

    final restoredNotifier = ThumbnailViewSettingsNotifier(store);
    addTearDown(restoredNotifier.dispose);
    await _settle();

    expect(restoredNotifier.state.gridSize, 168);
  });

  test('加载异常范围值时会自动限制到允许区间', () async {
    final file = File(
      '${settingsDir.path}${Platform.pathSeparator}'
      '${FileThumbnailViewSettingsStore.fileName}',
    );
    await file.writeAsString(jsonEncode({'gridSize': 999}));

    final notifier = ThumbnailViewSettingsNotifier(store);
    addTearDown(notifier.dispose);
    await _settle();
    expect(notifier.state.gridSize, ThumbnailViewSettings.maxGridSize);

    notifier.setGridSize(12);
    await _settle();
    expect(notifier.state.gridSize, ThumbnailViewSettings.minGridSize);
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await Future<void>.delayed(const Duration(milliseconds: 80));
}
