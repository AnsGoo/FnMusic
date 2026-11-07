/// The connection gate.
///
/// Only one backend is offered, matching the phone and desktop builds: a Music
/// Free server. The address is free-form so a LAN box, a tunnel host or
/// `localhost` all work without a discovery step.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _url = TextEditingController(text: 'http://');
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final model = context.read<AppModel>();
    model.login(_url.text, _username.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return Scaffold(
      backgroundColor: Mf.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 352),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      width: 104,
                      height: 104,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'MUSICFLY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Mf.faint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.6,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  '乐记',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Mf.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '让听歌这件事简单一点',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Mf.muted, fontSize: 13),
                ),
                const SizedBox(height: 26),
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
                  onSubmit: _submit,
                ),
                if (model.error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Mf.accentWash,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      model.error!,
                      style: const TextStyle(
                        color: Mf.accentHover,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                MfPrimaryButton(
                  label: model.connecting ? '连接中…' : '连接',
                  onTap: model.connecting ? null : _submit,
                  enabled: !model.connecting,
                ),
                const SizedBox(height: 16),
                const Text(
                  '需要 Music Free 服务端 · 兼容 Navidrome / Subsonic',
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
}
