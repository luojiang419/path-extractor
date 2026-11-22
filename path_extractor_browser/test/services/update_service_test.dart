import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_extractor_browser/config/update_config.dart';
import 'package:path_extractor_browser/models/update_manifest.dart';
import 'package:path_extractor_browser/services/update_service.dart';

void main() {
  late AppUpdateConfig config;

  setUp(() {
    config = const AppUpdateConfig(
      owner: 'luojiang419',
      repo: 'path-extractor',
    );
  });

  test('远端版本更高时返回 updateAvailable', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('latest.json')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'version': '1.0.1',
              'build': 2,
              'published_at': '2026-06-17T12:00:00Z',
              'notes': '修复若干问题',
              'installer_name': '路径提取器-安装包-1.0.1.exe',
              'installer_url':
                  'https://github.com/luojiang419/path-extractor/releases/download/v1.0.1/%E8%B7%AF%E5%BE%84%E6%8F%90%E5%8F%96%E5%99%A8-%E5%AE%89%E8%A3%85%E5%8C%85-1.0.1.exe',
              'installer_sha256': 'abc',
              'minimum_supported_version': '1.0.0',
            }),
          ),
          HttpStatus.ok,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', HttpStatus.notFound);
    });

    final service = UpdateService(
      config: config,
      client: client,
      packageInfoLoader: () async => PackageInfo(
        appName: '路径提取器',
        packageName: 'path_extractor_browser',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );

    final result = await service.checkForUpdate();

    expect(result.status, UpdateCheckStatus.updateAvailable);
    expect(result.manifest?.version, '1.0.1');
  });

  test('远端版本相同时返回 upToDate', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'version': '1.0.0',
            'build': 1,
            'published_at': '2026-06-17T12:00:00Z',
            'notes': '',
            'installer_name': '路径提取器-安装包-1.0.0.exe',
            'installer_url': 'https://example.com/installer.exe',
            'installer_sha256': 'abc',
            'minimum_supported_version': '1.0.0',
          }),
        ),
        HttpStatus.ok,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final service = UpdateService(
      config: config,
      client: client,
      packageInfoLoader: () async => PackageInfo(
        appName: '路径提取器',
        packageName: 'path_extractor_browser',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );

    final result = await service.checkForUpdate();

    expect(result.status, UpdateCheckStatus.upToDate);
  });

  test('下载安装包并校验 SHA256 成功', () async {
    final bytes = utf8.encode('installer-binary');
    final expectedSha = sha256.convert(bytes).toString();
    final manifest = UpdateManifest(
      version: '1.0.1',
      build: 2,
      publishedAt: DateTime.utc(2026, 6, 17, 12),
      notes: '修复若干问题',
      installerName: 'path-extractor-test-installer.exe',
      installerUrl: 'https://example.com/installer.exe',
      installerSha256: expectedSha,
      minimumSupportedVersion: '1.0.0',
    );

    final client = MockClient((request) async {
      if (request.url.toString() == manifest.installerUrl) {
        return http.Response.bytes(bytes, HttpStatus.ok);
      }
      return http.Response('', HttpStatus.notFound);
    });

    final service = UpdateService(
      config: config,
      client: client,
      packageInfoLoader: () async => PackageInfo(
        appName: '路径提取器',
        packageName: 'path_extractor_browser',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );

    final installerFile = await service.downloadInstaller(manifest);

    expect(await installerFile.exists(), isTrue);
    expect(await installerFile.readAsBytes(), bytes);

    await installerFile.delete();
  });

  test('安装包哈希不匹配时抛出异常并删除临时文件', () async {
    final manifest = UpdateManifest(
      version: '1.0.1',
      build: 2,
      publishedAt: DateTime.utc(2026, 6, 17, 12),
      notes: '修复若干问题',
      installerName: 'path-extractor-invalid-installer.exe',
      installerUrl: 'https://example.com/installer.exe',
      installerSha256: 'invalid-hash',
      minimumSupportedVersion: '1.0.0',
    );

    final client = MockClient((request) async {
      if (request.url.toString() == manifest.installerUrl) {
        return http.Response.bytes(
          utf8.encode('installer-binary'),
          HttpStatus.ok,
        );
      }
      return http.Response('', HttpStatus.notFound);
    });

    final service = UpdateService(
      config: config,
      client: client,
      packageInfoLoader: () async => PackageInfo(
        appName: '路径提取器',
        packageName: 'path_extractor_browser',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );

    final targetFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}${manifest.installerName}',
    );

    await expectLater(
      service.downloadInstaller(manifest),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(await targetFile.exists(), isFalse);
  });
}
