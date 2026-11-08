/// The home page: a comprehensive search on top, then cards for hot songs,
/// recently played, albums, artists, playlists and favorites.
///
/// Touch devices show four entries per card, desktop ten; the album, artist,
/// playlist and favorite card titles jump to their full library sections.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    if (model.homeLoading && !_hasHomeData(model) && !model.homeSearching) {
      return const Center(child: MfSpinner());
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final hotCard = _SectionCard(
      title: '热门歌曲',
      subtitle: '播放最多的歌曲',
      child: _HotTracks(model: model),
    );
    final recentCard = _SectionCard(
      title: '最近播放',
      subtitle: '最近在听',
      child: _AlbumRow(model: model, albums: model.homeRecentAlbums),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same threshold as the toolbar (browse_view.dart): on wide panes the
        // home search lives next to the refresh button there, so the in-list
        // row is dropped to keep a single search box on screen.
        final paneWide = constraints.maxWidth >= 760;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (!paneWide) ...[
              _HomeSearch(model: model),
              const SizedBox(height: 18),
            ],
            if (model.homeSearching)
              _SearchResults(model: model, wide: wide)
            else ...[
              // On desktop the two headline cards sit side by side, 50/50.
              if (wide)
                Row(
                  children: [
                    Expanded(child: hotCard),
                    const SizedBox(width: 16),
                    Expanded(child: recentCard),
                  ],
                )
              else ...[
                hotCard,
                recentCard,
              ],
              _SectionCard(
                title: '专辑',
                subtitle: '浏览全部专辑',
                onTitleTap: () => model.select(Section.albums),
                child: _AlbumRow(model: model, albums: model.homeAlbums),
              ),
              _SectionCard(
                title: '艺术家',
                subtitle: '按艺术家浏览',
                onTitleTap: () => model.select(Section.artists),
                child: _ArtistRow(model: model),
              ),
              _SectionCard(
                title: '歌单',
                subtitle: '我的歌单',
                onTitleTap: () => model.select(Section.playlists),
                child: _PlaylistRow(model: model),
              ),
              _SectionCard(
                title: '收藏',
                subtitle: '我喜欢的音乐',
                onTitleTap: () => model.select(Section.favorites),
                child: _FavoriteTracks(model: model),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _hasHomeData(AppModel model) =>
      model.homeHotTracks.isNotEmpty ||
      model.homeRecentAlbums.isNotEmpty ||
      model.homeAlbums.isNotEmpty ||
      model.homeArtists.isNotEmpty ||
      model.homePlaylists.isNotEmpty ||
      model.homeFavorites.isNotEmpty;
}

/// Entries shown per card: 4 on touch devices, 10 on desktop.
int get _cardLimit => isMobilePlatform ? 4 : 10;

/// Card width for the sideways cover rows. [rowWidth] is the real constraint
/// width of the row (measured with a LayoutBuilder, so SafeArea, drawer and
/// desktop rail are all accounted for automatically). On touch devices the
/// visible cards always fill the row exactly: the count is however many fit
/// at a sensible minimum, and when there are fewer items than that each card
/// grows to share the space (no dead gap on landscape phones). Desktop keeps
/// the fixed scrolling row.
double _rowCardWidth(
  double rowWidth,
  int itemCount, {
  double gap = 14,
  double desktopWidth = 128,
}) {
  if (!isMobilePlatform) return desktopWidth;
  const minCard = 88.0;
  final maxFit = ((rowWidth + gap) / (minCard + gap)).floor();
  final n = itemCount < maxFit ? itemCount : maxFit;
  return ((rowWidth - gap * (n - 1)) / n).clamp(minCard, 200.0);
}

// ---- Search -----------------------------------------------------------------

class _HomeSearch extends StatelessWidget {
  const _HomeSearch({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: MfSearchField(
              value: model.homeQuery,
              placeholder: '综合搜索：歌曲、专辑、艺术家',
              onChanged: model.updateHomeQuery,
              onSubmit: model.submitHomeSearch,
            ),
          ),
        ),
        if (model.homeSearching) ...[
          const SizedBox(width: 8),
          MfIconButton(
            icon: Icons.close_rounded,
            size: 34,
            glyph: 18,
            tooltip: '返回首页',
            onTap: model.clearHomeSearch,
          ),
        ],
      ],
    );
  }
}

/// One query, three refreshed groups: songs, albums and artists.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.model, required this.wide});

  final AppModel model;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final result = model.homeSearch;
    final audio = model.player.state.value;
    if (result.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            '没有找到「${model.homeQuery}」',
            style: const TextStyle(color: Mf.muted, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.tracks.isNotEmpty) ...[
          _SectionCard(
            title: '歌曲',
            subtitle: '${result.tracks.length} 个结果',
            child: Column(
              children: [
                for (final (index, track) in result.tracks.indexed)
                  TrackRow(
                    track: track,
                    index: index,
                    coverUrl: model.coverUrl(track.coverId, size: 96),
                    fallbackCoverUrl: model.coverUrl(track.album?.id, size: 96),
                    active: audio.trackId == track.id,
                    playing: audio.trackId == track.id && audio.playing,
                    showAlbum: wide,
                    onTap: () => model.playFrom(result.tracks, index),
                  ),
              ],
            ),
          ),
          _SectionCard(
            title: '专辑',
            subtitle: '${result.albums.length} 个结果',
            child: _AlbumRow(
              model: model,
              albums: result.albums,
              limit: result.albums.length,
            ),
          ),
          if (result.artists.isNotEmpty)
            _SectionCard(
              title: '艺术家',
              subtitle: '${result.artists.length} 个结果',
              child: _ArtistRow(model: model, limit: result.artists.length),
            ),
        ],
      ],
    );
  }
}

