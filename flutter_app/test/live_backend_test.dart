/// Live checks against a running Music Free server.
///
/// Skipped unless `FNMUSIC_TEST_SERVER` is set, so `flutter test` stays offline
/// by default:
///
///   FNMUSIC_TEST_SERVER=http://127.0.0.1:14533 \
///   FNMUSIC_TEST_USER=admin FNMUSIC_TEST_PASSWORD=admin flutter test
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fnmusic/data/musicfree_client.dart';

final _server = Platform.environment['FNMUSIC_TEST_SERVER'];
final _user = Platform.environment['FNMUSIC_TEST_USER'] ?? 'admin';
final _password = Platform.environment['FNMUSIC_TEST_PASSWORD'] ?? 'admin';

void main() {
  setUpAll(() {
    // `flutter_test` installs an HTTP override that fakes every request; the
    // live suite needs the real socket.
    HttpOverrides.global = null;
  });

  Future<MusicFreeClient> signIn() async {
    final client = MusicFreeClient();
    await client.login(_server!, _user, _password);
    return client;
  }

  test('logs in and lists the library', () async {
    if (_server == null) return;
    final client = await signIn();
    expect(client.session, isNotNull);
    expect(client.session!.token, isNotEmpty);

    final page = await client.tracks(1, 20);
    expect(page.items, isNotEmpty, reason: 'the server should have songs');
    expect(page.total, greaterThan(0));

    final first = page.items.first;
    expect(first.id, isNotEmpty);
    expect(first.title, isNotEmpty);
    expect(first.durationSeconds, greaterThan(0));
    expect(first.album?.name, isNotNull);
  });

  test('reads albums, artists, playlists and search', () async {
    if (_server == null) return;
    final client = await signIn();

    final albums = await client.albums(1, 10);
    expect(albums.items, isNotEmpty);
    final tracks = await client.albumTracks(albums.items.first.id);
    expect(tracks, isNotEmpty, reason: 'an album should expose its songs');

    final artists = await client.artists(1, 10);
    expect(artists.items, isNotEmpty);

    final playlists = await client.playlists();
    expect(playlists, isNotNull);

    final results = await client.searchTracks('周杰伦', limit: 20);
    expect(results, isNotEmpty, reason: 'search should find the fixture album');
  });

  test('builds signed stream and cover URLs', () async {
    if (_server == null) return;
    final client = await signIn();
    final page = await client.tracks(1, 1);
    final track = page.items.first;

    final stream = client.streamUrl(track.id);
    expect(stream, contains('/rest/stream'));
    expect(stream, contains('t='), reason: 'subsonic token must be signed');

    final response = await http.get(Uri.parse(stream));
    expect(response.statusCode, 200);
    if (response.headers['content-type']?.contains('audio/') != true) {
      // The URL is accepted and the media source resolves, but the upstream
      // store can be offline (NAS asleep). That is an environment problem, not
      // a client one, so report it as skipped instead of failing.
      if (response.body.contains('code="70"')) {
        markTestSkipped('媒体源当前不可达（NAS 离线），跳过音频字节断言');
        return;
      }
      fail('unexpected stream reply: ${response.body}');
    }
    expect(response.bodyBytes.length, greaterThan(1024));

    final cover = client.coverUrl(track.coverId);
    if (cover != null) {
      final art = await http.get(Uri.parse(cover));
      expect(art.statusCode, 200);
    }
  });

  test('reads embedded lyrics when a song carries them', () async {
    if (_server == null) return;
    final client = await signIn();
    final page = await client.tracks(1, 20);

    for (final track in page.items) {
      final lyrics = await client.lyrics(track.id);
      if (lyrics == null) continue;
      expect(
        lyrics.isTimed || (lyrics.plain?.isNotEmpty ?? false),
        isTrue,
        reason: 'lyrics should carry either timestamps or text',
      );
      return;
    }
    // A library may legitimately embed none; the client must simply report it.
  });
}
