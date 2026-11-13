/// The playlist sheet, its queue operations and the two-row phone transport.
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
import 'package:musicfly/ui/queue_sheet.dart';
import 'package:musicfly/ui/theme.dart';

class _FakePlayer extends MfPlayer {
  final List<String> played = [];

  @override
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    String? artist,
    required String streamUrl,
    String? coverId,
    String? coverUrl,
    Duration? duration,
    bool transcoded = false,
  }) async {
    played.add(title);
    state.value = PlaybackState(
      trackId: trackId,
      title: title,
      subtitle: subtitle,
    );
    return true;
  }

  @override
  Future<void> stop() async {
    state.value = const PlaybackState();
  }
}

/// Keeps widget tests off the network: every track load preloads lyrics.
class _OfflineClient extends MusicFreeClient {
  @override
  Future<Lyrics?> structuredLyrics(String trackId) async => null;
}

AppModel _model(_FakePlayer player) {
  final client = _OfflineClient()
    ..restore(
      MusicFreeSession(
        baseUrl: Uri.parse('http://127.0.0.1:1'),
        token: 'token',
        username: 'admin',
        clientSalt: 'salt',
      ),
    );
  return AppModel(client: client, player: player);
}

Widget _host(AppModel model, Widget child) =>
    ChangeNotifierProvider<AppModel>.value(
      value: model,
      child: MaterialApp(
        theme: buildMfTheme(),
        home: Scaffold(body: child),
      ),
    );

List<Track> _tracks(int count) => [
  for (var i = 0; i < count; i++)
    Track(
      id: 'id$i',
      title: '曲目${i + 1}',
      artists: [Artist(id: 'a$i', name: '歌手$i')],
    ),
];

void _phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The desktop shape, as opposed to the modal bottom sheet.
Finder _dockedPanel() => find.byWidgetPredicate(
  (widget) => widget is QueueSheet && widget.docked,
);

