import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/update_manifest.dart';
import '../providers/app_provider.dart';
import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/toast_notification.dart';
import 'browser_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _hasCheckedForUpdates = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasCheckedForUpdates) return;
      _hasCheckedForUpdates = true;
      unawaited(_checkForUpdates());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('路径提取器'),
        actions: const [ThemeToggle()],
      ),
      body: const ToastOverlay(child: BrowserScreen()),
    );
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateService = ref.read(updateServiceProvider);
      final result = await updateService.checkForUpdate();
      if (!mounted || result.status != UpdateCheckStatus.updateAvailable) {
        return;
      }

      final manifest = result.manifest;
      if (manifest == null) return;

      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('发现新版本 ${manifest.version}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本：${result.currentVersion.displayVersion}'),
                Text('最新版本：${manifest.version}+${manifest.build}'),
                if (manifest.publishedAt != null)
                  Text('发布日期：${_formatPublishedAt(manifest.publishedAt!)}'),
                const SizedBox(height: 12),
                const Text(
                  '更新说明',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(manifest.notes.trim().isEmpty ? '暂无更新说明' : manifest.notes),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('下载并安装'),
            ),
          ],
        ),
      );

      if (shouldDownload != true || !mounted) return;
      await _downloadAndInstall(updateService, manifest);
    } on Object {
      // 启动阶段的更新检查失败时静默忽略，不影响主界面可用。
    }
  }

  Future<void> _downloadAndInstall(
    UpdateService updateService,
    UpdateManifest manifest,
  ) async {
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在下载安装包，请稍候...')),
          ],
        ),
      ),
    );

    try {
      final installerFile = await updateService.downloadInstaller(manifest);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await progressDialog;
      if (!mounted) return;

      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('准备安装更新'),
          content: const Text('安装包已下载完成。点击“立即安装”后，程序将关闭并启动安装器。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('立即安装'),
            ),
          ],
        ),
      );

      if (shouldInstall != true || !mounted) return;
      await updateService.launchInstallerAndExit(installerFile);
    } on UpdateDownloadException catch (error) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
        ref.read(toastProvider.notifier).showError(error.message);
      }
    } on Object {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
        ref.read(toastProvider.notifier).showError('更新失败，请稍后重试');
      }
    }
  }

  String _formatPublishedAt(DateTime publishedAt) {
    final local = publishedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
