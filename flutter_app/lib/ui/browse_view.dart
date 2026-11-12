/// The library pane: toolbar, listings, grids and the paging trigger.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'detail_view.dart';
import 'home_view.dart';
import 'theme.dart';
import 'widgets.dart';

class BrowseView extends StatefulWidget {
  const BrowseView({super.key});

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final model = context.read<AppModel>();
    if (!model.canLoadMore) return;
    if (_scroll.position.extentAfter < 500) {
      model.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Column(
          children: [
            _Toolbar(wide: wide),
            const Divider(height: 1, thickness: 1, color: Mf.border),
            Expanded(
              child: _Body(scroll: _scroll, wide: wide),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final hasDetail = model.detail != null;
    // True on phone/narrow windows, where the shell puts navigation in a
    // drawer instead of a permanent rail.
    final hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    final isHome = model.section == Section.home;
    // Home search lives in the toolbar on desktop too (same slot as the other
    // sections); on narrow screens it stays as the in-list row instead.
    final showSearch = !hasDetail && (!isHome || wide);
    final searchField = isHome
        ? MfSearchField(
            value: model.homeQuery,
            placeholder: '综合搜索：歌曲、专辑、艺术家',
            onChanged: model.updateHomeQuery,
            onSubmit: model.submitHomeSearch,
            onClear: model.clearHomeSearch,
          )
        : MfSearchField(
            value: model.query,
            onChanged: model.updateQuery,
            onSubmit: model.submitSearch,
            onClear: model.clearSearch,
          );
    final searchActive = isHome && model.homeSearching;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        hasDrawer ? 8 : (wide ? 24 : 16),
        wide ? 16 : 8,
        wide ? 20 : 12,
        wide ? 12 : 8,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // A detail page replaces the section title / drawer menu with a
              // back button on the standard toolbar left side, so the cover and
              // its title keep their full width and nothing floats over the art.
              if (hasDetail)
                MfIconButton(
                  icon: Icons.arrow_back,
                  size: 38,
                  glyph: 18,
                  tooltip: '返回',
                  onTap: model.back,
                )
              else ...[
                // Phones keep their navigation in the drawer; this button is the
                // visible alternative to swiping in from the left edge.
                if (hasDrawer) ...[
                  MfIconButton(
                    icon: Icons.menu_rounded,
                    size: 38,
                    glyph: 21,
                    tooltip: '打开侧边栏',
                    onTap: () => Scaffold.maybeOf(context)?.openDrawer(),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        model.headerTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Mf.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.headerSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Mf.faint, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasDetail) const Spacer(),
              // On desktop the search sits beside the title; phones get a
              // full-width second row below it.
              if (wide && showSearch) ...[
                SizedBox(width: 228, child: searchField),
                const SizedBox(width: 8),
                MfIconButton(
                  icon: searchActive ? Icons.close_rounded : Icons.search,
                  size: 34,
                  glyph: 17,
                  tooltip: searchActive ? '返回首页' : '搜索',
                  onTap: searchActive
                      ? model.clearHomeSearch
                      : isHome
                      ? model.submitHomeSearch
                      : model.submitSearch,
                ),
              ],
              if (wide)
                MfIconButton(
                  icon: Icons.refresh,
                  size: 34,
                  glyph: 17,
                  tooltip: '刷新',
                  onTap: model.section == Section.home
                      ? () => model.loadHome(force: true)
                      : () => model.load(initial: true),
                ),
            ],
          ),
          if (!wide && showSearch) ...[
            const SizedBox(height: 8),
            SizedBox(height: 38, child: searchField),
          ],
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.scroll, required this.wide});

  final ScrollController scroll;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();

    // The detail drill-down is its own page: refresh reloads the same album,
    // playlist or artist.
    if (model.detail != null) {
      return RefreshIndicator(
        color: Mf.accent,
        backgroundColor: Mf.surface,
        onRefresh: model.reloadDetail,
        child: DetailView(detail: model.detail!, wide: wide),
      );
    }
    if (model.loading && model.tracks.isEmpty && model.albums.isEmpty) {
      return const Center(child: MfSpinner());
    }

    final Widget content = switch (model.section) {
      Section.home => HomeView(),
      Section.tracks || Section.favorites => _trackList(model, wide),
      Section.albums => _albumGrid(model, wide),
      Section.artists => _artistList(model),
      Section.playlists => _playlistGrid(model, wide),
    };

    // Pull-to-refresh. Home re-runs its card loader; other sections re-run the
    // paged loader. While a search is active the same query is re-issued so the
    // gesture means "refresh these results" rather than dumping the query.
    return RefreshIndicator(
      color: Mf.accent,
      backgroundColor: Mf.surface,
      onRefresh: () async {
        if (model.section == Section.home) {
          if (model.homeSearching) {
            await model.submitHomeSearch();
          } else {
            await model.loadHome(force: true);
          }
        } else {
          if (model.searching) {
            await model.submitSearch();
          } else {
            await model.load(initial: true);
          }
        }
      },
      child: content,
    );
  }

  EmptyState _noMatches(String query) => EmptyState(
    icon: Icons.search_off,
    title: '没有找到 “$query”',
    detail: '换个关键词，或检查服务端是否已扫描曲库',
  );

  Widget _trackList(AppModel model, bool wide) {
    final tracks = model.visibleTracks;
    if (!model.loading && tracks.isEmpty) {
      return model.searching
          ? _noMatches(model.query)
          : EmptyState(
              icon: Icons.library_music_outlined,
              title: model.section == Section.favorites ? '还没有收藏' : '曲库是空的',
              detail: '在 Music Free 服务端扫描歌曲后刷新',
            );
    }
    return _PagedList(
      controller: scroll,
      itemCount: tracks.length,
      footer: model.canLoadMore || model.loadingMore,
      builder: (context, index) {
        final track = tracks[index];
        final audio = model.player.state.value;
        return TrackRow(
          track: track,
          index: index,
          coverUrl: model.coverUrl(track.coverId, size: 96),
          fallbackCoverUrl: model.coverUrl(track.album?.id, size: 96),
          active: audio.trackId == track.id,
          playing: audio.trackId == track.id && audio.playing,
          showAlbum: wide,
          onTap: () => model.playFrom(tracks, index),
          onToggleFavorite: () => model.toggleFavorite(track),
        );
      },
    );
  }

  Widget _albumGrid(AppModel model, bool wide) {
    final albums = model.visibleAlbums;
    if (!model.loading && albums.isEmpty) {
      return model.searching
          ? _noMatches(model.query)
          : const EmptyState(
              icon: Icons.album_outlined,
              title: '没有专辑',
              detail: '曲库扫描完成后这里会出现专辑',
            );
    }
    return GridView.builder(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        // Narrow (portrait) screens fit three columns by capping the extent.
        maxCrossAxisExtent: wide ? 196 : 118,
        mainAxisSpacing: 20,
        crossAxisSpacing: 18,
        // Tuned together with _GridCard's Expanded artwork so the cover stays
        // near-square on both narrow and wide layouts while the two text lines
        // always fit inside the cell.
        childAspectRatio: wide ? 0.80 : 0.70,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _GridCard(
          title: album.name,
          subtitle: album.trackCount > 0
              ? '${album.artistLine} · ${album.trackCount} 首'
              : album.artistLine,
          coverUrl: model.coverUrl(album.coverId),
          onTap: () => model.openAlbum(album),
        );
      },
    );
  }

