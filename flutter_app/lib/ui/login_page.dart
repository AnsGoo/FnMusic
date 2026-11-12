/// The connection gate.
///
/// Two tabs:
/// - **普通登录**: a free-form server address (LAN box, tunnel host or
///   `localhost`) plus Music Free credentials.
/// - **飞牛快连 (FNID)**: enter the FNID and Music Free credentials — direct
///   links (LAN / public IPs) are probed without any fnOS credentials; the
///   NAS form is mandatory only when none is reachable, and can be filled
///   optionally while on the LAN to warm up the gateway / relay tokens. Every
///   link FN reports is kept as a failover address, so the app keeps working
///   when the device moves between LAN and WAN. On a unified-gateway link the
///   backend signs the user in from the trusted NAS identity without an app
///   password (first use binds the account once); other links use the normal
///   Music Free sign-in.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/fn_connect.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';

enum _LoginMode { direct, fnConnect }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.notice});

  /// Shown at the top of the form when a saved session could not be revived
  /// automatically (all links down / credentials expired).
  final String? notice;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Shared credentials (both tabs sign in to the same Music Free backend).
  final _username = TextEditingController();
  final _password = TextEditingController();

  // Direct tab.
  final _url = TextEditingController(text: 'http://');

  // Fn Connect tab, step 1 (NAS).
  final _fnId = TextEditingController();
  final _nasUsername = TextEditingController();
  final _nasPassword = TextEditingController();
  final _nasTwoFa = TextEditingController();

  /// The optional "warm up remote links" section on the FNID tab. Kept
  /// collapsed so the common LAN sign-in still needs just the FNID.
  bool _fnRemoteExpanded = false;

  /// NAS account remembered from an earlier FNID sign-in; surfaced so the user
  /// knows remote switching is already armed without re-entering it.
  String? _rememberedNasUser;

  _LoginMode _mode = _LoginMode.direct;
  bool _modePicked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_modePicked) return;
    _modePicked = true;
    // A FNID session that needs re-authentication should land on the FNID
    // tab with its ID / NAS account already prefilled, not on the plain URL
    // form.
    if (widget.notice != null &&
        context.read<AppModel>().session?.fnConnect == true) {
      _mode = _LoginMode.fnConnect;
    }
  }

  @override
  void initState() {
    super.initState();
    // Prefill the last successfully resolved FNID, kept across logout.
    loadLastFnId().then((fnId) {
      if (fnId != null && mounted && _fnId.text.isEmpty) {
        setState(() => _fnId.text = fnId);
      }
    });
    // Prefill the remembered fnOS account so the "外网自动切换" section shows
    // it is already armed, and the user does not have to retype it.
    loadFnOsCredentials().then((creds) {
      if (creds != null && mounted) {
        setState(() {
          if (_nasUsername.text.isEmpty) _nasUsername.text = creds.username;
          if (_nasPassword.text.isEmpty) _nasPassword.text = creds.password;
          _rememberedNasUser = creds.username;
        });
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _fnId.dispose();
    _nasUsername.dispose();
    _nasPassword.dispose();
    _nasTwoFa.dispose();
    super.dispose();
  }

  void _submit() {
    final model = context.read<AppModel>();
    if (_mode == _LoginMode.direct) {
      model.login(_url.text, _username.text, _password.text);
    } else if (model.fnPrepared) {
      model.loginFnPrepared(username: _username.text, password: _password.text);
    } else {
      model.prepareFnConnect(
        fnId: _fnId.text.trim(),
        nasUsername: _nasUsername.text,
        nasPassword: _nasPassword.text,
        nasTwoFaCode: _nasTwoFa.text,
      );
    }
  }

  /// Segmented tab switcher, styled after the app's compact controls.
  Widget _tabs() {
    Widget tab(_LoginMode mode, String label) {
      final selected = _mode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_mode == mode) return;
            setState(() => _mode = mode);
            // Errors belong to one flow; switching flows clears them.
            context.read<AppModel>().consumeError();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Mf.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? Mf.accent : Colors.transparent),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Mf.text : Mf.faint,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Mf.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          tab(_LoginMode.direct, '普通登录'),
          tab(_LoginMode.fnConnect, '飞牛快连 (FNID)'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    // Landscape phones get a two-column layout: brand on the left, the
    // connection form on the right. Portrait stacks everything.
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;

    // Exactly one status banner: a request error wins over the re-login
    // notice. Previously a notice, a bordered "step 1 complete" card and a
    // long hint could all be on screen at once, competing for attention.
    final status = model.error ?? widget.notice;
    final List<Widget> form = [
      _tabs(),
      const SizedBox(height: 14),
      if (status != null)
        _StatusBanner(
          message: status,
          detail: model.error == null ? '网络恢复后自动返回' : null,
          error: model.error != null,
        ),
      if (_mode == _LoginMode.direct) ..._directForm(model),
      if (_mode == _LoginMode.fnConnect) ..._fnConnectForm(model),
      const SizedBox(height: 22),
      MfPrimaryButton(
        label: model.connecting
            ? '连接中…'
            : _mode == _LoginMode.direct || model.fnPrepared
            ? '登录'
            : '连接 NAS',
        onTap: model.connecting ? null : _submit,
        enabled: !model.connecting,
      ),
    ];

    return Scaffold(
      backgroundColor: Mf.bg,
      // SafeArea keeps the form clear of the camera cutout when the phone is
      // sideways (the island sits on one of the side edges in landscape).
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: landscape
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              _Logo(size: 96),
                              SizedBox(height: 18),
                              _BrandTexts(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                        Expanded(
                          flex: 3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...form,
                              const SizedBox(height: 16),
                              const Text(
                                '需要 Music Free 服务端 · 兼容 Navidrome / Subsonic',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Mf.faint,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 352),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: _Logo(size: 104)),
                        const SizedBox(height: 22),
                        const _BrandTexts(),
                        const SizedBox(height: 26),
                        ...form,
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
      ),
    );
  }

  // ---- 普通登录 -------------------------------------------------------------

  List<Widget> _directForm(AppModel model) {
    void submit() => model.login(_url.text, _username.text, _password.text);
    return [
      MfField(
        label: '服务器地址',
        value: _url.text,
        placeholder: 'http://192.168.1.10:4533',
        onChanged: (value) => setState(() => _url.text = value),
        onSubmit: submit,
      ),
      const SizedBox(height: 10),
      _credentialsFields(submit),
    ];
  }

  /// The Music Free credentials shared by both tabs.
  Widget _credentialsFields(VoidCallback submit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MfField(
          label: '账号',
          value: _username.text,
          placeholder: 'Music Free 账号',
          onChanged: (value) => _username.text = value,
          onSubmit: submit,
        ),
        const SizedBox(height: 10),
        MfField(
          label: '密码',
          value: _password.text,
          password: true,
          placeholder: 'Music Free 密码',
          onChanged: (value) => _password.text = value,
          onSubmit: submit,
        ),
      ],
    );
  }

  // ---- 飞牛快连 (FNID) -------------------------------------------------------

  List<Widget> _fnConnectForm(AppModel model) {
    final prepared = model.fnPrepared;
    if (prepared) {
      return _fnConnectStep2(model);
    }
    return _fnConnectStep1(model);
  }

  /// Step 1: FNID connection. Direct links are probed without any fnOS
  /// credentials; the NAS form is mandatory when every direct link is
  /// unreachable (remote access rides the gateway / relay), and optional on
  /// the LAN to warm up those tokens in advance. The Music Free backend port
  /// is fixed at 14533 and is deliberately not a form field — the FNID flow
  /// should only need the ID (and, off the LAN, the NAS account).
  List<Widget> _fnConnectStep1(AppModel model) {
    final needsNas = model.fnNasRequired || model.fnTwoFaRequired;
    // On the LAN the NAS credentials are optional: filling them mints the
    // gateway / relay tokens up front so FN's WAN links really work once the
    // device leaves home. Keep the section collapsed by default.
    final showNas = needsNas || _fnRemoteExpanded;
    void submit() => model.prepareFnConnect(
      fnId: _fnId.text.trim(),
      nasUsername: _nasUsername.text,
      nasPassword: _nasPassword.text,
      nasTwoFaCode: _nasTwoFa.text,
    );
    return [
      Text(
        needsNas
            ? '直连不可达 · 登录飞牛账号后可走网关 / 中继远程访问'
            : _rememberedNasUser != null
                ? '第一步 · 已记住飞牛账号 $_rememberedNasUser，离开内网自动切换'
                : '第一步 · 输入 FNID，优先直连内网 / 公网',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Mf.muted, fontSize: 11.5, height: 1.4),
      ),
      const SizedBox(height: 10),
      MfField(
        label: 'FNID',
        value: _fnId.text,
        placeholder: '飞牛快连 ID，如 myid',
        onChanged: (value) => setState(() => _fnId.text = value),
        onSubmit: submit,
      ),
      if (!needsNas) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _fnRemoteExpanded = !_fnRemoteExpanded),
          child: Row(
            children: [
              Icon(
                _fnRemoteExpanded ? Icons.expand_less : Icons.expand_more,
                size: 14,
                color: Mf.faint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _rememberedNasUser != null
                      ? '外网自动切换 · 已记住 $_rememberedNasUser'
                      : '外网自动切换（可选）· 登记飞牛账号，离开内网自动切换',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Mf.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
      if (showNas) ...[
        const SizedBox(height: 10),
        MfField(
          label: needsNas ? '飞牛账号' : '飞牛账号（可选）',
          value: _nasUsername.text,
          placeholder: 'NAS 本地账号',
          onChanged: (value) => _nasUsername.text = value,
          onSubmit: submit,
        ),
        const SizedBox(height: 10),
        MfField(
          label: needsNas ? '飞牛密码' : '飞牛密码（可选）',
          value: _nasPassword.text,
          password: true,
          onChanged: (value) => _nasPassword.text = value,
          onSubmit: submit,
        ),
        // Mandatory flow reveals 2FA only when the NAS asks for it; the
        // optional LAN warm-up shows it right away so 2FA accounts can be
        // registered in one pass.
        if (needsNas ? model.fnTwoFaRequired : true) ...[
          const SizedBox(height: 10),
          MfField(
            label: needsNas
                ? '两步验证码（该账号已开启 2FA）'
                : '两步验证码（可选，账号开启 2FA 时填写）',
            value: _nasTwoFa.text,
            placeholder: '6 位动态码',
            onChanged: (value) => _nasTwoFa.text = value,
            onSubmit: submit,
          ),
        ],
      ],
    ];
  }

  /// Step 2: the NAS is connected; ask for the Music Free credentials.
  ///
  /// The connection summary is one line of muted text rather than a second
  /// bordered banner. During a re-login the status banner above already
  /// explains what happened, so the summary is dropped entirely then (only
  /// the "重新连接" action remains). Every long label is line-capped, which
  /// is what used to overflow the old card on narrow windows.
  List<Widget> _fnConnectStep2(AppModel model) {
    final probe = model.fnProbe;
    final links = probe?.reachable.length ?? 0;
    final showSummary = widget.notice == null && model.error == null;
    void submit() =>
        model.loginFnPrepared(username: _username.text, password: _password.text);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showSummary) ...[
            const Icon(Icons.check_circle, size: 14, color: Mf.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '已连接 · $links 条可达链路，${model.fnAddressCount} 条备用',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Mf.muted, fontSize: 11.5),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: model.resetFnConnect,
            child: const Text(
              '重新连接',
              style: TextStyle(color: Mf.accent, fontSize: 11.5),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        model.fnGatewayLoginAvailable
            ? '第二步 · 网关已校验身份，点「登录」即可进入；首次需填一次应用账号'
            : '第二步 · 输入 Music Free 账号密码',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Mf.muted, fontSize: 11.5, height: 1.4),
      ),
      const SizedBox(height: 10),
      _credentialsFields(submit),
    ];
  }
}

/// The single, bounded status banner above the form.
///
/// Text is line-capped and ellipsized so a long backend error or a long
/// re-login reason can never grow the card past its decoration or squeeze
/// the rest of the form.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    this.detail,
    this.error = false,
  });

  final String message;
  final String? detail;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Mf.accentWash,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 15,
            color: Mf.accentHover,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail == null ? message : '$message · $detail',
              maxLines: error ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Mf.accentHover,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The round app logo.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// MUSICFLY wordmark, app name and slogan, centered under the logo.
class _BrandTexts extends StatelessWidget {
  const _BrandTexts();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MUSICFLY',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Mf.faint,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.6,
          ),
        ),
        SizedBox(height: 7),
        Text(
          '乐记',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Mf.text,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '让听歌这件事简单一点',
          textAlign: TextAlign.center,
          style: TextStyle(color: Mf.muted, fontSize: 13),
        ),
      ],
    );
  }
}
