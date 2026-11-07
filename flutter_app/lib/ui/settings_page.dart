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

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final session = model.session;
    return Scaffold(
      backgroundColor: Mf.bg,
      body: Center(
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
                    _InfoRow(
                      label: '地址',
                      value: session?.baseUrl.toString() ?? '',
                    ),
                    const _RowDivider(),
                    _StatusRow(model: model),
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

/// Status line with a live latency figure and a retry tap target.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final info = model.serverInfo;
    final probing = model.probingServer;
    final online = info?.online ?? false;
    final label = probing
        ? '探测中…'
        : online
        ? '在线 · ${info!.latencyMs}ms'
        : '无法连接 · 点按重试';
    final color = probing
        ? Mf.muted
        : online
        ? const Color(0xFF7BC47F)
        : Mf.accentHover;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const SizedBox(
            width: 92,
            child: Text('状态', style: TextStyle(color: Mf.muted, fontSize: 12)),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label, style: TextStyle(color: color, fontSize: 12.5)),
          ),
          if (!probing)
            MfIconButton(
              icon: Icons.refresh_rounded,
              size: 26,
              glyph: 15,
              tooltip: '重新探测',
              onTap: model.refreshServerInfo,
            ),
        ],
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
