/// Guards the naming convention: English wordmark above the Chinese name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
}
