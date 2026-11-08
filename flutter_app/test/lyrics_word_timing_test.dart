/// The synced-lyrics view feeds flutter_lyric a word-timed (QRC) source built
/// from plain LRC lines so the highlight sweep ends near the end of singing
/// instead of stretching to the next line's start.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lyric/flutter_lyric.dart' hide LyricLine;

import 'package:musicfly/data/models.dart';
import 'package:musicfly/ui/synced_lyrics.dart';

Lyrics _lyrics(List<(Duration, String)> lines) => Lyrics(
      lines: [for (final (time, text) in lines) LyricLine(time, text)],
      raw: 'raw-lrc',
    );

void main() {
  test('the generated source parses as QRC with word timings', () {
    final lyrics = _lyrics([
      (Duration.zero, '作词 : 某人'),
      (const Duration(milliseconds: 80020), '谁的脚步 近了 谁的脚步 远了'),
      (const Duration(milliseconds: 87250), '我都竖起 耳朵'),
    ]);

    final source = wordTimedSource(lyrics);
    expect(source, contains('[80020,'));
    expect(source, contains('谁的脚步 近了 谁的脚步 远了(80020,'));

    final document = LyricParser.autoDetect(source);
    expect(document.lines, hasLength(3));
    // QRC branch: every line carries explicit word timing.
    for (final line in document.lines) {
      expect(line.words, isNotNull);
      expect(line.words!, isNotEmpty);
    }
    // The first (credit) line is short: its sweep ends around its own
    // estimate, not 80 seconds later at the next line's start.
    final first = document.lines.first;
    expect(first.end, isNotNull);
    expect(first.end!.inMilliseconds, lessThan(4000));
  });

  test('the sweep never runs past the gap to the next line', () {
    final lyrics = _lyrics([
      (const Duration(seconds: 10), '一句很短的话'),
      // Only 1.2s later: the estimated duration must shrink to the gap.
      (const Duration(milliseconds: 11200), '下一句'),
    ]);

    final document = LyricParser.autoDetect(wordTimedSource(lyrics));
    final first = document.lines.first;
    expect(first.end!.inMilliseconds, lessThanOrEqualTo(11200));
    expect(first.end!.inMilliseconds, greaterThan(10000));
  });

  test('long quiet gaps do not stretch the sweep', () {
    // 12-character line at 1:45.83 followed by a 51s interlude (耳朵 verse
    // shape): the sweep must finish within its 12s cap, not at 2:37.
    final lyrics = _lyrics([
      (const Duration(milliseconds: 105830), '直到心房里变得 空空荡荡的'),
      (const Duration(milliseconds: 157110), '所有的感官都要变迟钝'),
    ]);

    final document = LyricParser.autoDetect(wordTimedSource(lyrics));
    final first = document.lines.first;
    final sweep = first.end!.inMilliseconds - 105830;
    expect(sweep, lessThanOrEqualTo(12000));
  });
}