void main() {
  test('playFrom records the source and starts the history', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(3), 1, source: '我喜欢的音乐');

    expect(model.queue.length, 3);
    expect(model.queueIndex, 1);
    expect(model.queueSource, '我喜欢的音乐');
    expect(model.history.map((t) => t.id), ['id1']);
  });

  test('playQueueAt keeps the queue and moves the current row', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(3), 0, source: '专辑 A');
    await model.playQueueAt(2);

    expect(model.queueIndex, 2);
    expect(model.queue.length, 3);
    expect(model.queueSource, '专辑 A');
    expect(model.history.map((t) => t.id), ['id2', 'id0']);
  });

  test('removing a row above the current one keeps the same song playing', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(4), 2);
    await model.removeFromQueue(0);

    expect(model.queueIndex, 1);
    expect(model.queue[model.queueIndex].id, 'id2');
    expect(player.played, ['曲目3']);
  });

  test('removing the current row advances to the next one', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(3), 1);
    await model.removeFromQueue(1);

    expect(model.queue.length, 2);
    expect(model.queueIndex, 1);
    expect(player.played, ['曲目2', '曲目3']);
  });

  test('removing the last row stops playback', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(1), 0);
    await model.removeFromQueue(0);

    expect(model.queue, isEmpty);
    expect(model.queueIndex, -1);
    expect(model.queueSource, isNull);
  });

  test('reordering keeps queueIndex on the same song', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(4), 2);
    // ReorderableListView reports the insertion index: moving row 0 to "3"
    // really inserts it at 2.
    model.reorderQueue(0, 3);

    expect(model.queue.map((t) => t.id), ['id1', 'id2', 'id0', 'id3']);
    expect(model.queueIndex, 1);
    expect(model.queue[model.queueIndex].id, 'id2');

    // Dragging the current row itself moves the pointer with it: insertion
    // index 4 lands at 3 once the old row is removed.
    model.reorderQueue(1, 4);
    expect(model.queueIndex, 3);
    expect(model.queue[model.queueIndex].id, 'id2');
  });

  test('clearQueue empties the source label too', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(3), 0, source: '歌单 B');
    await model.clearQueue();

    expect(model.queue, isEmpty);
    expect(model.queueIndex, -1);
    expect(model.queueSource, isNull);
    // Play history is independent of the live queue.
    expect(model.history.length, 1);
    model.clearHistory();
    expect(model.history, isEmpty);
  });

  test('play mode cycles and only looping modes wrap the queue', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    expect(model.playMode, PlayMode.sequential);
    model.cyclePlayMode();
    expect(model.playMode, PlayMode.loopAll);
    model.cyclePlayMode();
    expect(model.playMode, PlayMode.loopOne);
    model.cyclePlayMode();
    expect(model.playMode, PlayMode.shuffle);
    model.cyclePlayMode();
    expect(model.playMode, PlayMode.sequential);

    await model.playFrom(_tracks(3), 2);
    await model.next();
    expect(model.queueIndex, 2, reason: 'sequential stops at the last song');

    model.setPlayMode(PlayMode.loopAll);
    await model.next();
    expect(model.queueIndex, 0);
  });

  test('a natural completion in single-track loop replays the song', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    model.setPlayMode(PlayMode.loopOne);
    await model.playFrom(_tracks(3), 0);
    player.onCompleted?.call();
    await Future<void>.delayed(Duration.zero);

    expect(model.queueIndex, 0);
    expect(player.played, ['曲目1', '曲目1']);
  });

  test('history de-duplicates by id, newest first', () async {
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);

    await model.playFrom(_tracks(3), 0);
    await model.playQueueAt(1);
    await model.playQueueAt(0);

    expect(model.history.map((t) => t.id), ['id0', 'id1']);
  });

  testWidgets('the queue sheet shows tabs, source and two mode pills', (
    tester,
  ) async {
    _phone(tester);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 1, source: '我喜欢的音乐');

    await tester.pumpWidget(_host(model, const QueueSheet()));
    await tester.pump();

    expect(find.text('当前播放'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('历史播放'), findsOneWidget);
    expect(find.text('来自：我喜欢的音乐'), findsOneWidget);
    expect(find.text('顺序播放'), findsOneWidget);
    expect(find.text('回到当前'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a row plays it and the close button drops it', (
    tester,
  ) async {
    _phone(tester);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const QueueSheet()));
    await tester.pump();

    await tester.tap(find.textContaining('曲目3'));
    await tester.pump();
    expect(model.queueIndex, 2);

    await tester.tap(find.byTooltip('从列表移除').first);
    await tester.pump();
    expect(model.queue.length, 2);
    expect(model.queue.map((t) => t.id), ['id1', 'id2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the history tab lists played songs', (tester) async {
    _phone(tester);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const QueueSheet()));
    await tester.pump();
    await tester.tap(find.text('历史播放'));
    await tester.pump();

    expect(find.textContaining('最近播放 1 首'), findsOneWidget);
    expect(find.textContaining('曲目1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone mini bar keeps only play and the queue button', (
    tester,
  ) async {
    _phone(tester, width: 360, height: 780);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const PlayerBar(wide: false)));
    await tester.pump();

    expect(find.byTooltip('播放列表'), findsOneWidget);
    expect(find.byTooltip('上一首'), findsNothing);
    expect(find.byTooltip('收藏'), findsNothing);
    expect(find.byTooltip('投屏'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mini bar queue button opens the sheet', (tester) async {
    _phone(tester);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const PlayerBar(wide: false)));
    await tester.pump();
    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();

    expect(find.byType(QueueSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a portrait phone player splits controls into two rows', (
    tester,
  ) async {
    _phone(tester);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const NowPlayingPage()));
    await tester.pump();

    expect(find.byTooltip('上一首'), findsOneWidget);
    expect(find.byTooltip('下一首'), findsOneWidget);
    expect(find.byTooltip('播放列表'), findsOneWidget);
    expect(find.byTooltip('顺序播放'), findsOneWidget);
    // The quieter utility row only exists on the narrow layout.
    expect(find.byTooltip('歌曲信息'), findsOneWidget);
    expect(find.byTooltip('音量'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window keeps one control row plus the volume slider', (
    tester,
  ) async {
    _phone(tester, width: 1440, height: 900);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const NowPlayingPage()));
    await tester.pump();

    expect(find.byTooltip('播放列表'), findsOneWidget);
    expect(find.byTooltip('歌曲信息'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the desktop queue panel is a toggleable model flag', () {
    final model = _model(_FakePlayer());
    addTearDown(model.dispose);

    expect(model.queuePanelVisible, isFalse);
    model.toggleQueuePanel();
    expect(model.queuePanelVisible, isTrue);
    model.openQueuePanel();
    expect(model.queuePanelVisible, isTrue);
    model.toggleQueuePanel();
    model.closeQueuePanel();
    expect(model.queuePanelVisible, isFalse);
  });

  testWidgets('a desktop queue docks on the right with no modal scrim', (
    tester,
  ) async {
    _phone(tester, width: 1200, height: 800);
    final player = _FakePlayer();
    final model = _model(player);
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0, source: '歌曲库');

    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();
    await tester.tap(find.byTooltip('播放列表'));
    await tester.pump();

    expect(model.queuePanelVisible, isTrue);
    expect(_dockedPanel(), findsOneWidget);
    // The library is still interactive: no bottom sheet, no barrier.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('关闭播放队列'), findsOneWidget);
    expect(find.text('播放队列'), findsOneWidget);
    expect(find.text('来自：歌曲库'), findsOneWidget);
    expect(find.text('顺序播放'), findsOneWidget);

    final rect = tester.getRect(_dockedPanel());
    expect(rect.right, closeTo(1200, 1));
    expect(rect.width, greaterThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('both the transport toggle and the panel close button work', (
    tester,
  ) async {
    _phone(tester, width: 1200, height: 800);
    final model = _model(_FakePlayer());
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);

    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();
    await tester.tap(find.byTooltip('播放列表'));
    await tester.pump();
    expect(_dockedPanel(), findsOneWidget);

    await tester.tap(find.byTooltip('关闭播放列表'));
    await tester.pump();
    expect(model.queuePanelVisible, isFalse);
    expect(_dockedPanel(), findsNothing);

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pump();
    expect(_dockedPanel(), findsOneWidget);
    await tester.tap(find.byTooltip('关闭播放队列'));
    await tester.pump();
    expect(model.queuePanelVisible, isFalse);
    expect(_dockedPanel(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the full-screen player returns to the library before docking', (
    tester,
  ) async {
    _phone(tester, width: 1200, height: 800);
    final model = _model(_FakePlayer());
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);
    model.openNowPlaying();

    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();
    expect(find.byType(NowPlayingPage), findsOneWidget);

    await tester.tap(find.byTooltip('播放列表'));
    await tester.pump();

    expect(model.nowPlayingVisible, isFalse);
    expect(model.queuePanelVisible, isTrue);
    expect(find.byType(NowPlayingPage), findsNothing);
    expect(_dockedPanel(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone player still uses the bottom sheet', (tester) async {
    _phone(tester);
    final model = _model(_FakePlayer());
    addTearDown(model.dispose);
    await model.playFrom(_tracks(3), 0);
    model.openNowPlaying();

    await tester.pumpWidget(_host(model, const HomeShell()));
    await tester.pump();
    await tester.tap(find.byTooltip('播放列表'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_dockedPanel(), findsNothing);
    expect(model.queuePanelVisible, isFalse);
    expect(model.nowPlayingVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  // The two footer controls must not grow back into full-width 46px pills:
  // they used to dominate the 300-360px desktop sidebar and the phone sheet.
  for (final size in const <Size>[Size(1200, 800), Size(390, 844)]) {
    testWidgets('footer chips stay compact at $size', (tester) async {
      _phone(tester, width: size.width, height: size.height);
      final model = _model(_FakePlayer());
      addTearDown(model.dispose);
      await model.playFrom(_tracks(3), 0, source: '歌曲库');

      if (size.width >= kDockedQueueBreakpoint) {
        model.openQueuePanel();
        await tester.pumpWidget(_host(model, const HomeShell()));
      } else {
        await tester.pumpWidget(_host(model, const QueueSheet()));
      }
      await tester.pump();

      final mode = find.byKey(const ValueKey('queue-pill-顺序播放'));
      final locate = find.byKey(const ValueKey('queue-pill-回到当前'));
      expect(mode, findsOneWidget);
      expect(locate, findsOneWidget);

      final modeSize = tester.getSize(mode);
      final locateSize = tester.getSize(locate);
      expect(modeSize.height, lessThanOrEqualTo(32));
      expect(locateSize.height, lessThanOrEqualTo(32));
      expect(modeSize.width, lessThan(140));
      expect(locateSize.width, lessThan(140));
      // Both chips together stay well short of the panel width.
      expect(modeSize.width + locateSize.width, lessThan(size.width * 0.7));
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const <Size>[
    Size(900, 600),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('docked queue does not overflow at $size', (tester) async {
      _phone(tester, width: size.width, height: size.height);
      final model = _model(_FakePlayer());
      addTearDown(model.dispose);
      await model.playFrom(_tracks(3), 0);
      model.openQueuePanel();

      await tester.pumpWidget(_host(model, const HomeShell()));
      await tester.pump();

      expect(_dockedPanel(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
