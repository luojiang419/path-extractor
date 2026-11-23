import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/widgets/breadcrumb_nav.dart';

void main() {
  const pathSegments = ['Users', 'john', 'Documents'];

  Widget buildWidget({required void Function(int) onTap}) {
    return MaterialApp(
      home: Scaffold(
        body: BreadcrumbNav(pathSegments: pathSegments, onTap: onTap),
      ),
    );
  }

  testWidgets('路径段正确渲染', (WidgetTester tester) async {
    await tester.pumpWidget(buildWidget(onTap: (_) {}));

    // 三个文本都出现在 Widget 树中
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('john'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);

    // 最后一段 'Documents' 使用粗体样式
    final documentsText = tester.widget<Text>(find.text('Documents'));
    expect(documentsText.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('点击非最后一段触发正确的 onTap(index) 回调', (WidgetTester tester) async {
    int? tappedIndex;
    await tester.pumpWidget(buildWidget(onTap: (i) => tappedIndex = i));

    // 点击 'Users'（index=0）
    await tester.tap(find.text('Users'));
    await tester.pump();
    expect(tappedIndex, 0);

    // 点击 'john'（index=1）
    await tester.tap(find.text('john'));
    await tester.pump();
    expect(tappedIndex, 1);
  });

  testWidgets('最后一段不可点击（不是 TextButton）', (WidgetTester tester) async {
    int? tappedIndex;
    await tester.pumpWidget(buildWidget(onTap: (i) => tappedIndex = i));

    // 'Documents' 不在 TextButton 中
    final textButtonFinder = find.ancestor(
      of: find.text('Documents'),
      matching: find.byType(TextButton),
    );
    expect(textButtonFinder, findsNothing);

    // 点击 'Documents' 不触发 onTap
    await tester.tap(find.text('Documents'));
    await tester.pump();
    expect(tappedIndex, isNull);
  });
}