  Widget _playlistGrid(AppModel model, bool wide) {
    final playlists = model.visiblePlaylists;
    if (!model.loading && playlists.isEmpty) {
      return model.searching
          ? _noMatches(model.query)
          : const EmptyState(
              icon: Icons.queue_music,
              title: '还没有歌单',
              detail: '在服务端创建歌单后会显示在这里',
            );
    }
    return GridView.builder(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        // Narrow (portrait) screens fit three columns by capping the extent.
        maxCrossAxisExtent: wide ? 196 : 118,
        mainAxisSpacing: 20,
        crossAxisSpacing: 18,
        // Tuned together with _GridCard's Expanded artwork so the cover stays
        // near-square on both narrow and wide layouts while the two text lines
        // always fit inside the cell.
        childAspectRatio: wide ? 0.80 : 0.70,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _GridCard(
          title: playlist.name,
          subtitle: '${playlist.trackCount ?? 0} 首',
          coverUrl: model.coverUrl(playlist.coverId),
          onTap: () => model.openPlaylist(playlist),
        );
      },
    );
  }

  Widget _artistList(AppModel model) {
    final artists = model.visibleArtists;
    if (!model.loading && artists.isEmpty) {
      return model.searching
          ? _noMatches(model.query)
          : const EmptyState(
              icon: Icons.person_outline,
              title: '没有艺术家',
              detail: '曲库扫描完成后这里会按艺术家归类',
            );
    }
    return ListView.builder(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return _ArtistTile(
          artist: artist,
          coverUrl: model.coverUrl(artist.coverId),
          onTap: () => model.openArtist(artist),
        );
      },
    );
  }
}

class _PagedList extends StatelessWidget {
  const _PagedList({
    required this.controller,
    required this.itemCount,
    required this.builder,
    required this.footer,
  });

  final ScrollController controller;
  final int itemCount;
  final Widget Function(BuildContext, int) builder;
  final bool footer;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      // Lets the pull-to-refresh trigger even when the list is short and
      // would otherwise not be scrollable on Android (ClampingScrollPhysics).
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: itemCount + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= itemCount) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: MfSpinner(size: 16)),
          );
        }
        return builder(context, index);
      },
    );
  }
}

/// Albums and playlists share one tile: square cover, title, a single
/// metadata line, and a play glyph that fades in on hover.
class _GridCard extends StatefulWidget {
  const _GridCard({
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
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
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
            // Grid cells have a fixed height (childAspectRatio). A square
            // AspectRatio + two text lines overflows it when font metrics are
            // taller than the design baseline (12 px on the HarmonyOS emulator,
            // which draws Flutter's yellow overflow banner). Let the artwork
            // absorb the leftover height so the text always fits.
            Expanded(
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

class _ArtistTile extends StatefulWidget {
  const _ArtistTile({
    required this.artist,
    required this.coverUrl,
    required this.onTap,
  });

  final Artist artist;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  State<_ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends State<_ArtistTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? Mf.raised.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              CoverImage(
                url: widget.coverUrl,
                size: 42,
                circular: true,
                iconSize: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Mf.text, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist.trackCount > 0
                          ? '${artist.albumCount} 张专辑 · ${artist.trackCount} 首'
                          : '${artist.albumCount} 张专辑',
                      style: const TextStyle(color: Mf.faint, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Mf.faint),
            ],
          ),
        ),
      ),
    );
  }
}
