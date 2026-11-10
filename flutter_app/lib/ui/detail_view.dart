/// Album and playlist detail: a cover header plus its track list.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

class DetailView extends StatefulWidget {
  const DetailView({super.key, required this.detail, required this.wide});

  final Detail detail;
  final bool wide;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final detail = widget.detail;
    final audio = model.player.state.value;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.wide ? 24 : 16,
            18,
            widget.wide ? 24 : 16,
            14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MfIconButton(
                icon: Icons.arrow_back,
                size: 30,
                glyph: 17,
                tooltip: '返回',
                onTap: model.back,
              ),
              const SizedBox(width: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 26,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: CoverImage(
                  url: model.coverUrl(detail.coverId),
                  size: widget.wide ? 150 : 104,
                  radius: 12,
                  circular: detail.isArtist,
                ),
              ),
              SizedBox(width: widget.wide ? 20 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(
                      detail.isArtist
                          ? '艺术家'
                          : detail.isAlbum
                          ? '专辑'
                          : '歌单',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Mf.text,
                        fontSize: widget.wide ? 26 : 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Subtitle and the play-all action share one row so the
                    // header never grows past the cover's height.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            detail.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Mf.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (detail.isArtist)
                          MfPrimaryButton(
                            label: '播放全部歌曲',
                            icon: Icons.play_arrow_rounded,
                            height: 36,
                            onTap: detail.albums.isEmpty
                                ? null
                                : model.playArtistAll,
                            enabled: detail.albums.isNotEmpty,
                          )
                        else
                          MfPrimaryButton(
                            label: '播放全部',
                            icon: Icons.play_arrow_rounded,
                            height: 36,
                            onTap: detail.tracks.isEmpty
                                ? null
                                : () => model.playFrom(detail.tracks, 0),
                            enabled: detail.tracks.isNotEmpty,
                          ),
                        if (detail.loading) ...[
                          const SizedBox(width: 10),
                          const MfSpinner(size: 16),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Mf.border),
        Expanded(
          child: detail.isArtist
              ? _artistAlbums(model, detail)
              : detail.loading && detail.tracks.isEmpty
              ? const Center(child: MfSpinner())
              : detail.tracks.isEmpty
              ? EmptyState(
                  icon: Icons.music_note_outlined,
                  title: detail.isAlbum ? '这张专辑还没有曲目' : '这个歌单还没有曲目',
                )
              : ListView.builder(
                  controller: _scroll,
                  // Lets pull-to-refresh fire even when the track list is short.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: detail.tracks.length,
                  itemBuilder: (context, index) {
                    final track = detail.tracks[index];
                    return TrackRow(
                      track: track,
                      index: index,
                      coverUrl: model.coverUrl(track.coverId, size: 96),
                      fallbackCoverUrl: model.coverUrl(
                        track.album?.id,
                        size: 96,
                      ),
                      // An album's tracks all share the header art, so the
                      // per-row thumbnail only earns its space in a playlist.
                      showCover: !detail.isAlbum,
                      active: audio.trackId == track.id,
                      playing: audio.trackId == track.id && audio.playing,
                      showAlbum: false,
                      onTap: () => model.playFrom(detail.tracks, index),
                      onToggleFavorite: () => model.toggleFavorite(track),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The artist page's album grid — mirrors the web player's artist view.
  Widget _artistAlbums(AppModel model, Detail detail) {
    if (detail.loading && detail.albums.isEmpty) {
      return const Center(child: MfSpinner());
    }
    if (detail.albums.isEmpty) {
      return const EmptyState(
        icon: Icons.album_outlined,
        title: '暂无专辑',
        detail: '曲库扫描完成后这里会出现这位艺术家的专辑',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Text(
            '专辑',
            style: TextStyle(
              color: Mf.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              // Narrow (portrait) screens fit three columns by capping the
              // extent.
              maxCrossAxisExtent: MediaQuery.sizeOf(context).width < 500
                  ? 118
                  : 196,
              mainAxisSpacing: 20,
              crossAxisSpacing: 18,
              childAspectRatio: 0.74,
            ),
            itemCount: detail.albums.length,
            itemBuilder: (context, index) {
              final album = detail.albums[index];
              return _AlbumTile(
                title: album.name,
                subtitle: album.trackCount > 0 ? '${album.trackCount} 首' : '',
                coverUrl: model.coverUrl(album.coverId),
                onTap: () => model.openAlbum(album),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One album tile on the artist page: square cover with a play glyph that
/// fades in on hover, then title and track count.
class _AlbumTile extends StatefulWidget {
  const _AlbumTile({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(url: widget.coverUrl, radius: 8),
                  if (_hovered)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Mf.bg.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            size: 40,
                            color: Mf.cream,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              widget.title,
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
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Mf.faint, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
