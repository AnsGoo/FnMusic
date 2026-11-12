/// Guards the naming convention: English wordmark above the Chinese name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicfly/state/app_model.dart';
import 'package:musicfly/ui/login_page.dart';
import 'package:musicfly/ui/theme.dart';

void main() {
  testWidgets('the login page shows both names', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppModel(),
        child: MaterialApp(theme: buildMfTheme(), home: const LoginPage()),
      ),
    );

    expect(find.text('MUSICFLY'), findsOneWidget);
    expect(find.text('乐记'), findsOneWidget);
    expect(find.text('让听歌这件事简单一点'), findsOneWidget);
  });

  testWidgets('FNID sign-in has no port field', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppModel(),
        child: MaterialApp(theme: buildMfTheme(), home: const LoginPage()),
      ),
    );
    await tester.tap(find.text('飞牛快连 (FNID)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('服务端口'), findsNothing);
    expect(find.text('14533'), findsNothing);
  });

  testWidgets('re-login shows one compact status banner', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppModel(),
        child: MaterialApp(
          theme: buildMfTheme(),
          home: const LoginPage(notice: '登录已过期，请重新登录'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.textContaining('登录已过期，请重新登录'), findsOneWidget);
    expect(find.textContaining('网络恢复后自动返回'), findsOneWidget);
    // The old two-line banner is gone; reason and hint now share one line.
    expect(find.text('后台仍在自动探测连接，恢复后会自动返回。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the status banner fits a narrow viewport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppModel(),
        child: MaterialApp(
          theme: buildMfTheme(),
          home: const LoginPage(notice: '所有连接地址均不可达，请重新登录'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
