/// The persistent transport at the bottom of the window.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/player.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key, required this.wide});

  final bool wide;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar>
    with SingleTickerProviderStateMixin {
  double? _scrubSeconds;

  /// Captured in [initState]: `dispose` must not look the provider up again.
  late final MfPlayer _player;

  /// The cover turns like a record while audio advances, mirroring the web
  /// transport. It keeps its angle when paused.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void initState() {
    super.initState();
    _player = context.read<AppModel>().player;
    _player.state.addListener(_syncSpin);
    _syncSpin();
  }

  @override
  void dispose() {
    _player.state.removeListener(_syncSpin);
    _spin.dispose();
    super.dispose();
  }

  void _syncSpin() {
    final playing = _player.state.value.playing;
    if (playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: model.player.state,
      builder: (context, audio, _) {
        if (!audio.hasTrack) {
          return const SizedBox.shrink();
        }
        final duration = audio.duration.inMilliseconds > 0
            ? audio.duration
            : Duration.zero;
        final durationSeconds = duration.inMilliseconds / 1000;
        final position = _scrubSeconds ??
            (audio.position.inMilliseconds / 1000).clamp(0.0, 1e9);

        return Container(
          decoration: const BoxDecoration(
            color: Mf.surface,
            border: Border(top: BorderSide(color: Mf.border)),
          ),
          padding: EdgeInsets.fromLTRB(
            widget.wide ? 18 : 12,
            widget.wide ? 10 : 8,
            widget.wide ? 18 : 12,
            widget.wide ? 10 : 8,
          ),
          child: widget.wide
              ? _wideLayout(model, audio, position, durationSeconds)
              : _compactLayout(model, audio, position, durationSeconds),
        );
      },
    );
  }

  Widget _wideLayout(
    AppModel model,
    PlaybackState audio,
    double position,
    double durationSeconds,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _nowPlaying(model, audio, 46),
        ),
        Expanded(
          flex: 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MfIconButton(
                    icon: Icons.skip_previous_rounded,
                    size: 30,
                    glyph: 20,
                    tooltip: '上一首',
                    onTap: model.previous,
                  ),
                  const SizedBox(width: 4),
                  _playButton(model, audio),
                  const SizedBox(width: 4),
                  MfIconButton(
                    icon: Icons.skip_next_rounded,
                    size: 30,
                    glyph: 20,
                    tooltip: '下一首',
                    onTap: model.next,
                  ),
                  const SizedBox(width: 6),
                  MfIconButton(
                    icon: Icons.lyrics_outlined,
                    size: 30,
                    glyph: 17,
                    tooltip: '歌词',
                    onTap: model.showLyrics,
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      formatClock(position),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Mf.faint,
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _scrubber(model, position, durationSeconds),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 38,
                    child: Text(
                      formatClock(durationSeconds),
                      style: const TextStyle(
                        color: Mf.faint,
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 17,
                child: Center(
                  child: _InlineLyric(model: model, position: audio.position),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.volume_up_rounded, size: 16, color: Mf.faint),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: MfScrubber(
                  fraction: model.volume,
                  thumbColor: Mf.textSoft,
                  activeColor: Mf.muted,
                  onScrub: model.setVolume,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactLayout(
    AppModel model,
    PlaybackState audio,
    double position,
    double durationSeconds,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: _nowPlaying(model, audio, 40)),
            MfIconButton(
              icon: Icons.skip_previous_rounded,
              size: 30,
              glyph: 20,
              onTap: model.previous,
            ),
            _playButton(model, audio),
            MfIconButton(
              icon: Icons.skip_next_rounded,
              size: 30,
              glyph: 20,
              onTap: model.next,
            ),
            MfIconButton(
              icon: Icons.lyrics_outlined,
              size: 30,
              glyph: 17,
              onTap: model.showLyrics,
            ),
          ],
        ),
        const SizedBox(height: 2),
        _scrubber(model, position, durationSeconds),
      ],
    );
  }

  /// Shared by both layouts: dragging previews a position, releasing seeks.
  Widget _scrubber(AppModel model, double position, double durationSeconds) {
    return MfScrubber(
      fraction: durationSeconds > 0
          ? (position / durationSeconds).clamp(0.0, 1.0)
          : 0,
      enabled: durationSeconds > 0,
      onScrub: (fraction) =>
          setState(() => _scrubSeconds = fraction * durationSeconds),
      onCommit: () {
        final target = _scrubSeconds;
        setState(() => _scrubSeconds = null);
        if (target != null) {
          model.seek(Duration(milliseconds: (target * 1000).round()));
        }
      },
    );
  }

  Widget _nowPlaying(AppModel model, PlaybackState audio, double coverSize) {
    final coverUrl = model.coverUrl(audio.coverId);
    return Row(
      children: [
        Tooltip(
          message: '查看播放详情',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: model.openNowPlaying,
              child: SizedBox(
                width: coverSize,
                height: coverSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RotationTransition(
                      turns: _spin,
                      child: CoverImage(
                        url: coverUrl,
                        size: coverSize,
                        circular: true,
                        iconSize: coverSize * 0.42,
                      ),
                    ),
                    IgnorePointer(
                      child: Container(
                        width: coverSize * 0.14,
                        height: coverSize * 0.14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Mf.bg,
                          border: Border.all(color: Mf.border, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                audio.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Mf.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                audio.error ?? audio.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: audio.error != null ? Mf.accent : Mf.faint,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playButton(AppModel model, PlaybackState audio) {
    final playing = audio.playing;
    return GestureDetector(
      onTap: model.togglePlay,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Mf.accent,
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 22,
          color: Mf.cream,
        ),
      ),
    );
  }
}

/// One line of the current lyric under the progress bar, matching the web
/// transport. It reserves its height so the bar never jumps.
class _InlineLyric extends StatelessWidget {
  const _InlineLyric({required this.model, required this.position});

  final AppModel model;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final lyrics = model.lyrics;
    final index = lyrics != null && lyrics.isTimed
        ? lyrics.indexAt(position)
        : -1;
    final text = index < 0 ? null : lyrics!.lines[index].text;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: text == null
          ? const SizedBox.shrink()
          : Text(
              text,
              key: ValueKey(text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Mf.muted, fontSize: 11.5),
            ),
    );
  }
}
