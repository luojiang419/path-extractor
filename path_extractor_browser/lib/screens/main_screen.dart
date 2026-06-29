import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/update_manifest.dart';
import '../providers/app_provider.dart';
import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';
import '../widgets/glow_background.dart';
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
  bool _isCheckingForUpdates = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasCheckedForUpdates) return;
      _hasCheckedForUpdates = true;
      unawaited(_checkForUpdates(userInitiated: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlowBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _AppHeader(
                isCheckingForUpdates: _isCheckingForUpdates,
                onCheckForUpdates: _isCheckingForUpdates
                    ? null
                    : () => unawaited(_checkForUpdates(userInitiated: true)),
              ),
              const Expanded(child: ToastOverlay(child: BrowserScreen())),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkForUpdates({required bool userInitiated}) async {
    if (_isCheckingForUpdates) return;

    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final updateService = ref.read(updateServiceProvider);
      final result = await updateService.checkForUpdate();
      if (!mounted) {
        return;
      }

      switch (result.status) {
        case UpdateCheckStatus.upToDate:
          if (userInitiated) {
            ref.read(toastProvider.notifier).showSuccess('当前已是最新版本');
          }
          return;
        case UpdateCheckStatus.unavailable:
          if (userInitiated) {
            ref.read(toastProvider.notifier).showError('检查更新失败，请稍后重试');
          }
          return;
        case UpdateCheckStatus.updateAvailable:
          break;
      }

      final manifest = result.manifest;
      if (manifest == null) {
        if (userInitiated) {
          ref.read(toastProvider.notifier).showError('检查更新失败，请稍后重试');
        }
        return;
      }

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
      if (mounted && userInitiated) {
        ref.read(toastProvider.notifier).showError('检查更新失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
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

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.isCheckingForUpdates,
    required this.onCheckForUpdates,
  });

  final bool isCheckingForUpdates;
  final VoidCallback? onCheckForUpdates;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GlassPanel(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary.withValues(alpha: 0.88),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(Icons.alt_route, color: colorScheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '路径提取器',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const ThemeToggle(),
          IconButton(
            key: const Key('check-update-button'),
            tooltip: '检查更新',
            onPressed: onCheckForUpdates,
            icon: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: isCheckingForUpdates
                  ? const SizedBox(
                      key: ValueKey('checking'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.system_update_alt, key: ValueKey('idle')),
            ),
          ),
        ],
      ),
    );
  }
}
