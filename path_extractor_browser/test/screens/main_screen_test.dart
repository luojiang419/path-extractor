import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/app.dart';
import 'package:path_extractor_browser/config/update_config.dart';
import 'package:path_extractor_browser/providers/update_provider.dart';
import 'package:path_extractor_browser/services/update_service.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  testWidgets('点击检查更新按钮后，已是最新版本时显示提示', (tester) async {
    final updateService = _FakeUpdateService(
      UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        currentVersion: InstalledVersion(version: Version.none, build: 0),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateServiceProvider.overrideWithValue(updateService)],
        child: const App(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('check-update-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('当前已是最新版本'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 250));
  });
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this._result)
    : super(
        config: const AppUpdateConfig(owner: 'test', repo: 'test'),
      );

  final UpdateCheckResult _result;

  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    return _result;
  }
}
