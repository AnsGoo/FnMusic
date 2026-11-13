/// The persistent transport at the bottom of the window.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/player.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import 'cast_sheet.dart';
import 'controls.dart';
import 'queue_sheet.dart';
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
          decoration: widget.wide
              ? const BoxDecoration(
                  color: Mf.surface,
                  border: Border(top: BorderSide(color: Mf.border)),
                )
              : null,
          padding: EdgeInsets.fromLTRB(
            widget.wide ? 18 : 10,
            widget.wide ? 10 : 4,
            widget.wide ? 18 : 10,
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
    // Mirror of everything right of the scrubber: the total clock (38) + gap
    // (10) + gap (14) + favourite button (30) + gap (10) + cast button (30)
    // on mobile, plus the volume icon and slider (16+8+96+10) on desktop. The
    // transport buttons and the inline lyric centre over this span so they
    // line up with the scrubber.
    // +40 for the queue button (30dp + 10dp gap) added after the cast button.
    final rightSpan = (isMobilePlatform ? 132.0 : 262.0) + 40.0;
    return Row(
      children: [
        // Like the web transport (flex: 1.2 middle): the song info and the
        // volume control only take the width they need, so the progress
        // column absorbs every remaining pixel.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: _nowPlaying(model, audio, 46),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The transport buttons are centered over the scrubber, not
              // over the whole column: the progress row has a 38px clock
              // (+10 gap) on the left and a 38px clock (+10+14 gap), the
              // cast button, the volume icon and the 96px volume slider on
              // the right, so mirror those spans to find the scrubber's
              // true center.
              Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Row(
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
                      ],
                    ),
                  ),
                  SizedBox(width: rightSpan),
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
                  const SizedBox(width: 14),
                  _FavoriteBarButton(
                    favorite: model.currentTrack?.isFavorite ?? false,
                    visible: model.currentTrack != null,
                    onTap: () {
                      final track = model.currentTrack;
                      if (track != null) model.toggleFavorite(track);
                    },
                  ),
                  const SizedBox(width: 10),
                  MfIconButton(
                    icon: Icons.cast_rounded,
                    size: 30,
                    glyph: 18,
                    color: model.casting ? Mf.accentHover : null,
                    tooltip: model.casting ? '正在投屏' : '投屏',
                    onTap: () => showCastSheet(context),
                  ),
                  const SizedBox(width: 10),
                  MfIconButton(
                    icon: Icons.queue_music_rounded,
                    size: 30,
                    glyph: 18,
                    tooltip: '播放列表',
                    onTap: () => showQueueSheet(context),
                  ),
                  if (!isMobilePlatform) ...[
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 16,
                      color: Mf.faint,
                    ),
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
                ],
              ),
              SizedBox(
                height: 17,
                // Same mirror spans as the transport row: centre the lyric
                // over the scrubber's true span, not the whole column.
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Center(
                        child: _InlineLyric(
                          model: model,
                          position: audio.position,
                        ),
                      ),
                    ),
                    SizedBox(width: rightSpan),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A floating pill on phones. Five controls used to share this row with the
  /// song info, leaving the title about 100dp on a 360dp screen; only play and
  /// the queue stay here, and the removed controls live in the full player's
  /// second button row (see now_playing.dart).
  Widget _compactLayout(
    AppModel model,
    PlaybackState audio,
    double position,
    double durationSeconds,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Mf.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Mf.border.withValues(alpha: 0.8)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _nowPlaying(model, audio, 40)),
              const SizedBox(width: 6),
              _playButton(model, audio),
              const SizedBox(width: 2),
              MfIconButton(
                icon: Icons.queue_music_rounded,
                size: 34,
                glyph: 21,
                tooltip: '播放列表',
                onTap: () => showQueueSheet(context),
              ),
            ],
          ),
          // A childless CustomPaint collapses to zero width in loose
          // constraints, so give the scrubber a tight row or it renders as a
          // lone dot (most visible in landscape, where this bar shows alone).
          SizedBox(
            height: 16,
            child: Row(
              children: [
                Expanded(child: _scrubber(model, position, durationSeconds)),
              ],
            ),
          ),
        ],
      ),
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
        // Loose fit: inside the wide bar the info section hugs its content
        // (capped by the caller), inside the compact bar it still gets the
        // whole row from the parent Expanded.
        Flexible(
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
                  color: audio.error != null ? Mf.accent : Mf.muted,
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

/// Heart toggle for the transport: filled accent when the current song is
/// starred, an outline otherwise. Hidden while nothing is queued.
class _FavoriteBarButton extends StatelessWidget {
  const _FavoriteBarButton({
    required this.favorite,
    required this.visible,
    required this.onTap,
  });

  final bool favorite;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: 30);
    return MfIconButton(
      icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: 30,
      glyph: 18,
      color: favorite ? Mf.accent : null,
      tooltip: favorite ? '取消收藏' : '收藏',
      onTap: onTap,
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
