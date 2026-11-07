/// Casting: control forwarding, queue advance and session teardown.
library;

import 'dart:io';

import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:musicfly/audio/player.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';
import 'package:musicfly/state/app_model.dart';

/// Records every control call without touching any network.
class _FakeSession extends CastSession {
  _FakeSession(super.device);

  final List<CastMedia> loaded = [];
  final List<Duration> seeked = [];
  final List<double> volumes = [];
  int plays = 0;
  int pauses = 0;

  @override
  Future<void> loadMedia(CastMedia media) async {
    loaded.add(media);
    stateMachine.transitionTo(SessionState.loading);
    stateMachine.transitionTo(SessionState.playing);
  }

  @override
  Future<void> play() async => plays++;
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async => seeked.add(position);
  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> setSubtitle(CastSubtitle? subtitle) async {}
  @override
  Future<void> disconnect() async {
    stateMachine.transitionTo(SessionState.disconnected);
  }
}

/// Same shape as the queue tests' fake: never touches a platform channel.
class _FakePlayer extends MfPlayer {
  final List<String> attempted = [];

  @override
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    required String streamUrl,
    String? coverId,
    Duration? duration,
  }) async {
    attempted.add(title);
    state.value = PlaybackState(
      trackId: trackId,
      title: title,
      subtitle: subtitle,
    );
    return true;
  }
}

void main() {
  List<Track> queue(int count) => [
    for (var i = 0; i < count; i++)
      Track(id: 'id$i', title: '曲目${i + 1}', durationSeconds: 180),
  ];

  Future<(AppModel, _FakeSession)> build() async {
    final client = MusicFreeClient();
    client.restore(
      MusicFreeSession(
        baseUrl: Uri.parse('http://127.0.0.1:14533'),
        token: 'token',
        username: 'admin',
        subsonicToken: 'subtoken',
        clientSalt: 'salt',
      ),
    );
    final player = _FakePlayer();
    late final _FakeSession session;
    final model = AppModel(
      client: client,
      player: player,
      castSessionFactory: (device) => session = _FakeSession(device),
    );
    final device = CastDevice(
      id: 'uuid:test',
      name: '客厅音箱',
      protocol: CastProtocol.dlna,
      address: InternetAddress('192.168.1.50'),
      port: 49152,
    );
    await model.playFrom(queue(3), 0);
    await model.connectCast(device);
    return (model, session);
  }

  test('connecting pushes the current track to the renderer', () async {
    final (model, session) = await build();

    expect(model.casting, isTrue);
    expect(model.castDevice?.name, '客厅音箱');
    expect(session.loaded, hasLength(1));
    // The renderer gets the server's own stream URL with token auth, so it
    // needs nothing from this machine.
    final castUrl = session.loaded.single.url;
    expect(castUrl, contains('/rest/stream'));
    expect(castUrl, contains('id=id0'));
    expect(castUrl, contains('t='));
    expect(castUrl, contains('s=salt'));
    expect(session.loaded.single.title, '曲目1');
    // The local player must not have been reloaded by connecting.
    expect(model.player.state.value.playing, isFalse);
    model.dispose();
  });

  test('transport controls are forwarded while casting', () async {
    final (model, session) = await build();

    model.togglePlay();
    await Future<void>.delayed(Duration.zero);
    expect(session.pauses, 1);

    session.stateMachine.transitionTo(SessionState.paused);
    model.togglePlay();
    await Future<void>.delayed(Duration.zero);
    expect(session.plays, 1);

    await model.seek(const Duration(seconds: 42));
    expect(session.seeked, [const Duration(seconds: 42)]);

    model.setVolume(0.4);
    expect(session.volumes, [0.4]);
    expect(model.volume, 0.4);
    model.dispose();
  });

  test('next and previous stay on the renderer', () async {
    final (model, session) = await build();

    await model.next();
    expect(session.loaded, hasLength(2));
    expect(session.loaded.last.title, '曲目2');
    expect(model.currentTrack?.id, 'id1');
    // The local player only ever saw the first track (before connecting).
    expect(model.player.state.value.trackId, 'id0');

    await model.previous();
    expect(session.loaded.last.title, '曲目1');
    model.dispose();
  });

  test('a renderer stop near the end advances the queue', () async {
    final (model, session) = await build();

    // The renderer plays to the last seconds and stops itself.
    session.updateDuration(const Duration(minutes: 3));
    session.updatePosition(const Duration(minutes: 3) - const Duration(seconds: 2));
    session.stateMachine.transitionTo(SessionState.idle);
    await Future<void>.delayed(Duration.zero);

    expect(session.loaded, hasLength(2));
    expect(session.loaded.last.title, '曲目2');
    model.dispose();
  });

  test('a renderer stop mid-track does not advance', () async {
    final (model, session) = await build();

    session.updateDuration(const Duration(minutes: 3));
    session.updatePosition(const Duration(seconds: 30));
    session.stateMachine.transitionTo(SessionState.idle);
    await Future<void>.delayed(Duration.zero);

    expect(session.loaded, hasLength(1));
    expect(model.castState, SessionState.idle);
    model.dispose();
  });

  test('disconnecting hands playback back to the local player', () async {
    final (model, session) = await build();

    await model.next();
    expect(session.loaded.last.title, '曲目2');
    await model.disconnectCast();

    expect(model.casting, isFalse);
    expect(model.castDevice, isNull);
    // The track that was on the renderer now plays locally.
    expect(model.player.state.value.trackId, 'id1');
    model.dispose();
  });
}
