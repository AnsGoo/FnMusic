import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/data/models.dart';

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
}
