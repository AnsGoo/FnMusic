/// Home page data sources: album lists, hot-track flattening and the
/// comprehensive search that returns songs, albums and artists at once.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

MusicFreeClient _clientWith(MockClientHandler handler) {
  final client = MusicFreeClient(httpClient: MockClient(handler));
  client.restore(
    MusicFreeSession(
      baseUrl: Uri.parse('http://127.0.0.1:14533'),
      token: 'token',
      username: 'admin',
      clientSalt: 'salt',
    ),
  );
  return client;
}

Map<String, dynamic> _album(String id, String name) => {
  'id': id,
  'name': name,
  'artist': '歌手',
  'songCount': 3,
  'coverArt': 'al-$id',
};

Map<String, dynamic> _song(String id, String title) => {
  'id': id,
  'title': title,
  'artist': '歌手',
  'album': '专辑',
  'albumId': 'alb',
  'duration': 180,
  'suffix': 'mp3',
};

void main() {
  test('searchAll returns songs, albums and artists from one query', () async {
    final paths = <String>[];
    final client = _clientWith((request) async {
      paths.add(request.url.path);
      expect(request.url.queryParameters['query'], '不该用情');
      expect(request.url.queryParameters['songCount'], '30');
      expect(request.url.queryParameters['albumCount'], '12');
      expect(request.url.queryParameters['artistCount'], '12');
      return _ok({
        'searchResult3': {
          'song': [_song('s1', '不该用情')],
          'album': [_album('a1', '专辑一')],
          'artist': [
            {'id': 'ar1', 'name': '张三', 'albumCount': 2, 'songCount': 10},
          ],
        },
      });
    });

    final result = await client.searchAll('不该用情');
    expect(paths.single, endsWith('/rest/search3.view'));
    expect(result.tracks.single.title, '不该用情');
    expect(result.albums.single.name, '专辑一');
    expect(result.artists.single.name, '张三');
  });

  test('searchAll with a blank query returns nothing', () async {
    final client = _clientWith((request) async {
      fail('a blank query must not hit the network');
    });
    final result = await client.searchAll('   ');
    expect(result.isEmpty, isTrue);
  });

  test('hotTracks round-robins the most played albums', () async {
    final client = _clientWith((request) async {
      final path = request.url.path;
      if (path.endsWith('/rest/getAlbumList2.view')) {
        expect(request.url.queryParameters['type'], 'highest');
        return _ok({
          'albumList2': {
            'album': [
              _album('a1', '热门一'),
              _album('a2', '热门二'),
              _album('a3', '热门三'),
            ],
          },
        });
      }
      if (path.endsWith('/rest/getAlbum.view')) {
        final id = request.url.queryParameters['id'];
        return _ok({
          'album': {
            ..._album(id!, '专辑$id'),
            'song': [
              _song('$id-1', '曲1'),
              _song('$id-2', '曲2'),
            ],
          },
        });
      }
      fail('unexpected request: $path');
    });

    final tracks = await client.hotTracks(limit: 5);
    // Round-robin: one track per album per pass, deduped, capped at 5.
    expect(tracks.map((t) => t.id).toList(), [
      'a1-1',
      'a2-1',
      'a3-1',
      'a1-2',
      'a2-2',
    ]);
  });

  test('albumList parses getAlbumList2 replies', () async {
    final client = _clientWith((request) async {
      expect(request.url.path, endsWith('/rest/getAlbumList2.view'));
      expect(request.url.queryParameters['type'], 'recent');
      expect(request.url.queryParameters['size'], '12');
      return _ok({
        'albumList2': {
          'album': [_album('a1', '最近听过的专辑')],
        },
      });
    });

    final albums = await client.albumList(type: 'recent', size: 12);
    expect(albums.single.name, '最近听过的专辑');
    expect(albums.single.coverId, 'al-a1');
  });

  test('artistDetail parses getArtist replies and fixes the album count', () async {
    final client = _clientWith((request) async {
      expect(request.url.path, endsWith('/rest/getArtist.view'));
      expect(request.url.queryParameters['id'], 'ar1');
      return _ok({
        'artist': {
          'id': 'ar1',
          'name': '张三',
          'coverArt': 'ar-ar1',
          // Some servers report zero here while still listing the albums.
          'albumCount': 0,
          'album': [
            _album('a1', '专辑一'),
            _album('a2', '专辑二'),
          ],
        },
      });
    });

    final page = await client.artistDetail('ar1');
    expect(page.artist.name, '张三');
    expect(page.artist.coverId, 'ar-ar1');
    // The album rows are the truth, not the stale albumCount.
    expect(page.artist.albumCount, 2);
    expect(page.albums.map((a) => a.name), ['专辑一', '专辑二']);
  });

  test('artistDetail tolerates a missing artist node', () async {
    final client = _clientWith((request) async => _ok({}));
    final page = await client.artistDetail('gone');
    expect(page.artist.name, '');
    expect(page.albums, isEmpty);
  });
}
