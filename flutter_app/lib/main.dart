import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/http_defaults.dart';
import 'state/app_model.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = LocalNetworkDirect();
  runApp(const MusicFlyApp());
}

class MusicFlyApp extends StatelessWidget {
  const MusicFlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppModel()..restoreSession(),
      child: MaterialApp(
        title: 'MusicFly',
        debugShowCheckedModeBanner: false,
        theme: buildMfTheme(),
        home: const _RootPage(),
      ),
    );
  }
}

class _RootPage extends StatefulWidget {
  const _RootPage();

  @override
  State<_RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<_RootPage> {
  /// The launch overlay stays mounted while its exit animation plays; the
  /// destination page (login / home) is already alive underneath, so data
  /// loading overlaps the reveal instead of waiting for it.
  bool _splashUp = true;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final Widget page;
    if (model.booting) {
      page = const ColoredBox(color: Mf.bg);
    } else if (!model.signedIn) {
      page = const LoginPage();
    } else {
      page = const HomeShell();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        page,
        if (_splashUp)
          _SplashOverlay(
            onFinished: () {
              if (mounted) setState(() => _splashUp = false);
            },
          ),
      ],
    );
  }
}

/// Launch splash: the vinyl logo spins over a background that matches its own
/// dark palette (no visible plate), with the tagline underneath. Once booting
/// finishes the whole mark glides from the centre up past the top edge and
/// fades, revealing the page beneath.
class _SplashOverlay extends StatefulWidget {
  const _SplashOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<_SplashOverlay>
    with TickerProviderStateMixin {
  /// Keep the mark on screen long enough to register the tagline even when
  /// the session restores instantly.
  static const _minVisible = Duration(milliseconds: 1200);
  static const _spinPeriod = Duration(milliseconds: 1800);
  static const _exitDuration = Duration(milliseconds: 600);

  final DateTime _startedAt = DateTime.now();
  // Saved at initState: looking the model up via `context.read` is unsafe
  // once the element is being unmounted (dispose).
  late final AppModel _model;
  late final AnimationController _spin;
  late final AnimationController _exit;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _model = context.read<AppModel>();
    _spin = AnimationController(vsync: this, duration: _spinPeriod)..repeat();
    _exit = AnimationController(vsync: this, duration: _exitDuration);
    _model.addListener(_onModelChanged);
    // Booting may already be over by the time this overlay mounts.
    _beginExitWhenReady(_model.booting);
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _spin.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (!mounted) return;
    _beginExitWhenReady(_model.booting);
  }

  void _beginExitWhenReady(bool booting) {
    if (_exiting || booting) return;
    _exiting = true;
    final remaining = _minVisible - DateTime.now().difference(_startedAt);
    (remaining <= Duration.zero
            ? Future<void>.value()
            : Future<void>.delayed(remaining))
        .then((_) {
          if (!mounted) return;
          // Keep the vinyl spinning right up until the exit slide starts.
          _spin.stop();
          _exit.forward().whenComplete(widget.onFinished);
        });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    // Material (transparent) gives the tagline a DefaultTextStyle ancestor —
    // without it debug builds paint the "no Material" double underline.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _exit]),
        builder: (context, _) {
          // 0 → 1 as the mark leaves: slide from centre past the top edge
          // while fading out.
          final t = Curves.easeInCubic.transform(_exit.value);
          final travel = height / 2 + 44;
          return ColoredBox(
            color: Mf.bg,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, -travel * t),
                child: Opacity(
                  opacity: 1 - t,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RotationTransition(
                        turns: _spin,
                        child: ClipOval(
                          child: Image.asset(
                            'assets/logo.png',
                            width: 92,
                            height: 92,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        '让听歌这件事简单一点',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Mf.textSoft,
                          fontSize: 13,
                          letterSpacing: 3,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
