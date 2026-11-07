/// The lyrics pane: the server's own lyrics, timed when LRC and highlighted
/// against the playhead.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/player.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';
import 'synced_lyrics.dart';

class LyricsPanel extends StatelessWidget {
  const LyricsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return Container(
      color: Mf.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.lyrics_outlined, size: 17, color: Mf.muted),
                const SizedBox(width: 8),
                const Text(
                  '歌词',
                  style: TextStyle(
                    color: Mf.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (model.currentTrack != null)
                  Flexible(
                    child: Text(
                      model.currentTrack!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Mf.faint, fontSize: 12),
                    ),
                  ),
                const SizedBox(width: 8),
                MfIconButton(
                  icon: Icons.close,
                  size: 28,
                  glyph: 15,
                  tooltip: '关闭歌词',
                  onTap: model.hideLyrics,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Mf.border),
          Expanded(
            child: ValueListenableBuilder<PlaybackState>(
              valueListenable: model.player.state,
              builder: (context, audio, _) {
                if (model.lyricsLoading) {
                  return const Center(child: MfSpinner());
                }
                return LyricsBody(
                  lyrics: model.lyrics,
                  playback: model.player.state,
                  dense: true,
                  onSeek: model.seek,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders whatever lyrics the server returned: untimed text scrolls as one
/// column, timed LRC hands over to [SyncedLyrics].
class LyricsBody extends StatelessWidget {
  const LyricsBody({
    super.key,
    required this.lyrics,
    required this.playback,
    this.dense = false,
    this.onSeek,
  });

  final Lyrics? lyrics;
  final ValueListenable<PlaybackState> playback;
  final bool dense;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final lyrics = this.lyrics;
    if (lyrics == null) {
      return EmptyState(
        icon: Icons.lyrics_outlined,
        title: '这首歌没有内嵌歌词',
        detail: dense ? null : '在 Music Free 服务端为歌曲写入歌词后即可显示',
      );
    }
    if (!lyrics.isTimed) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          dense ? 26 : 12,
          dense ? 20 : 8,
          dense ? 26 : 12,
          32,
        ),
        child: Text(
          lyrics.plain ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Mf.textSoft,
            fontSize: dense ? 14 : 15,
            height: 1.9,
          ),
        ),
      );
    }
    return SyncedLyrics(
      lyrics: lyrics,
      playback: playback,
      dense: dense,
      onSeek: onSeek,
    );
  }
}
