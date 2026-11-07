/// The lyrics pane: the server's own lyrics, timed when LRC and highlighted
/// against the playhead.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/player.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

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
                final lyrics = model.lyrics;
                if (lyrics == null) {
                  return const EmptyState(
                    icon: Icons.lyrics_outlined,
                    title: '这首歌没有内嵌歌词',
                    detail: '在 Music Free 服务端为歌曲写入歌词后即可显示',
                  );
                }
                if (!lyrics.isTimed) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                    child: Text(
                      lyrics.plain ?? '',
                      style: const TextStyle(
                        color: Mf.textSoft,
                        fontSize: 14,
                        height: 1.9,
                      ),
                    ),
                  );
                }
                return _TimedLyrics(lyrics: lyrics, position: audio.position);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimedLyrics extends StatefulWidget {
  const _TimedLyrics({required this.lyrics, required this.position});

  final Lyrics lyrics;
  final Duration position;

  @override
  State<_TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends State<_TimedLyrics> {
  static const _lineHeight = 42.0;
  final _scroll = ScrollController();
  int _lastIndex = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index) {
    if (index == _lastIndex) return;
    _lastIndex = index;
    if (index < 0 || !_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final target = (index * _lineHeight) - viewport / 2 + _lineHeight / 2;
    final clamped = target.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      clamped,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.lyrics.indexAt(widget.position);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(activeIndex));
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      itemCount: widget.lyrics.lines.length,
      itemExtent: _lineHeight,
      itemBuilder: (context, index) {
        final line = widget.lyrics.lines[index];
        final active = index == activeIndex;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<AppModel>().seek(line.time),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: active ? Mf.accent : Mf.muted,
                fontSize: active ? 17 : 14.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                height: 1.4,
              ),
              child: Text(
                line.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }
}
