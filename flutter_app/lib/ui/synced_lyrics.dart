/// Scrolling, highlighted lyrics driven by the playhead.
///
/// Rendering is delegated to `flutter_lyric`, which paints the lines on a
/// canvas and keeps the active line anchored while the list eases between
/// entries. This widget only owns the wiring: it feeds the server's LRC into a
/// [LyricController] and forwards the player's position on every tick.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';

import '../audio/player.dart';
import '../data/models.dart';
import 'theme.dart';

class SyncedLyrics extends StatefulWidget {
  const SyncedLyrics({
    super.key,
    required this.lyrics,
    required this.playback,
    this.dense = false,
    this.onSeek,
  });

  final Lyrics lyrics;

  /// The player's published state; position changes move the highlight.
  final ValueListenable<PlaybackState> playback;

  /// Narrow side pane: smaller type and tighter spacing.
  final bool dense;

  /// Called when a line is tapped, so the caller decides whether to seek.
  final ValueChanged<Duration>? onSeek;

  @override
  State<SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<SyncedLyrics> {
  LyricController? _controller;

  @override
  void initState() {
    super.initState();
    _build();
    widget.playback.addListener(_sync);
  }

  @override
  void didUpdateWidget(SyncedLyrics old) {
    super.didUpdateWidget(old);
    if (old.playback != widget.playback) {
      old.playback.removeListener(_sync);
      widget.playback.addListener(_sync);
    }
    if (!identical(old.lyrics, widget.lyrics) ||
        old.lyrics.raw != widget.lyrics.raw) {
      _controller?.dispose();
      _build();
    }
  }

  @override
  void dispose() {
    widget.playback.removeListener(_sync);
    _controller?.dispose();
    super.dispose();
  }

  void _build() {
    final controller = LyricController(
      initialPosition: widget.playback.value.position,
    );
    if (widget.lyrics.raw.isNotEmpty) controller.load(widget.lyrics.raw);
    _controller = controller;
  }

  /// The controller throws once it is disposing, and the player can tick during
  /// the same frame the page is popped — a stale notification is harmless.
  void _sync() {
    final controller = _controller;
    if (controller == null) return;
    controller.setPosition(widget.playback.value.position);
  }

  @override
  Widget build(BuildContext context) {
    return LyricView(
      controller: _controller!,
      preset: _preset(dense: widget.dense),
      onLineTap: (details) => widget.onSeek?.call(details.seekPosition),
    );
  }
}

LyricPreset _preset({required bool dense}) {
  final base = LyricPresets.appleMusic;
  return base.copyWith(
    textStyle: TextStyle(
      fontSize: dense ? 14.5 : 19,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: Mf.muted,
    ),
    activeTextStyle: TextStyle(
      fontSize: dense ? 17 : 23,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: Mf.text,
    ),
    // The sung portion stays cream so the active line reads as one bright
    // block, the way the web player renders it.
    highlight: const LyricHighlight.solid(Mf.text, tailFadeWidth: 14),
    countdown: base.countdown.copyWith(color: Mf.faint),
    edgeFade: LyricEdgeFade.fraction(top: dense ? .14 : .16, bottom: .18),
    lineSpacing: dense ? 18 : 26,
    padding: EdgeInsets.symmetric(horizontal: dense ? 22 : 6),
  );
}
