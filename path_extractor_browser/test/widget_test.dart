import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/app.dart';

void main() {
  testWidgets('主界面显示中文标题和双输入工具栏且不再展示模式标签页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    expect(find.text('路径提取器'), findsOneWidget);
    expect(find.text('文件浏览器'), findsNothing);
    expect(find.text('无限模式'), findsNothing);
    expect(find.byKey(const Key('path-input')), findsOneWidget);
    expect(find.byKey(const Key('filter-input')), findsOneWidget);
    expect(find.byKey(const Key('check-update-button')), findsOneWidget);
  });
}
