import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/update_manifest.dart';

void main() {
  test('notes 为字符串列表时会合并为多行文本', () {
    final manifest = UpdateManifest.fromJson({
      'version': '1.0.1',
      'build': 1,
      'published_at': '2026-06-17T12:00:00Z',
      'notes': ['- 第一项', '- 第二项'],
      'installer_name': '路径提取器-安装包-1.0.1.exe',
      'installer_url': 'https://example.com/installer.exe',
      'installer_sha256': 'abc',
      'minimum_supported_version': '1.0.0',
    });

    expect(manifest.notes, '- 第一项\n- 第二项');
  });
}
