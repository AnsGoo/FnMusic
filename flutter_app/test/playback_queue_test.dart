/// Queue behaviour when the server refuses to hand over a track's file.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:musicfly/audio/player.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';
import 'package:musicfly/state/app_model.dart';

/// Never touches a platform channel: it reports the failure the way the real
/// player does (state + `onFailed`) and returns false.
class _FakePlayer extends MfPlayer {
  _FakePlayer({this.healthy = false});

  /// When true every track loads fine.
  bool healthy;
  final List<String> attempted = [];

  @override
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    required String streamUrl,
    String? coverId,
    Duration? duration,
    bool transcoded = false,
  }) async {
    attempted.add(title);
    state.value = PlaybackState(
      trackId: trackId,
      title: title,
      subtitle: subtitle,
    );
    if (healthy) return true;
    onFailed?.call(trackId, '文件在服务端找不到了');
    return false;
  }
}

void main() {
  List<Track> queue(int count) => [
    for (var i = 0; i < count; i++)
      Track(id: 'id$i', title: '曲目${i + 1}'),
  ];

  AppModel build(_FakePlayer player) {
    final client = MusicFreeClient();
    client.restore(
      MusicFreeSession(
        baseUrl: Uri.parse('http://127.0.0.1:14533'),
        token: 'token',
        username: 'admin',
        clientSalt: 'salt',
      ),
    );
    return AppModel(client: client, player: player);
  }

  test('steps over a broken track and keeps playing', () async {
    final player = _FakePlayer();
    final model = build(player);
    final tracks = queue(3);

    await model.playFrom(tracks, 0);
    await Future<void>.delayed(Duration.zero);

    // Every track fails, so the queue walks to the end and stops there.
    expect(model.queueIndex, 2);
    expect(player.attempted, ['曲目1', '曲目2', '曲目3']);
    expect(model.error, contains('文件在服务端找不到了'));
    model.dispose();
  });

  test('gives up once the whole queue looks broken', () async {
    final player = _FakePlayer();
    final model = build(player);
    final tracks = queue(20);

    await model.playFrom(tracks, 0);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(model.queueIndex, lessThanOrEqualTo(6));
    expect(model.error, contains('连续'));
    expect(player.attempted.length, lessThanOrEqualTo(8));
    model.dispose();
  });

  test('does not skip when the file loads', () async {
    final player = _FakePlayer(healthy: true);
    final model = build(player);
    final tracks = queue(3);

    await model.playFrom(tracks, 0);
    await Future<void>.delayed(Duration.zero);

    expect(model.queueIndex, 0);
    expect(player.attempted, ['曲目1']);
    expect(model.error, isNull);
    model.dispose();
  });
}
