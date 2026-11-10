import 'package:flutter_test/flutter_test.dart';

import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';

void main() {
  group('parseLyrics', () {
    test('reads LRC timestamps and drops empty lines', () {
      const raw = '[00:12.50]第一行\n[00:18.00]第二行\n[00:20.00]\n';
      final lyrics = parseLyrics(raw);
      expect(lyrics.isTimed, isTrue);
      expect(lyrics.lines, hasLength(2));
      expect(lyrics.lines.first.time, const Duration(milliseconds: 12500));
      expect(lyrics.lines.first.text, '第一行');
      expect(lyrics.lines.last.time, const Duration(seconds: 18));
    });

    test('expands a line carrying several timestamps', () {
      const raw = '[00:01.00][00:30.00]副歌';
      final lyrics = parseLyrics(raw);
      expect(lyrics.lines, hasLength(2));
      expect(lyrics.lines[1].time, const Duration(seconds: 30));
      expect(lyrics.lines[1].text, '副歌');
    });

    test('falls back to plain text without timestamps', () {
      final lyrics = parseLyrics('没有时间轴的歌词\n第二行');
      expect(lyrics.isTimed, isFalse);
      expect(lyrics.plain, contains('没有时间轴'));
    });

    test('indexAt follows the playhead', () {
      final lyrics = parseLyrics('[00:01.00]a\n[00:05.00]b\n[00:09.00]c');
      expect(lyrics.indexAt(Duration.zero), -1);
      expect(lyrics.indexAt(const Duration(seconds: 2)), 0);
      expect(lyrics.indexAt(const Duration(seconds: 6)), 1);
      expect(lyrics.indexAt(const Duration(seconds: 20)), 2);
    });
  });

  group('transcode decision', () {
    test('containers the decoders cannot handle go through mp3', () {
      expect(needsTranscode('wma'), isTrue);
      expect(needsTranscode('APE'), isTrue);
      expect(needsTranscode('ogg'), isTrue);
      expect(needsTranscode('opus'), isTrue);
    });

    test('common and lossless containers stream raw', () {
      expect(needsTranscode('mp3'), isFalse);
      expect(needsTranscode('m4a'), isFalse);
      expect(needsTranscode('flac'), isFalse);
      expect(needsTranscode('wav'), isFalse);
      expect(needsTranscode(null), isFalse);
      expect(needsTranscode(''), isFalse);
    });

    test('tracks carry the container suffix', () {
      const track = Track(id: 'a', title: 't', format: 'flac');
      expect(track.format, 'flac');
      const bare = Track(id: 'b', title: 't');
      expect(bare.format, isNull);
    });

    test('raw stream URLs carry neither format nor maxBitRate', () {
      final client = MusicFreeClient()
        ..restore(
          MusicFreeSession(
            baseUrl: Uri.parse('http://127.0.0.1:14533'),
            token: 't',
            username: 'admin',
            subsonicToken: 'abc',
            clientSalt: 'salt',
          ),
        );
      final raw = Uri.parse(
        client.streamUrl('id1', format: null, maxBitRate: null),
      );
      expect(raw.queryParameters.containsKey('format'), isFalse);
      // maxBitRate alone flips this server into the chunked transcoder.
      expect(raw.queryParameters.containsKey('maxBitRate'), isFalse);

      final transcoded = Uri.parse(
        client.streamUrl('id1', format: 'mp3', maxBitRate: 192),
      ).queryParameters;
      expect(transcoded['format'], 'mp3');
      expect(transcoded['maxBitRate'], '192');
    });
  });

  group('duration formatting', () {
    test('formats minutes, hours and unknown lengths', () {
      expect(formatClock(325.4), '5:25');
      expect(formatClock(3700), '1:01:40');
      expect(formatClock(0), '0:00');
      expect(formatClock(double.nan), '0:00');
      expect(formatDuration(325.4), '5:25');
      expect(formatDuration(0), '--:--');
    });
  });

  group('multi-address session', () {
    test('round-trips the address list through JSON', () {
      final session = MusicFreeSession(
        baseUrl: Uri.parse('http://192.168.1.10:14533'),
        token: 't',
        username: 'admin',
        clientSalt: 'salt',
        addresses: [
          Uri.parse('http://192.168.1.10:14533'),
          Uri.parse('https://music.example.com'),
        ],
      );
      final restored = MusicFreeSession.fromJson(session.toJson());
      expect(restored, isNotNull);
      expect(restored!.baseUrl, session.baseUrl);
      expect(restored.allAddresses, session.allAddresses);
    });

    test('legacy JSON without addresses still loads', () {
      final restored = MusicFreeSession.fromJson({
        'baseUrl': 'http://10.0.2.2:14533',
        'token': 't',
        'username': 'admin',
        'clientSalt': 'salt',
      });
      expect(restored, isNotNull);
      expect(restored!.allAddresses, [Uri.parse('http://10.0.2.2:14533')]);
    });

    test('allAddresses falls back to baseUrl when empty', () {
      final session = MusicFreeSession(
        baseUrl: Uri.parse('http://10.0.2.2:14533'),
        token: 't',
        username: 'admin',
        clientSalt: 'salt',
      );
      expect(session.allAddresses, [session.baseUrl]);
    });

    test('copyWith keeps credentials while re-pointing the address', () {
      final session = MusicFreeSession(
        baseUrl: Uri.parse('http://192.168.1.10:14533'),
        token: 't',
        username: 'admin',
        subsonicToken: 'abc',
        clientSalt: 'salt',
        addresses: [
          Uri.parse('http://192.168.1.10:14533'),
          Uri.parse('https://music.example.com'),
        ],
      );
      final switched = session.copyWith(
        baseUrl: Uri.parse('https://music.example.com'),
      );
      expect(switched.token, 't');
      expect(switched.subsonicToken, 'abc');
      expect(switched.baseUrl, Uri.parse('https://music.example.com'));
      expect(switched.allAddresses, session.allAddresses);
    });
  });

  group('FNID-managed address pool', () {
    final gateway = Uri.parse('https://myid.fnos.net/app/musicfree/');
    final pool = <Uri>[
      gateway,
      Uri.parse('http://192.168.1.10:14533/'),
      Uri.parse('https://1.2.3.4:14533/'),
    ];

    test('hides the internal pool but keeps it for failover', () {
      final session = MusicFreeSession(
        baseUrl: gateway,
        token: 't',
        username: 'admin',
        clientSalt: 'salt',
        addresses: pool,
        fnConnect: true,
      );
      expect(session.allAddresses, pool);
      expect(session.visibleAddresses, [gateway]);

      final switched = session.copyWith(baseUrl: pool[1]);
      expect(switched.fnConnect, isTrue);
      expect(switched.visibleAddresses, [pool[1]]);
      expect(switched.allAddresses, pool);
    });

    test('round-trips the flag through JSON', () {
      final session = MusicFreeSession(
        baseUrl: gateway,
        token: 't',
        username: 'admin',
        clientSalt: 'salt',
        addresses: pool,
        fnConnect: true,
      );
      final restored = MusicFreeSession.fromJson(session.toJson());
      expect(restored!.fnConnect, isTrue);
      expect(restored.visibleAddresses, [gateway]);
      expect(restored.allAddresses, pool);
    });

    test('recognizes a legacy FN pool saved before the flag existed', () {
      final restored = MusicFreeSession.fromJson({
        'baseUrl': gateway.toString(),
        'token': 't',
        'username': 'admin',
        'clientSalt': 'salt',
        'addresses': [
          pool[1].toString(),
          pool[2].toString(),
        ],
      });
      expect(restored!.fnConnect, isTrue);
      expect(restored.visibleAddresses, [gateway]);
    });

    test('an explicitly ordinary session is never reclassified', () {
      final ordinary = MusicFreeSession(
        baseUrl: gateway,
        token: 't',
        username: 'admin',
        clientSalt: 'salt',
        addresses: pool,
      );
      expect(ordinary.fnConnect, isFalse);
      expect(ordinary.visibleAddresses, pool);
      final restored = MusicFreeSession.fromJson(ordinary.toJson());
      expect(restored!.fnConnect, isFalse);
      expect(restored.visibleAddresses, pool);
    });

    test('a user-maintained backup list is not mistaken for an FN pool', () {
      expect(
        looksLikeFnAddressPool([
          Uri.parse('http://192.168.1.10:14533'),
          Uri.parse('https://music.example.com'),
          Uri.parse('http://10.0.0.5:14533'),
        ]),
        isFalse,
      );
    });
  });
}
