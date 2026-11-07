/// Lyrics source: OpenSubsonic structured lyrics (getLyricsBySongId) parsing.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({'subsonic-response': {'status': 'ok', ...body}}),
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

void main() {
  test('synced structured lyrics become timed lines with raw LRC', () async {
    final client = _clientWith((request) async {
      expect(request.url.path, endsWith('/rest/getLyricsBySongId.view'));
      expect(request.url.queryParameters['id'], 'song1');
      return _ok({
        'lyricsList': {
          'structuredLyrics': [
            {
              'synced': true,
              'lang': 'und',
              'line': [
                {'start': 0, 'value': '作词 : 某人'},
                // Inline per-word hints must be stripped from the sentence.
                {'start': 12500, 'value': '[00:12.30]第二 [00:12.80]句'},
                {'value': '没有时间戳的一行'},
              ],
            },
          ],
        },
      });
    });

    final lyrics = await client.structuredLyrics('song1');
    expect(lyrics, isNotNull);
    expect(lyrics!.isTimed, isTrue);
    expect(lyrics.lines[0].text, '作词 : 某人');
    expect(lyrics.lines[0].time, Duration.zero);
    expect(lyrics.lines[1].text, '第二 句');
    expect(lyrics.lines[1].time, const Duration(seconds: 12, milliseconds: 500));
    // The line without `start` inherits the previous timestamp.
    expect(lyrics.lines[2].time, const Duration(seconds: 12, milliseconds: 500));
    // Raw LRC stays available for the synced-lyrics view.
    expect(lyrics.raw, contains('[00:12.50]第二 句'));
  });

  test('unsynced structured lyrics come back as plain text', () async {
    final client = _clientWith((request) async => _ok({
      'lyricsList': {
        'structuredLyrics': [
          {
            'synced': false,
            'line': [
              {'value': '第一行'},
              {'value': '第二行'},
            ],
          },
        ],
      },
    }));

    final lyrics = await client.structuredLyrics('song1');
    expect(lyrics, isNotNull);
    expect(lyrics!.isTimed, isFalse);
    expect(lyrics.plain, '第一行\n第二行');
  });

  test('a missing lyrics payload returns null instead of throwing', () async {
    final client = _clientWith(
      (request) async => _ok({'lyricsList': {'structuredLyrics': []}}),
    );
    expect(await client.structuredLyrics('song1'), isNull);
  });

  test('the endpoint is queried with the session credentials', () async {
    final seen = <String>[];
    final client = _clientWith((request) async {
      seen.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/rest/getLyricsBySongId.view')) {
        expect(request.url.queryParameters['id'], 'song9');
        expect(request.url.queryParameters['u'], 'admin');
        return _ok({'lyricsList': {'structuredLyrics': []}});
      }
      return http.Response('not found', 404);
    });

    expect(await client.structuredLyrics('song9'), isNull);
    expect(seen, ['GET /rest/getLyricsBySongId.view']);
  });
}
