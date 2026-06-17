import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../config/update_config.dart';
import '../models/update_manifest.dart';

enum UpdateCheckStatus { upToDate, updateAvailable, unavailable }

class InstalledVersion {
  const InstalledVersion({required this.version, required this.build});

  final Version version;
  final int build;

  String get displayVersion => '${version.toString()}+$build';
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.manifest,
  });

  final UpdateCheckStatus status;
  final InstalledVersion currentVersion;
  final UpdateManifest? manifest;
}

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateService {
  UpdateService({
    required this.config,
    http.Client? client,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _client = client ?? http.Client(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  final AppUpdateConfig config;
  final http.Client _client;
  final Future<PackageInfo> Function() _packageInfoLoader;

  Future<UpdateCheckResult> checkForUpdate() async {
    InstalledVersion? currentVersion;
    try {
      currentVersion = await getInstalledVersion();
      final response = await _client.get(config.latestManifestUri);
      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.unavailable,
          currentVersion: currentVersion,
        );
      }

      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map<String, dynamic>) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.unavailable,
          currentVersion: currentVersion,
        );
      }

      final manifest = UpdateManifest.fromJson(payload);
      if (manifest.version.isEmpty || manifest.installerUrl.isEmpty) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.unavailable,
          currentVersion: currentVersion,
        );
      }

      final remoteVersion = Version.parse(manifest.version);
      final hasNewerVersion =
          remoteVersion > currentVersion.version ||
          (remoteVersion == currentVersion.version &&
              manifest.build > currentVersion.build);

      return UpdateCheckResult(
        status: hasNewerVersion
            ? UpdateCheckStatus.updateAvailable
            : UpdateCheckStatus.upToDate,
        currentVersion: currentVersion,
        manifest: manifest,
      );
    } on Object {
      return UpdateCheckResult(
        status: UpdateCheckStatus.unavailable,
        currentVersion:
            currentVersion ?? InstalledVersion(version: Version.none, build: 0),
      );
    }
  }

  Future<InstalledVersion> getInstalledVersion() async {
    final packageInfo = await _packageInfoLoader();
    final version = Version.parse(packageInfo.version);
    final build = int.tryParse(packageInfo.buildNumber) ?? 0;
    return InstalledVersion(version: version, build: build);
  }

  Future<File> downloadInstaller(UpdateManifest manifest) async {
    final request = http.Request('GET', Uri.parse(manifest.installerUrl));
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw const UpdateDownloadException('下载更新安装包失败');
    }

    final installerName = path.basename(manifest.installerName);
    final targetPath = path.join(Directory.systemTemp.path, installerName);
    final installerFile = File(targetPath);
    if (await installerFile.exists()) {
      await installerFile.delete();
    }

    final sink = installerFile.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }

    final actualSha = await _sha256OfFile(installerFile);
    if (actualSha.toLowerCase() != manifest.installerSha256.toLowerCase()) {
      if (await installerFile.exists()) {
        await installerFile.delete();
      }
      throw const UpdateDownloadException('安装包校验失败，请重新下载');
    }

    return installerFile;
  }

  Future<void> launchInstallerAndExit(File installerFile) async {
    if (!await installerFile.exists()) {
      throw const UpdateDownloadException('安装包不存在，无法启动安装');
    }

    await Process.start(
      installerFile.path,
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