// ---- Cards ------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onTitleTap,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Mf.text,
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              subtitle,
              style: const TextStyle(color: Mf.faint, fontSize: 11.5),
            ),
          ),
          const Spacer(),
          if (onTitleTap != null)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('查看全部', style: TextStyle(color: Mf.muted, fontSize: 12)),
                SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 17, color: Mf.muted),
              ],
            ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Mf.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Mf.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          onTitleTap == null
              ? header
              : InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onTitleTap,
                  child: header,
                ),
          child,
        ],
      ),
    );
  }
}

class _HotTracks extends StatelessWidget {
  const _HotTracks({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final tracks = model.homeHotTracks.take(_cardLimit).toList();
    if (tracks.isEmpty) {
      return const _CardEmpty('还没有播放记录，先去曲库挑一首吧');
    }
    return _TrackCardRow(model: model, tracks: tracks);
  }
}

class _FavoriteTracks extends StatelessWidget {
  const _FavoriteTracks({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final tracks = model.homeFavorites.take(_cardLimit).toList();
    if (tracks.isEmpty) {
      return const _CardEmpty('收藏喜欢的歌曲后会显示在这里');
    }
    return _TrackCardRow(model: model, tracks: tracks);
  }
}

/// Songs use the same sideways cover-card row as albums; the card that is
/// currently playing is outlined in the accent colour.
class _TrackCardRow extends StatelessWidget {
  const _TrackCardRow({required this.model, required this.tracks});

  final AppModel model;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final audio = model.player.state.value;
    // Cover cards are square plus a caption block, so the row grows with the
    // card width (which itself fills the row on touch devices).
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _rowCardWidth(constraints.maxWidth, tracks.length);
        return SizedBox(
          height: cardWidth + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final track = tracks[index];
              final active = audio.trackId == track.id;
              return _AlbumCard(
                title: track.title,
                subtitle: track.artistLine,
                coverUrl: model.coverUrl(
                  track.coverId ?? track.album?.id,
                  size: 320,
                ),
                width: cardWidth,
                highlight: active,
                onTap: () => model.playFrom(tracks, index),
              );
            },
          ),
        );
      },
    );
  }
}

/// Square covers scrolling sideways, shared by the album and recent cards.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.model, required this.albums, this.limit});

  final AppModel model;
  final List<Album> albums;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown = albums.take(limit ?? _cardLimit).toList();
    if (shown.isEmpty) {
      return const _CardEmpty('服务端还没有专辑');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _rowCardWidth(constraints.maxWidth, shown.length);
        return SizedBox(
          height: cardWidth + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = shown[index];
              return _AlbumCard(
                title: album.name,
                subtitle: album.artistLine,
                coverUrl: model.coverUrl(album.coverId, size: 320),
                width: cardWidth,
                onTap: () => model.openAlbum(album),
              );
            },
          ),
        );
      },
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final shown = model.homePlaylists.take(_cardLimit).toList();
    if (shown.isEmpty) {
      return const _CardEmpty('还没有歌单');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _rowCardWidth(constraints.maxWidth, shown.length);
        return SizedBox(
          height: cardWidth + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = shown[index];
              return _AlbumCard(
                title: playlist.name,
                subtitle: '${playlist.trackCount ?? 0} 首',
                coverUrl: model.coverUrl(playlist.coverId, size: 320),
                width: cardWidth,
                onTap: () => model.openPlaylist(playlist),
              );
            },
          ),
        );
      },
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.model, this.limit});

  final AppModel model;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown = model.homeArtists.take(limit ?? _cardLimit).toList();
    if (shown.isEmpty) {
      return const _CardEmpty('曲库扫描完成后这里会按艺术家归类');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _rowCardWidth(
          constraints.maxWidth,
          shown.length,
          gap: 18,
          desktopWidth: 92,
        );
        // Circular avatar (width - 8) plus the name/subtitle block.
        return SizedBox(
          height: cardWidth + 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (context, index) {
              final artist = shown[index];
              return _ArtistCard(
                name: artist.name,
                subtitle: artist.trackCount > 0 ? '${artist.trackCount} 首' : '',
                coverUrl: model.coverUrl(artist.coverId, size: 320),
                width: cardWidth,
                onTap: () => model.openArtist(artist),
              );
            },
          ),
        );
      },
    );
  }
}

// ---- Small pieces -----------------------------------------------------------

class _CardEmpty extends StatelessWidget {
  const _CardEmpty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Mf.faint, fontSize: 12.5),
        ),
      ),
    );
  }
}

class _AlbumCard extends StatefulWidget {
  const _AlbumCard({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
    this.width = 128,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final VoidCallback onTap;
  final double width;

  /// The song card that is currently playing.
  final bool highlight;

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverImage(url: widget.coverUrl, radius: 8),
                    if (widget.highlight)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Mf.accent, width: 2),
                          ),
                        ),
                      ),
                    if (_hovered)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Mf.bg.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              size: 34,
                              color: widget.highlight
                                  ? Mf.accentHover
                                  : Mf.cream,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Pin the line height: platform font fallbacks (notably the
                // CJK one on Android) are a hair taller than Roboto's and
                // overflowed the fixed-height card row by 1px.
                style: TextStyle(
                  color: widget.highlight ? Mf.accentHover : Mf.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Mf.faint,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistCard extends StatefulWidget {
  const _ArtistCard({
    required this.name,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
    this.width = 92,
  });

  final String name;
  final String subtitle;
  final String? coverUrl;
  final VoidCallback onTap;
  final double width;

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CoverImage(
                url: widget.coverUrl,
                size: widget.width - 8,
                circular: true,
                iconSize: 30,
              ),
              const SizedBox(height: 9),
              Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _hovered ? Mf.accentHover : Mf.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: const TextStyle(color: Mf.faint, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
