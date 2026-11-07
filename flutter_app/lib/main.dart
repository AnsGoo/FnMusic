import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_model.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FnMusicApp());
}

class FnMusicApp extends StatelessWidget {
  const FnMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppModel()..restoreSession(),
      child: MaterialApp(
        title: 'FnMusic',
        debugShowCheckedModeBanner: false,
        theme: buildFnTheme(),
        home: const _RootPage(),
      ),
    );
  }
}

class _RootPage extends StatelessWidget {
  const _RootPage();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    if (model.booting) return const _Splash();
    if (!model.signedIn) return const LoginPage();
    return const HomeShell();
  }
}

/// Shown for the frame it takes to read the saved session.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Fn.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/music_free_logo.png',
                width: 72,
                height: 72,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: 18),
            const FnSpinner(size: 16),
          ],
        ),
      ),
    );
  }
}
