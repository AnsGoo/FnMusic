/// The full-window player reachable from the transport's cover art.
///
/// Layout follows the web player: a blurred copy of the cover fills the
/// background, the left half holds a spinning vinyl disc and the song's
/// credits, the right half scrolls its lyrics, and the transport sits at the
/// bottom of the window.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../audio/player.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import 'cast_sheet.dart' show showCastSheet;
import 'controls.dart';
import 'lyrics_view.dart';
import 'queue_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  double? _scrubSeconds;

  /// Captured in [initState]: `dispose` must not look the provider up again.
  late final MfPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = context.read<AppModel>().player;
    _player.state.addListener(_followPlayback);
    _followPlayback();
  }

  @override
  void dispose() {
    _player.state.removeListener(_followPlayback);
    _spin.dispose();
    super.dispose();
  }

  /// The disc only turns while audio advances, and keeps its angle on pause.
  void _followPlayback() {
    if (!mounted) return;
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): model.closeNowPlaying,
      },
      child: Focus(
        autofocus: true,
        child: ValueListenableBuilder<PlaybackState>(
          valueListenable: model.player.state,
          builder: (context, audio, _) {
            final coverId = audio.coverId;
            return Stack(
              fit: StackFit.expand,
              children: [
                _Backdrop(coverUrl: model.coverUrl(coverId, size: 320)),
                SafeArea(
                  child: Column(
                    children: [
                      _header(model),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Narrow windows stack the credits above the
                              // lyrics, the way the web player does below
                              // 768px.
                              if (constraints.maxWidth < 720) {
                                // On a very short viewport (landscape phone,
                                // split screen) the lyrics panel cannot fit
                                // its empty-state hint alongside the disc and
                                // the two-row transport. Drop the panel and
                                // give that space back to the cover.
                                const coverFlex = 6;
                                const lyricsFlex = 4;
                                final lyricsHeight =
                                    (constraints.maxHeight - 8) *
                                    lyricsFlex /
                                    (coverFlex + lyricsFlex);
                                final showLyrics = lyricsHeight >= 140;
                                return Column(
                                  children: [
                                    // The transport gained a second button
                                    // row on phones, so give the disc a
                                    // little more room back. Tight (Expanded)
                                    // constraints let the disc measure the
                                    // space left after the credits instead of
                                    // overflowing its own column.
                                    Expanded(
                                      flex: coverFlex,
                                      child: _coverColumn(
                                        model,
                                        audio,
                                        compact: true,
                                      ),
                                    ),
                                    if (showLyrics) ...[
                                      const SizedBox(height: 8),
                                      Expanded(
                                        flex: lyricsFlex,
                                        child: _lyricsColumn(model),
                                      ),
                                    ],
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: _coverColumn(model, audio)),
                                  const SizedBox(width: 32),
                                  Expanded(child: _lyricsColumn(model)),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      _transport(model, audio),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(AppModel model) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            onTap: model.closeNowPlaying,
          ),
          const Spacer(),
          const Text(
            '正在播放',
            style: TextStyle(
              color: Mf.faint,
              fontSize: 11.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _CastButton(),
        ],
      ),
    );
  }

  Widget _coverColumn(
    AppModel model,
    PlaybackState audio, {
    bool compact = false,
  }) {
    if (compact) {
      // On a phone the disc must yield to the credits. Sizing it as a fixed
      // fraction (0.72) of this column left no room for the title / artist /
      // album lines below and rendered the "BOTTOM OVERFLOWED BY ... PIXELS"
      // stripe. Let Expanded measure the space the credits leave instead.
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = [
                  constraints.maxWidth * 0.78,
                  constraints.maxHeight - 4,
                  300.0,
                ].reduce((a, b) => a < b ? a : b);
                return Center(
                  child: size > 0
                      ? _disc(model, audio, size)
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
          _credits(model, audio, gap: 20),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop's two-column layout keeps the smaller, lyric-friendly size.
        final size = [
          constraints.maxWidth * 0.62,
          constraints.maxHeight * 0.56,
          300.0,
        ].reduce((a, b) => a < b ? a : b);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _disc(model, audio, size),
            _credits(model, audio, gap: 28),
          ],
        );
      },
    );
  }

  Widget _disc(AppModel model, PlaybackState audio, double size) {
    return _Disc(
      rotation: _spin,
      child: CoverImage(
        url: model.coverUrl(audio.coverId, size: 640),
        size: size,
        circular: true,
        iconSize: size * 0.28,
      ),
    );
  }

  /// Fixed-height text block under the disc. Kept out of the flex sizing so
  /// the disc can never push it past the bottom of the column.
  Widget _credits(AppModel model, PlaybackState audio, {required double gap}) {
    final track = model.currentTrack;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: gap),
        Text(
          audio.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Mf.text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          audio.error ?? track?.artistLine ?? audio.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: audio.error != null ? Mf.accent : Mf.muted,
            fontSize: 13,
          ),
        ),
        if (track?.album?.name case final album? when album.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Mf.muted, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _lyricsColumn(AppModel model) {
    if (model.lyricsLoading) {
      return const Center(child: MfSpinner());
    }
    return LyricsBody(
      lyrics: model.lyrics,
      playback: model.player.state,
      onSeek: model.seek,
    );
  }

  Widget _transport(AppModel model, PlaybackState audio) {
    final duration = audio.duration;
    final durationSeconds = duration.inMilliseconds / 1000;
    final position =
        _scrubSeconds ?? (audio.position.inMilliseconds / 1000).clamp(0.0, 1e9);
    // Five controls plus a volume slider cannot breathe on a phone in
    // portrait. Split them into a primary transport row and a quieter
    // utility row, the way mobile players do.
    final stacked = MediaQuery.sizeOf(context).width < 560;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            stacked ? 20 : 32,
            12,
            stacked ? 20 : 32,
            stacked ? 18 : 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      formatClock(position),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Mf.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MfScrubber(
                      fraction: durationSeconds > 0
                          ? (position / durationSeconds).clamp(0.0, 1.0)
                          : 0,
                      enabled: durationSeconds > 0,
                      onScrub: (fraction) => setState(
                        () => _scrubSeconds = fraction * durationSeconds,
                      ),
                      onCommit: () {
                        final target = _scrubSeconds;
                        setState(() => _scrubSeconds = null);
                        if (target != null) {
                          model.seek(
                            Duration(
                              milliseconds: (target * 1000).round(),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 42,
                    child: Text(
                      formatClock(durationSeconds),
                      style: const TextStyle(
                        color: Mf.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (stacked) ...[
                _primaryRow(model, audio, spaced: true),
                const SizedBox(height: 18),
                _utilityRow(model),
              ] else
                SizedBox(
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _primaryRow(model, audio, spaced: false),
                      if (!isMobilePlatform)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _volumeSlider(model),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The five main controls: play mode, previous, play/pause, next, queue.
  Widget _primaryRow(
    AppModel model,
    PlaybackState audio, {
    required bool spaced,
  }) {
    final buttons = <Widget>[
      MfIconButton(
        icon: playModeIcon(model.playMode),
        size: 44,
        glyph: 22,
        tooltip: playModeLabel(model.playMode),
        onTap: model.cyclePlayMode,
      ),
      MfIconButton(
        icon: Icons.skip_previous_rounded,
        size: 44,
        glyph: 26,
        tooltip: '上一首',
        onTap: model.previous,
      ),
      _PlayButton(playing: audio.playing, onTap: model.togglePlay),
      MfIconButton(
        icon: Icons.skip_next_rounded,
        size: 44,
        glyph: 26,
        tooltip: '下一首',
        onTap: model.next,
      ),
      MfIconButton(
        icon: Icons.queue_music_rounded,
        size: 44,
        glyph: 22,
        tooltip: '播放列表',
        onTap: () => showQueue(context, fromFullPlayer: true),
      ),
    ];
    if (spaced) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: buttons,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          buttons[i],
        ],
      ],
    );
  }

  /// Second row on phones: quieter, smaller, and every button does something
  /// real rather than being an inert "more" placeholder.
  Widget _utilityRow(AppModel model) {
    final track = model.currentTrack;
    final favorite = track?.isFavorite ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        MfIconButton(
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          size: 40,
          glyph: 19,
          color: favorite ? Mf.accent : null,
          tooltip: favorite ? '取消收藏' : '收藏',
          onTap: () {
            if (track != null) model.toggleFavorite(track);
          },
        ),
        MfIconButton(
          icon: Icons.info_outline_rounded,
          size: 40,
          glyph: 19,
          tooltip: '歌曲信息',
          onTap: () => _showTrackInfo(model),
        ),
        MfIconButton(
          icon: Icons.volume_up_rounded,
          size: 40,
          glyph: 19,
          tooltip: '音量',
          onTap: () => _showVolumeSheet(model),
        ),
        MfIconButton(
          icon: model.casting
              ? Icons.cast_connected_rounded
              : Icons.cast_outlined,
          size: 40,
          glyph: 19,
          color: model.casting ? Mf.accentHover : null,
          tooltip: model.casting ? '正在投屏' : '投屏',
          onTap: () => showCastSheet(context),
        ),
      ],
    );
  }

  Widget _volumeSlider(AppModel model) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.volume_up_rounded, size: 16, color: Mf.faint),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: MfScrubber(
            fraction: model.volume,
            thumbColor: Mf.textSoft,
            activeColor: Mf.muted,
            onScrub: model.setVolume,
          ),
        ),
      ],
    );
  }

  void _showVolumeSheet(AppModel model) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Mf.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '音量',
                style: TextStyle(
                  color: Mf.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.volume_down_rounded,
                    size: 18,
                    color: Mf.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: model,
                      builder: (_, _) => MfScrubber(
                        fraction: model.volume,
                        thumbColor: Mf.textSoft,
                        activeColor: Mf.accent,
                        onScrub: model.setVolume,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: Mf.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTrackInfo(AppModel model) {
    final track = model.currentTrack;
    if (track == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Mf.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Mf.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                track.artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Mf.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Mf.border),
              const SizedBox(height: 8),
              _infoRow('专辑', track.album?.name),
              _infoRow('时长', track.durationLabel),
              _infoRow('格式', track.format?.toUpperCase()),
              _infoRow('来自', model.queueSource),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(color: Mf.muted, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value.isEmpty) ? '—' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Mf.textSoft, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cover scaled up, blurred and dimmed behind the whole page.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Mf.bg),
        if (url != null && url.isNotEmpty)
          Opacity(
            opacity: 0.34,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 64, sigmaY: 64),
              child: Transform.scale(
                scale: 1.2,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xDE131010), Color(0xB8131010), Color(0xEA131010)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// A vinyl record: the cover clipped to a circle, groove rings and a spindle.
class _Disc extends StatelessWidget {
  const _Disc({required this.rotation, required this.child});

  final Animation<double> rotation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: rotation,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 44,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _GroovePainter()),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Mf.surfaceAlt,
              border: Border.all(color: Mf.border, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.16],
        ).createShader(rect),
    );

    for (final ring in const [0.62, 0.74]) {
      canvas.drawCircle(
        center,
        radius * ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.045
          ..color = const Color(0x2E000000),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33FFFFFF),
    );
    canvas.drawCircle(
      center,
      radius * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.6
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0x00000000), Color(0x24000000)],
          stops: [0, 0.72, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GroovePainter oldDelegate) => false;
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Mf.accentHover, Mf.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x522A1009),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 30,
            color: Mf.cream,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered ? Mf.raised : Mf.surfaceAlt,
            border: Border.all(color: Mf.border),
          ),
          child: Icon(widget.icon, size: 19, color: Mf.textSoft),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Opens the cast sheet from the player page's top-right corner.
class _CastButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final casting = context.watch<AppModel>().casting;
    return _CircleButton(
      icon: Icons.cast_outlined,
      tooltip: casting ? '投屏中' : '投屏',
      onTap: () => showCastSheet(context),
    );
  }
}
