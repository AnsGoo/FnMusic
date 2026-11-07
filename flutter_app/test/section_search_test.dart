/// Section-aware search: every library list can be searched, songs and
/// albums and artists through the server, playlists and favorites in memory.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:musicfly/audio/player.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';
import 'package:musicfly/data/session_store.dart';
import 'package:musicfly/state/app_model.dart';

/// Never touches a platform channel: nothing in these tests plays audio.
class _FakePlayer extends MfPlayer {
  @override
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    required String streamUrl,
    String? coverId,
    Duration? duration,
  }) async => false;
}

/// Hands back a session without touching shared preferences.
class _FakeStore extends SessionStore {
  _FakeStore(this.session);

  final MusicFreeSession session;

  @override
  Future<MusicFreeSession?> load() async => session;
  @override
  Future<void> save(MusicFreeSession session) async {}
  @override
  Future<void> clear() async {}
}

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// Anything the boot sequence touches but a test does not assert on.
http.Response _empty(http.Request request) => _ok(const {});

void main() {
  Future<AppModel> modelWith(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final client = MusicFreeClient(httpClient: MockClient(handler));
    final model = AppModel(
      client: client,
      player: _FakePlayer(),
      store: _FakeStore(
        MusicFreeSession(
          baseUrl: Uri.parse('http://127.0.0.1:14533'),
          token: 'token',
          username: 'admin',
          clientSalt: 'salt',
        ),
      ),
    );
    // Boot lands on the home page; the boot's own requests fall through to
    // the empty reply, and each test then selects the section it asserts on.
    await model.restoreSession();
    return model;
  }

  test('playlists search filters the local list by name', () async {
    final searchCalls = <Uri>[];
    final model = await modelWith((request) async {
      if (request.url.path.endsWith('/rest/api/v1/playlists')) {
        return _ok({
          'playlists': [
            {'id': 'p1', 'name': '华语经典'},
            {'id': 'p2', 'name': '欧美流行'},
          ],
        });
      }
      if (request.url.path.endsWith('/rest/search3.view')) {
        searchCalls.add(request.url);
        return _ok({'searchResult3': {}});
      }
      return _empty(request);
    });

    await model.select(Section.playlists);
    model.updateQuery('华语');
    await model.submitSearch();

    // Playlists have no server search; filtering happens in memory.
    expect(searchCalls, isEmpty);
    expect(model.searching, isTrue);
    expect(model.visiblePlaylists.single.name, '华语经典');
    expect(model.headerSubtitle, '1 个结果');
    model.dispose();
  });

  test('favorites search filters by title, artist and album', () async {
    final model = await modelWith((request) async {
      if (request.url.path.endsWith('/rest/getStarred2.view')) {
        return _ok({
          'starred2': {
            'song': [
              {'id': 's1', 'title': '不该用情', 'artist': '张三', 'suffix': 'mp3'},
              {'id': 's2', 'title': '别的歌', 'artist': '李四', 'suffix': 'mp3'},
            ],
          },
        });
      }
      return _empty(request);
    });

    await model.select(Section.favorites);
    model.updateQuery('张三');
    await model.submitSearch();

    expect(model.visibleTracks.single.id, 's1');
    model.dispose();
  });

  test('artists search queries search3 for artists only', () async {
    Uri? searchUri;
    final model = await modelWith((request) async {
      if (request.url.path.endsWith('/rest/search3.view')) {
        searchUri = request.url;
        return _ok({
          'searchResult3': {
            'artist': [
              {'id': 'ar1', 'name': '张三', 'albumCount': 2},
            ],
          },
        });
      }
      return _empty(request);
    });

    await model.select(Section.artists);
    model.updateQuery('张三');
    await model.submitSearch();

    expect(searchUri, isNotNull);
    expect(searchUri!.queryParameters['songCount'], '0');
    expect(searchUri!.queryParameters['albumCount'], '0');
    expect(searchUri!.queryParameters['artistCount'], '100');
    expect(model.visibleArtists.single.name, '张三');
    model.dispose();
  });

  test('albums search queries search3 for albums only', () async {
    Uri? searchUri;
    final model = await modelWith((request) async {
      if (request.url.path.endsWith('/rest/search3.view')) {
        searchUri = request.url;
        return _ok({
          'searchResult3': {
            'album': [
              {'id': 'al1', 'name': '命中专辑', 'artist': '张三'},
            ],
          },
        });
      }
      return _empty(request);
    });

    await model.select(Section.albums);
    model.updateQuery('命中');
    await model.submitSearch();

    expect(searchUri!.queryParameters['albumCount'], '100');
    expect(searchUri!.queryParameters['songCount'], '0');
    expect(model.visibleAlbums.single.name, '命中专辑');
    model.dispose();
  });

  test('tracks search still goes through the server', () async {
    Uri? searchUri;
    final model = await modelWith((request) async {
      if (request.url.path.endsWith('/rest/search3.view')) {
        searchUri = request.url;
        return _ok({
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': '不该用情', 'artist': '张三', 'suffix': 'mp3'},
            ],
          },
        });
      }
      return _empty(request);
    });

    await model.select(Section.tracks);
    model.updateQuery('不该用情');
    await model.submitSearch();

    expect(searchUri!.queryParameters['songCount'], '60');
    expect(model.visibleTracks.single.title, '不该用情');
    model.dispose();
  });
}
