/// The cover is the way into the full player, so the transport and the page
/// must agree on one flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:musicfly/audio/player.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';
import 'package:musicfly/state/app_model.dart';
import 'package:musicfly/ui/home_shell.dart';
import 'package:musicfly/ui/now_playing.dart';
import 'package:musicfly/ui/player_bar.dart';
import 'package:musicfly/ui/theme.dart';

class _SilentPlayer extends MfPlayer {
  final List<String> played = [];

  @override
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    required String streamUrl,
    String? coverId,
    Duration? duration,
  }) async {
    played.add(title);
    state.value = PlaybackState(
      trackId: trackId,
      title: title,
      subtitle: subtitle,
      coverId: coverId,
    );
    return true;
  }
}

/// Keeps the widget tests off the network: the model now preloads lyrics for
/// every track so the transport can show a line.
class _OfflineClient extends MusicFreeClient {
  @override
  Future<Lyrics?> structuredLyrics(String trackId) async => null;
}

AppModel _model() {
  final client = _OfflineClient()
    ..restore(
      MusicFreeSession(
        baseUrl: Uri.parse('http://127.0.0.1:1'),
        token: 'token',
        username: 'admin',
        clientSalt: 'salt',
      ),
    );
  return AppModel(client: client, player: _SilentPlayer());
}

Widget _host(AppModel model, Widget child) => ChangeNotifierProvider<AppModel>.value(
  value: model,
  child: MaterialApp(
    theme: buildMfTheme(),
    home: Scaffold(body: child),
  ),
);

void main() {
  test('opening the player is a plain state toggle', () {
    final model = _model();
    expect(model.nowPlayingVisible, isFalse);

    model.openNowPlaying();
    expect(model.nowPlayingVisible, isTrue);

    model.closeNowPlaying();
    expect(model.nowPlayingVisible, isFalse);
  });

  test('parsed lyrics keep the raw LRC for the lyric renderer', () {
    final lyrics = parseLyrics('[00:01.00]第一句\n[00:02.50]第二句');
    expect(lyrics.isTimed, isTrue);
    expect(lyrics.raw, contains('[00:02.50]第二句'));
  });

  testWidgets('tapping the cover opens the full player', (tester) async {
    final model = _model();
    await model.playFrom([const Track(id: 'a', title: '不该用情')], 0);

    await tester.pumpWidget(_host(model, const PlayerBar(wide: true)));
    await tester.pump();
    expect(find.text('不该用情'), findsOneWidget);

    await tester.tap(find.byTooltip('查看播放详情'));
    await tester.pump();
    expect(model.nowPlayingVisible, isTrue);
  });

  testWidgets('the player page shows the song and an empty-lyrics hint', (
    tester,
  ) async {
    final model = _model();
    await model.playFrom([const Track(id: 'a', title: '不该用情')], 0);

    await tester.pumpWidget(_host(model, const NowPlayingPage()));
    await tester.pump();

    expect(find.text('不该用情'), findsOneWidget);
    expect(find.text('这首歌没有内嵌歌词'), findsOneWidget);
  });

  testWidgets('on a phone the sections live in a swipe-in drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = _model();
    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();

    // No tab bar under the transport any more. The home page behind the
    // drawer does carry a card titled 专辑, so scope the drawer lookups.
    expect(find.byTooltip('打开侧边栏'), findsOneWidget);

    // A left-to-right touch from the edge reveals the PC-style sidebar.
    await tester.dragFrom(const Offset(4, 420), const Offset(260, 0));
    await tester.pumpAndSettle();

    final drawer = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('专辑'),
    );
    expect(drawer, findsOneWidget);
    expect(
      find.descendant(of: find.byType(Drawer), matching: find.text('艺术家')),
      findsOneWidget,
    );
    expect(find.text('乐记'), findsOneWidget);
  });

  testWidgets('the toolbar menu button opens the same drawer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = _model();
    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();

    await tester.tap(find.byTooltip('打开侧边栏'));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    expect(
      find.descendant(of: drawer, matching: find.text('歌单')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('收藏')),
      findsOneWidget,
    );
  });

  testWidgets('picking a section closes the drawer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = _model();
    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();

    await tester.tap(find.byTooltip('打开侧边栏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出登录'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('专辑')),
    );
    await tester.pumpAndSettle();

    expect(model.section, Section.albums);
    expect(find.byTooltip('退出登录'), findsNothing);
  });

  testWidgets('the shell keeps a single transport while the page is open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = _model();
    await model.playFrom([const Track(id: 'a', title: '不该用情')], 0);

    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();
    expect(find.byType(PlayerBar), findsOneWidget);
    expect(find.byType(NowPlayingPage), findsNothing);

    model.openNowPlaying();
    await tester.pump();

    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(find.byType(PlayerBar), findsNothing);
  });

  testWidgets('the player page stacks instead of overflowing on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = _model();
    await model.playFrom([const Track(id: 'a', title: '不该用情')], 0);

    await tester.pumpWidget(_host(model, const NowPlayingPage()));
    await tester.pump();

    expect(find.text('不该用情'), findsWidgets);
  });
}
