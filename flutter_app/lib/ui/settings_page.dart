/// The settings page: account, server status/identity, switch server and
/// sign out. Opened by tapping the account footer in the sidebar.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'home_shell.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppModel>().refreshServerInfo();
    });
  }

  Future<void> _confirmLogout() async {
    final model = context.read<AppModel>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Mf.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '退出登录',
          style: TextStyle(color: Mf.text, fontSize: 16),
        ),
        content: const Text(
          '将清除本机保存的登录信息，需要重新连接服务器。',
          style: TextStyle(color: Mf.textSoft, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Mf.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出', style: TextStyle(color: Mf.accentHover)),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      await model.logout();
    }
  }

  Future<void> _switchServer() async {
    final model = context.read<AppModel>();
    final session = model.session;
    await showDialog<void>(
      context: context,
      builder: (context) => _SwitchServerDialog(
        initialUrl: session?.baseUrl.toString() ?? 'http://',
        initialUsername: session?.username ?? '',
      ),
    );
  }

  Future<void> _addAddress() async {
    final model = context.read<AppModel>();
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Mf.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '添加备用地址',
          style: TextStyle(color: Mf.text, fontSize: 16),
        ),
        // Scrollable within a screen-height cap so short windows (phone
        // landscape) never overflow the dialog.
        content: _ScrollableDialogBody(
          children: [
            const Text(
              '同一服务器的另一个入口，例如外网地址或局域网地址。',
              style: TextStyle(color: Mf.textSoft, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            MfField(
              label: '服务器地址',
              value: '',
              placeholder: 'http://192.168.1.10:4533',
              onChanged: (value) => controller.text = value,
              onSubmit: () => Navigator.pop(context, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Mf.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加', style: TextStyle(color: Mf.accentHover)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (ok != true || !mounted) return;
    final success = await model.addServerAddress(controller.text);
    if (!success && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('地址格式不正确，请检查后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final session = model.session;
    return Scaffold(
      backgroundColor: Mf.bg,
      // No AppBar, so keep the back button and title clear of the status bar
      // (and the list clear of the home indicator) on notched phones.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  children: [
                    MfIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 32,
                      glyph: 16,
                      tooltip: '返回',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '设置',
                      style: TextStyle(
                        color: Mf.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionLabel('账号'),
                _Card(
                  child: Row(
                    children: [
                      AvatarLetter(username: session?.username ?? ''),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session?.username ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Mf.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              '已登录',
                              style: TextStyle(color: Mf.muted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _DangerButton(label: '退出登录', onTap: _confirmLogout),
                const SizedBox(height: 22),
                _SectionLabel('服务器'),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final address in model.serverAddresses) ...[
                        if (address != model.serverAddresses.first)
                          const _RowDivider(),
                        _AddressRow(
                          address: address,
                          active: address == session?.baseUrl,
                        ),
                      ],
                      const _RowDivider(),
                      _AddAddressRow(onAdd: _addAddress),
                      const _RowDivider(),
                      _InfoRow(
                        label: '服务端',
                        value: _serverIdentity(
                          model.serverInfo,
                          model.probingServer,
                        ),
                      ),
                      const _RowDivider(),
                      _InfoRow(
                        label: 'Subsonic API',
                        value: _apiIdentity(model.serverInfo),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '多地址自动切换：每 5 分钟探测一次所有地址并优选延迟最低的'
                    '（局域网与外网同时可达时自动走局域网）。',
                    style: const TextStyle(color: Mf.faint, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 10),
                _DangerButton(
                  label: '切换服务器',
                  onTap: _switchServer,
                  destructive: false,
                ),
                const SizedBox(height: 22),
                _SectionLabel('关于'),
                _Card(
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: '应用', value: '乐记 MusicFly'),
                      _RowDivider(),
                      _InfoRow(label: '版本', value: kAppVersion),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '兼容 Navidrome / Subsonic 生态',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Mf.faint, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _serverIdentity(ServerInfo? info, bool probing) {
    if (info == null) return probing ? '探测中…' : '未知';
    if (!info.online) return '无法连接';
    final type = info.serverType ?? 'Music Free';
    final version = info.serverVersion;
    return version == null || version.isEmpty ? type : '$type $version';
  }

  String _apiIdentity(ServerInfo? info) {
    if (info == null || !info.online) return '—';
    final version = info.subsonicVersion;
    final suffix = info.openSubsonic ? ' · OpenSubsonic' : '';
    return version == null || version.isEmpty ? '—$suffix' : 'v$version$suffix';
  }
}

/// One configured server endpoint: probe status, tap to promote it to the
/// active address, delete when there is more than one.
class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.active});

  final Uri address;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final info = model.addressStatus(address);
    final probed = info != null;
    final online = info?.online ?? false;
    final statusColor = !probed
        ? Mf.muted
        : online
        ? const Color(0xFF7BC47F)
        : Mf.accentHover;
    final statusLabel = !probed
        ? '探测中…'
        : online
        ? '在线 · ${info.latencyMs}ms'
        : '无法连接';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            active ? Icons.radio_button_checked_rounded : Icons.circle_outlined,
            size: 15,
            color: active ? Mf.accent : Mf.faint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? '当前使用' : '备用地址',
                  style: TextStyle(
                    color: active ? Mf.accent : Mf.faint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 1),
                SelectableText(
                  address.toString(),
                  style: const TextStyle(color: Mf.textSoft, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            statusLabel,
            style: TextStyle(color: statusColor, fontSize: 11.5),
          ),
          if (model.serverAddresses.length > 1) ...[
            const SizedBox(width: 4),
            MfIconButton(
              icon: Icons.close_rounded,
              size: 24,
              glyph: 13,
              tooltip: '删除此地址',
              onTap: () => model.removeServerAddress(address),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tap target adding another endpoint for the same server.
class _AddAddressRow extends StatelessWidget {
  const _AddAddressRow({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.add_link_rounded, size: 16, color: Mf.muted),
              const SizedBox(width: 8),
              Text(
                '添加备用地址',
                style: TextStyle(color: Mf.textSoft, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchServerDialog extends StatefulWidget {
  const _SwitchServerDialog({
    required this.initialUrl,
    required this.initialUsername,
  });

  final String initialUrl;
  final String initialUsername;

  @override
  State<_SwitchServerDialog> createState() => _SwitchServerDialogState();
}

class _SwitchServerDialogState extends State<_SwitchServerDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl,
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.initialUsername,
  );
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final model = context.read<AppModel>();
    await model.switchServer(_url.text, _username.text, _password.text);
    if (!mounted) return;
    if (model.signedIn) {
      Navigator.of(context)
        ..pop()
        ..pop(); // close dialog, then settings
    } else {
      setState(() {}); // stay open; the login page takes over on cancel
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return AlertDialog(
      backgroundColor: Mf.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '切换服务器',
        style: TextStyle(color: Mf.text, fontSize: 16),
      ),
      // Scrollable within a screen-height cap so short windows (phone
      // landscape) never overflow the dialog.
      content: _ScrollableDialogBody(
        children: [
          const Text(
            '将退出当前登录并连接新服务器。',
            style: TextStyle(color: Mf.textSoft, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          MfField(
            label: '服务器地址',
            value: _url.text,
            placeholder: 'http://192.168.1.10:4533',
            onChanged: (value) => _url.text = value,
          ),
          const SizedBox(height: 10),
          MfField(
            label: '账号',
            value: _username.text,
            onChanged: (value) => _username.text = value,
          ),
          const SizedBox(height: 10),
          MfField(
            label: '密码',
            value: _password.text,
            password: true,
            onChanged: (value) => _password.text = value,
            onSubmit: model.connecting ? null : _submit,
          ),
          if (model.error != null) ...[
            const SizedBox(height: 10),
            Text(
              model.error!,
              style: const TextStyle(color: Mf.accentHover, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Mf.muted)),
        ),
        TextButton(
          onPressed: model.connecting ? null : _submit,
          child: Text(
            model.connecting ? '连接中…' : '连接',
            style: const TextStyle(color: Mf.accentHover),
          ),
        ),
      ],
    );
  }
}

/// Dialog body that scrolls under a screen-height cap: on phone landscape
/// a multi-field form would otherwise overflow the AlertDialog.
class _ScrollableDialogBody extends StatelessWidget {
  const _ScrollableDialogBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Mf.faint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Mf.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mf.border),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: Mf.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Mf.textSoft, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Divider(height: 1, thickness: 1, color: Mf.border),
    );
  }
}

class _DangerButton extends StatefulWidget {
  const _DangerButton({
    required this.label,
    required this.onTap,
    this.destructive = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<_DangerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.destructive ? Mf.accentHover : Mf.textSoft;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? Mf.surfaceAlt : Mf.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.destructive
                  ? color.withValues(alpha: 0.45)
                  : Mf.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.destructive ? Icons.logout_rounded : Icons.dns_outlined,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
