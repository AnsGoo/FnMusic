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

class _PlayerBarState extends State<PlayerBar> {
  double? _scrubSeconds;

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
            color: Fn.surface,
            border: Border(top: BorderSide(color: Fn.border)),
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
                  FnIconButton(
                    icon: Icons.skip_previous_rounded,
                    size: 30,
                    glyph: 20,
                    tooltip: '上一首',
                    onTap: model.previous,
                  ),
                  const SizedBox(width: 4),
                  _playButton(model, audio),
                  const SizedBox(width: 4),
                  FnIconButton(
                    icon: Icons.skip_next_rounded,
                    size: 30,
                    glyph: 20,
                    tooltip: '下一首',
                    onTap: model.next,
                  ),
                  const SizedBox(width: 6),
                  FnIconButton(
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
                        color: Fn.faint,
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
                        color: Fn.faint,
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.volume_up_rounded, size: 16, color: Fn.faint),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: FnScrubber(
                  fraction: model.volume,
                  thumbColor: Fn.textSoft,
                  activeColor: Fn.muted,
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
            FnIconButton(
              icon: Icons.skip_previous_rounded,
              size: 30,
              glyph: 20,
              onTap: model.previous,
            ),
            _playButton(model, audio),
            FnIconButton(
              icon: Icons.skip_next_rounded,
              size: 30,
              glyph: 20,
              onTap: model.next,
            ),
            FnIconButton(
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
    return FnScrubber(
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
        CoverImage(url: coverUrl, size: coverSize, radius: 6),
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
                  color: Fn.text,
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
                  color: audio.error != null ? Fn.accent : Fn.faint,
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
          color: Fn.accent,
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 22,
          color: Fn.cream,
        ),
      ),
    );
  }
}
