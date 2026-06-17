import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/providers/infinite_list_provider.dart';
import 'package:path_extractor_browser/services/file_system_service.dart';
import 'package:path_extractor_browser/services/path_service.dart';

void main() {
  late Directory tempDir;
  late InfiniteListNotifier notifier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('path_extractor_infinite_');
    notifier = InfiniteListNotifier(FileSystemServiceImpl(), PathServiceImpl());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('拖入时会激活无限模式并按路径去重', () {
    final file = File('${tempDir.path}${Platform.pathSeparator}alpha.txt')
      ..writeAsStringSync('alpha');
    final folder = Directory('${tempDir.path}${Platform.pathSeparator}folder')
      ..createSync();

    notifier.enterFromDrop([file.path, folder.path, file.path]);

    expect(notifier.state.isActive, isTrue);
    expect(notifier.state.isRootView, isTrue);
    expect(notifier.state.rootEntries.map((entry) => entry.path), [
      file.path,
      folder.path,
    ]);
    expect(notifier.state.currentEntries.map((entry) => entry.path), [
      file.path,
      folder.path,
    ]);
  });

  test('拖入文件夹后可在无限模式内导航并返回根列表', () async {
    final root = Directory('${tempDir.path}${Platform.pathSeparator}project')
      ..createSync();
    final nested = Directory('${root.path}${Platform.pathSeparator}src')
      ..createSync();
    final nestedFile = File('${nested.path}${Platform.pathSeparator}main.dart')
      ..writeAsStringSync('void main() {}');

    notifier.enterFromDrop([root.path]);

    await notifier.navigateTo(root.path);
    expect(notifier.state.isRootView, isFalse);
    expect(notifier.state.anchorPath, root.path);
    expect(notifier.state.anchorLabel, 'project');
    expect(
      notifier.state.currentEntries.any((entry) => entry.path == nested.path),
      isTrue,
    );

    await notifier.navigateTo(nested.path);
    expect(notifier.state.currentPath, nested.path);
    expect(
      notifier.state.currentEntries.any(
        (entry) => entry.path == nestedFile.path,
      ),
      isTrue,
    );

    await notifier.navigateUp();
    expect(notifier.state.currentPath, root.path);

    await notifier.navigateUp();
    expect(notifier.state.isRootView, isTrue);
    expect(notifier.state.currentEntries.map((entry) => entry.path), [
      root.path,
    ]);
  });

  test('浏览子目录时追加拖入会扩展根列表且退出会清空会话', () async {
    final firstRoot = Directory('${tempDir.path}${Platform.pathSeparator}first')
      ..createSync();
    final child = Directory('${firstRoot.path}${Platform.pathSeparator}child')
      ..createSync();
    final secondRoot = Directory(
      '${tempDir.path}${Platform.pathSeparator}second',
    )..createSync();
    final copiedFile = File('${child.path}${Platform.pathSeparator}note.txt')
      ..writeAsStringSync('note');

    notifier.enterFromDrop([firstRoot.path]);
    await notifier.navigateTo(firstRoot.path);
    notifier.appendDroppedEntries([secondRoot.path, firstRoot.path]);
    notifier.setLastCopied(copiedFile.path);

    expect(notifier.state.rootEntries.map((entry) => entry.path), [
      firstRoot.path,
      secondRoot.path,
    ]);
    expect(notifier.state.isRootView, isFalse);
    expect(notifier.state.currentPath, firstRoot.path);

    notifier.exitAndClear();

    expect(notifier.state.isActive, isFalse);
    expect(notifier.state.rootEntries, isEmpty);
    expect(notifier.state.currentEntries, isEmpty);
    expect(notifier.state.currentPath, isEmpty);
    expect(notifier.state.lastCopiedPath, isNull);
  });

  test('输入会话内目录路径后继续停留在无限模式中导航', () async {
    final root = Directory('${tempDir.path}${Platform.pathSeparator}project')
      ..createSync();
    final child = Directory('${root.path}${Platform.pathSeparator}lib')
      ..createSync();

    notifier.enterFromDrop([root.path]);

    final result = await notifier.navigateToSubmittedPath(child.path);

    expect(result, InfinitePathSubmitResult.handledInInfinite);
    expect(notifier.state.isActive, isTrue);
    expect(notifier.state.currentPath, child.path);
    expect(notifier.state.anchorPath, root.path);
    expect(notifier.state.highlightedPath, isNull);
  });

  test('输入会话内文件路径后进入父目录并高亮该文件', () async {
    final root = Directory('${tempDir.path}${Platform.pathSeparator}project')
      ..createSync();
    final file = File('${root.path}${Platform.pathSeparator}README.md')
      ..writeAsStringSync('readme');

    notifier.enterFromDrop([root.path]);

    final result = await notifier.navigateToSubmittedPath(file.path);

    expect(result, InfinitePathSubmitResult.handledInInfinite);
    expect(notifier.state.currentPath, root.path);
    expect(notifier.state.anchorPath, root.path);
    expect(notifier.state.highlightedPath, file.path);
  });

  test('输入会话外路径后返回 switchToBrowser 且不改动当前无限会话', () async {
    final root = Directory('${tempDir.path}${Platform.pathSeparator}inside')
      ..createSync();
    final outside = Directory('${tempDir.path}${Platform.pathSeparator}outside')
      ..createSync();

    notifier.enterFromDrop([root.path]);

    final result = await notifier.navigateToSubmittedPath(outside.path);

    expect(result, InfinitePathSubmitResult.switchToBrowser);
    expect(notifier.state.isActive, isTrue);
    expect(notifier.state.isRootView, isTrue);
    expect(notifier.state.currentPath, isEmpty);
    expect(notifier.state.rootEntries.map((entry) => entry.path), [root.path]);
  });

  test('输入无效路径后返回 invalid 且保持当前无限模式位置', () async {
    final root = Directory('${tempDir.path}${Platform.pathSeparator}inside')
      ..createSync();
    final invalidPath = '${tempDir.path}${Platform.pathSeparator}missing.txt';

    notifier.enterFromDrop([root.path]);

    final result = await notifier.navigateToSubmittedPath(invalidPath);

    expect(result, InfinitePathSubmitResult.invalid);
    expect(notifier.state.isActive, isTrue);
    expect(notifier.state.isRootView, isTrue);
    expect(notifier.state.currentPath, isEmpty);
    expect(notifier.state.highlightedPath, isNull);
  });

  test('无限模式下输入网络主机地址时会切回普通浏览器处理', () async {
    final root = Directory('${tempDir.path}${Platform.pathSeparator}inside')
      ..createSync();

    notifier.enterFromDrop([root.path]);

    final result = await notifier.navigateToSubmittedPath('10.10.10.10');

    expect(result, InfinitePathSubmitResult.switchToBrowser);
    expect(notifier.state.isActive, isTrue);
    expect(notifier.state.isRootView, isTrue);
  });
}
