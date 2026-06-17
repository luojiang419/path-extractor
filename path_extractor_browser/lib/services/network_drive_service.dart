import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/file_entry.dart';

/// 一条已保存的网络位置记录
class NetworkDriveEntry {
  final String address; // UNC 路径，如 \\192.168.1.1\share 或 smb://...
  final String label; // 显示名称
  final String? username;
  final String? password; // 仅当 savePassword=true 时保存

  const NetworkDriveEntry({
    required this.address,
    required this.label,
    this.username,
    this.password,
  });

  Map<String, dynamic> toJson() => {
    'address': address,
    'label': label,
    if (username != null) 'username': username,
    if (password != null) 'password': password,
  };

  factory NetworkDriveEntry.fromJson(Map<String, dynamic> json) =>
      NetworkDriveEntry(
        address: json['address'] as String,
        label: json['label'] as String? ?? json['address'] as String,
        username: json['username'] as String?,
        password: json['password'] as String?,
      );

  NetworkDriveEntry copyWith({
    String? address,
    String? label,
    String? username,
    String? password,
  }) {
    return NetworkDriveEntry(
      address: address ?? this.address,
      label: label ?? this.label,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

enum NetworkPathType { hostRoot, sharePath }

enum NetworkProbeStatus { accessible, authenticationRequired, unavailable }

class ParsedNetworkPath {
  const ParsedNetworkPath({
    required this.path,
    required this.host,
    required this.type,
    this.share,
  });

  final String path;
  final String host;
  final String? share;
  final NetworkPathType type;

  bool get isHostRoot => type == NetworkPathType.hostRoot;

  String get authScope => isHostRoot ? '\\\\$host' : '\\\\$host\\$share';
}

class NetworkHostBrowseResult {
  const NetworkHostBrowseResult({
    required this.status,
    this.entries = const [],
    this.authScope,
    this.message,
  });

  final NetworkProbeStatus status;
  final List<FileEntry> entries;
  final String? authScope;
  final String? message;
}

class NetworkPathProbeResult {
  const NetworkPathProbeResult({
    required this.status,
    required this.entityType,
    this.authScope,
    this.message,
  });

  final NetworkProbeStatus status;
  final FileSystemEntityType entityType;
  final String? authScope;
  final String? message;
}

class NetworkDriveService {
  static const _fileName = 'network_drives.json';

  Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<List<NetworkDriveEntry>> loadAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => NetworkDriveEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<NetworkDriveEntry> entries) async {
    final file = await _getFile();
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(NetworkDriveEntry entry) async {
    final all = await loadAll();
    // 同地址去重
    final updated = [...all.where((e) => e.address != entry.address), entry];
    await saveAll(updated);
  }

  Future<void> remove(String address) async {
    final all = await loadAll();
    await saveAll(all.where((e) => e.address != address).toList());
  }

  static ParsedNetworkPath? parseNetworkPath(String rawPath) {
    if (!Platform.isWindows) return null;

    var path = rawPath.trim();
    if (path.isEmpty) return null;

    if ((path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1).trim();
    }
    if (path.isEmpty) return null;

    final lower = path.toLowerCase();
    if (lower.startsWith('smb://')) {
      path = '\\\\${path.substring(6)}';
    } else if (path.startsWith('//')) {
      path = '\\\\${path.substring(2)}';
    } else if (path.startsWith(r'\\')) {
      // Keep UNC path as-is.
    } else if (_looksLikeHostAndShare(path) || _looksLikeBareHost(path)) {
      path = '\\\\$path';
    } else {
      return null;
    }

    path = path.replaceAll('/', '\\');
    if (!path.startsWith(r'\\')) return null;

    final parts = path
        .substring(2)
        .split('\\')
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final host = parts.first;
    if (parts.length == 1) {
      return ParsedNetworkPath(
        path: '\\\\$host',
        host: host,
        type: NetworkPathType.hostRoot,
      );
    }

    final share = parts[1];
    final remainder = parts.skip(2).toList();
    final normalizedPath = remainder.isEmpty
        ? '\\\\$host\\$share'
        : '\\\\$host\\$share\\${remainder.join('\\')}';

    return ParsedNetworkPath(
      path: normalizedPath,
      host: host,
      share: share,
      type: NetworkPathType.sharePath,
    );
  }

  /// Windows: 使用 net use 挂载 UNC 路径（需要凭据时传入）
  /// 返回 null 表示成功，否则返回错误信息
  Future<String?> mountWindows(NetworkDriveEntry entry) async {
    if (!Platform.isWindows) return null;
    final parsed = parseNetworkPath(entry.address);
    final target = parsed == null
        ? entry.address
        : parsed.isHostRoot
        ? '\\\\${parsed.host}\\IPC\$'
        : parsed.authScope;
    final args = ['use', target];
    if (entry.username != null && entry.password != null) {
      args.addAll([entry.password!, '/user:${entry.username}']);
    }
    try {
      final result = await _runNetCommand(args);
      if (result.exitCode == 0) return null;
      // 已连接也视为成功
      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      if (output.contains('已经存在') ||
          output.contains('already exists') ||
          output.contains('multiple connections')) {
        return null;
      }
      return ('${result.stdout}\n${result.stderr}').trim();
    } catch (e) {
      return e.toString();
    }
  }

  /// 检测 UNC 路径是否可访问（不挂载，直接尝试列目录）
  Future<bool> isAccessible(String address) async {
    try {
      final dir = Directory(address);
      await dir.list().take(1).drain<void>();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<NetworkHostBrowseResult> browseWindowsHost(
    String hostRootPath, {
    NetworkDriveEntry? credentials,
  }) async {
    if (!Platform.isWindows) {
      return const NetworkHostBrowseResult(
        status: NetworkProbeStatus.unavailable,
        message: '当前平台不支持自动探测网络主机',
      );
    }

    final parsed = parseNetworkPath(hostRootPath);
    if (parsed == null || !parsed.isHostRoot) {
      return const NetworkHostBrowseResult(
        status: NetworkProbeStatus.unavailable,
      );
    }

    if (credentials != null) {
      final authError = await mountWindows(credentials);
      if (authError != null) {
        return NetworkHostBrowseResult(
          status: NetworkProbeStatus.authenticationRequired,
          authScope: parsed.authScope,
          message: authError,
        );
      }
    }

    final result = await _runNetCommand(['view', '\\\\${parsed.host}']);
    final output = '${result.stdout}\n${result.stderr}';
    if (result.exitCode == 0) {
      return NetworkHostBrowseResult(
        status: NetworkProbeStatus.accessible,
        entries: _parseShareEntries(parsed.host, output),
      );
    }

    if (_looksLikeAuthFailure(output)) {
      return NetworkHostBrowseResult(
        status: NetworkProbeStatus.authenticationRequired,
        authScope: parsed.authScope,
        message: output.trim(),
      );
    }

    return NetworkHostBrowseResult(
      status: NetworkProbeStatus.unavailable,
      message: output.trim().isEmpty ? '无法访问该网络主机' : output.trim(),
    );
  }

  Future<NetworkPathProbeResult> probeWindowsPath(
    String path, {
    NetworkDriveEntry? credentials,
  }) async {
    if (!Platform.isWindows) {
      return const NetworkPathProbeResult(
        status: NetworkProbeStatus.unavailable,
        entityType: FileSystemEntityType.notFound,
        message: '当前平台不支持自动探测网络路径',
      );
    }

    final parsed = parseNetworkPath(path);
    if (parsed == null || parsed.isHostRoot) {
      return const NetworkPathProbeResult(
        status: NetworkProbeStatus.unavailable,
        entityType: FileSystemEntityType.notFound,
      );
    }

    if (credentials != null) {
      final authError = await mountWindows(credentials);
      if (authError != null) {
        return NetworkPathProbeResult(
          status: NetworkProbeStatus.authenticationRequired,
          entityType: FileSystemEntityType.notFound,
          authScope: parsed.authScope,
          message: authError,
        );
      }
    }

    try {
      if (await File(path).exists()) {
        return NetworkPathProbeResult(
          status: NetworkProbeStatus.accessible,
          entityType: FileSystemEntityType.file,
        );
      }
      if (await Directory(path).exists()) {
        return NetworkPathProbeResult(
          status: NetworkProbeStatus.accessible,
          entityType: FileSystemEntityType.directory,
        );
      }

      try {
        await Directory(path).list().take(1).drain<void>();
        return NetworkPathProbeResult(
          status: NetworkProbeStatus.accessible,
          entityType: FileSystemEntityType.directory,
        );
      } on FileSystemException catch (e) {
        if (_looksLikeAuthException(e)) {
          return NetworkPathProbeResult(
            status: NetworkProbeStatus.authenticationRequired,
            entityType: FileSystemEntityType.notFound,
            authScope: parsed.authScope,
            message: e.message,
          );
        }
      }

      return const NetworkPathProbeResult(
        status: NetworkProbeStatus.unavailable,
        entityType: FileSystemEntityType.notFound,
      );
    } on FileSystemException catch (e) {
      if (_looksLikeAuthException(e)) {
        return NetworkPathProbeResult(
          status: NetworkProbeStatus.authenticationRequired,
          entityType: FileSystemEntityType.notFound,
          authScope: parsed.authScope,
          message: e.message,
        );
      }
      return NetworkPathProbeResult(
        status: NetworkProbeStatus.unavailable,
        entityType: FileSystemEntityType.notFound,
        message: e.message,
      );
    } catch (e) {
      return NetworkPathProbeResult(
        status: NetworkProbeStatus.unavailable,
        entityType: FileSystemEntityType.notFound,
        message: e.toString(),
      );
    }
  }

  static bool isPotentialNetworkInput(String rawPath) {
    return parseNetworkPath(rawPath) != null;
  }

  static bool _looksLikeBareHost(String value) {
    if (value.contains('\\') || value.contains('/')) return false;
    if (_isDriveLetter(value)) return false;
    return _isIpv4(value) || value.contains('.');
  }

  static bool _looksLikeHostAndShare(String value) {
    if (!value.contains('\\')) return false;
    final parts = value.split('\\').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return false;
    final host = parts.first;
    if (_isDriveLetter(host)) return false;
    return _isIpv4(host) || host.contains('.');
  }

  static bool _isIpv4(String value) {
    return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value);
  }

  static bool _isDriveLetter(String value) {
    return value.length == 2 && value[1] == ':';
  }

  Future<ProcessResult> _runNetCommand(List<String> args) async {
    try {
      return await Process.run('net', args).timeout(
        const Duration(seconds: 8),
        onTimeout: () => ProcessResult(-1, -1, '', '网络探测超时，请检查设备是否在线'),
      );
    } on TimeoutException {
      return ProcessResult(-1, -1, '', '网络探测超时，请检查设备是否在线');
    }
  }

  bool _looksLikeAuthFailure(String output) {
    final normalized = output.toLowerCase();
    return normalized.contains('access is denied') ||
        normalized.contains('logon failure') ||
        normalized.contains('system error 5') ||
        normalized.contains('拒绝访问') ||
        normalized.contains('登录失败') ||
        normalized.contains('系统错误 5');
  }

  bool _looksLikeAuthException(FileSystemException exception) {
    final message = '${exception.message} ${exception.osError?.message ?? ''}'
        .toLowerCase();
    final code = exception.osError?.errorCode;
    return code == 5 ||
        code == 13 ||
        message.contains('access is denied') ||
        message.contains('permission denied') ||
        message.contains('拒绝访问') ||
        message.contains('权限');
  }

  List<FileEntry> _parseShareEntries(String host, String output) {
    final lines = const LineSplitter()
        .convert(output)
        .map((line) => line.trimRight())
        .toList();
    final entries = <FileEntry>[];
    var afterDivider = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (!afterDivider) {
        if (RegExp(r'^[-\s]{3,}$').hasMatch(line)) {
          afterDivider = true;
        }
        continue;
      }

      final normalized = line.toLowerCase();
      if (normalized.contains('command completed successfully') ||
          normalized.contains('命令成功完成') ||
          normalized.startsWith('the command completed')) {
        break;
      }

      final columns = line.split(RegExp(r'\s{2,}|\t+'));
      if (columns.isEmpty) continue;
      final shareName = columns.first.trim();
      if (shareName.isEmpty || shareName.endsWith(r'$')) continue;

      entries.add(
        FileEntry(
          path: '\\\\$host\\$shareName',
          name: shareName,
          isDirectory: true,
          type: FileEntryType.directory,
        ),
      );
    }

    return entries;
  }
}
