import 'package:flutter/material.dart';
import '../services/network_drive_service.dart';

/// 返回值：用户填写完成后的 NetworkDriveEntry，取消则返回 null
Future<NetworkDriveEntry?> showNetworkDriveDialog(BuildContext context) {
  return showDialog<NetworkDriveEntry>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _NetworkDriveDialog(),
  );
}

Future<NetworkDriveEntry?> showNetworkCredentialDialog(
  BuildContext context, {
  required String address,
  String? title,
  String? helperText,
}) {
  return showDialog<NetworkDriveEntry>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NetworkCredentialDialog(
      address: address,
      title: title ?? '需要网络凭据',
      helperText: helperText,
    ),
  );
}

class _NetworkDriveDialog extends StatefulWidget {
  const _NetworkDriveDialog();

  @override
  State<_NetworkDriveDialog> createState() => _NetworkDriveDialogState();
}

class _NetworkDriveDialogState extends State<_NetworkDriveDialog> {
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _needAuth = false;
  bool _savePassword = false;
  bool _obscurePass = true;
  bool _isConnecting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _labelCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isConnecting = true;
      _errorMsg = null;
    });

    final address = _addressCtrl.text.trim();
    final label = _labelCtrl.text.trim().isEmpty
        ? address.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last
        : _labelCtrl.text.trim();

    final entry = NetworkDriveEntry(
      address: address,
      label: label,
      username: _needAuth && _userCtrl.text.isNotEmpty ? _userCtrl.text : null,
      password: (_needAuth && _savePassword && _passCtrl.text.isNotEmpty)
          ? _passCtrl.text
          : null,
    );

    // 尝试挂载（Windows）
    final svc = NetworkDriveService();
    if (_needAuth) {
      final err = await svc.mountWindows(entry);
      if (err != null) {
        setState(() {
          _isConnecting = false;
          _errorMsg = '连接失败：$err';
        });
        return;
      }
    }

    // 检测是否可访问
    final ok = await svc.isAccessible(address);
    if (!ok && _needAuth) {
      setState(() {
        _isConnecting = false;
        _errorMsg = '无法访问该网络位置，请检查地址和凭据';
      });
      return;
    }

    setState(() => _isConnecting = false);
    if (mounted) Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lan_outlined),
          SizedBox(width: 8),
          Text('添加网络位置'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 网络地址
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: '网络地址',
                  hintText: r'\\192.168.1.1\share 或 //server/share',
                  prefixIcon: Icon(Icons.folder_shared_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '请输入网络地址';
                  return null;
                },
                onChanged: (_) {
                  // 自动填充显示名称
                  if (_labelCtrl.text.isEmpty) setState(() {});
                },
              ),
              const SizedBox(height: 12),
              // 显示名称（可选）
              TextFormField(
                controller: _labelCtrl,
                decoration: InputDecoration(
                  labelText: '显示名称（可选）',
                  hintText: _addressCtrl.text.isEmpty
                      ? '留空则使用地址'
                      : _addressCtrl.text
                                .split(RegExp(r'[/\\]'))
                                .where((s) => s.isNotEmpty)
                                .lastOrNull ??
                            _addressCtrl.text,
                  prefixIcon: const Icon(Icons.label_outline),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // 需要身份验证开关
              SwitchListTile(
                value: _needAuth,
                onChanged: (v) => setState(() => _needAuth = v),
                title: const Text('需要身份验证'),
                subtitle: const Text('输入账号密码连接受保护的共享'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // 账号密码区域
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _needAuth
                    ? Column(
                        children: [
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _userCtrl,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (_needAuth &&
                                  (v == null || v.trim().isEmpty)) {
                                return '请输入用户名';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            decoration: InputDecoration(
                              labelText: '密码',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          CheckboxListTile(
                            value: _savePassword,
                            onChanged: (v) =>
                                setState(() => _savePassword = v ?? false),
                            title: const Text('保存密码'),
                            subtitle: const Text('密码将加密存储在本地配置文件中'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              // 错误提示
              if (_errorMsg != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _isConnecting ? null : _connect,
          icon: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link, size: 16),
          label: Text(_isConnecting ? '连接中...' : '连接'),
        ),
      ],
    );
  }
}

class _NetworkCredentialDialog extends StatefulWidget {
  const _NetworkCredentialDialog({
    required this.address,
    required this.title,
    this.helperText,
  });

  final String address;
  final String title;
  final String? helperText;

  @override
  State<_NetworkCredentialDialog> createState() =>
      _NetworkCredentialDialogState();
}

class _NetworkCredentialDialogState extends State<_NetworkCredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final label =
        widget.address
            .split(RegExp(r'[/\\]'))
            .where((segment) => segment.isNotEmpty)
            .lastOrNull ??
        widget.address;

    Navigator.of(context).pop(
      NetworkDriveEntry(
        address: widget.address,
        label: label,
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline),
          const SizedBox(width: 8),
          Flexible(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                initialValue: widget.address,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: '网络地址',
                  prefixIcon: Icon(Icons.folder_shared_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.helperText != null &&
                  widget.helperText!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.helperText!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _userCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入用户名';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.login, size: 16),
          label: const Text('登录并打开'),
        ),
      ],
    );
  }
}
