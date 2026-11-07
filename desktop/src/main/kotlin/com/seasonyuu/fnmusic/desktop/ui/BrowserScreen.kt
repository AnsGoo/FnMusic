package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seasonyuu.fnmusic.core.model.Album
import com.seasonyuu.fnmusic.core.model.Artist
import com.seasonyuu.fnmusic.core.model.Playlist
import com.seasonyuu.fnmusic.core.model.Track
import com.seasonyuu.fnmusic.desktop.AppModel
import com.seasonyuu.fnmusic.desktop.Detail
import com.seasonyuu.fnmusic.desktop.Section
import org.jetbrains.skia.Image as SkiaImage

private val brandMark: ImageBitmap? by lazy {
    runCatching {
        Thread.currentThread().contextClassLoader
            ?.getResourceAsStream("music_free_logo.png")
            ?.use { SkiaImage.makeFromEncoded(it.readBytes()).toComposeImageBitmap() }
    }.getOrNull()
}

/**
 * The library window: navigation rail, listing pane and transport bar.
 *
 * The rail is fixed, the listing scrolls, and the player is pinned to the
 * bottom edge across the full width, mirroring the shape of the phone app on a
 * much wider canvas.
 */
@Composable
fun BrowserScreen(model: AppModel) {
    Column(Modifier.fillMaxSize().background(Fn.bg)) {
        Row(Modifier.weight(1f).fillMaxWidth()) {
            Sidebar(model)
            Box(Modifier.width(1.dp).fillMaxHeight().background(Fn.border))
            ContentPane(model, Modifier.weight(1f).fillMaxHeight())
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Fn.border))
        PlayerBar(model)
    }
}

// ---- Rail -----------------------------------------------------------------

@Composable
private fun Sidebar(model: AppModel) {
    Column(
        modifier = Modifier.width(214.dp).fillMaxHeight().background(Fn.surface).padding(vertical = 18.dp),
    ) {
        Row(
            modifier = Modifier.padding(start = 18.dp, end = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val mark = brandMark
            if (mark != null) {
                Image(
                    bitmap = mark,
                    contentDescription = null,
                    modifier = Modifier.size(28.dp).clip(RoundedCornerShape(percent = 50)),
                )
            } else {
                FnGlyph(FnIcon.Album, size = 26.dp, tint = Fn.accent)
            }
            Spacer(Modifier.width(10.dp))
            Column {
                Text("Music Free", color = Fn.text, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    model.session?.hostLabel ?: "",
                    color = Fn.faint,
                    fontSize = 10.5.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Spacer(Modifier.height(26.dp))
        SectionLabel("浏览", Modifier.padding(start = 20.dp, bottom = 8.dp))

        val iconOf = mapOf(
            Section.Tracks to FnIcon.Tracks,
            Section.Albums to FnIcon.Album,
            Section.Artists to FnIcon.Artist,
            Section.Playlists to FnIcon.Playlist,
            Section.Favorites to FnIcon.Heart,
        )
        Section.entries.forEach { entry ->
            NavItem(
                label = entry.label,
                icon = iconOf.getValue(entry),
                selected = model.section == entry && model.detail == null && !model.searching,
                onClick = { model.select(entry) },
            )
        }

        Spacer(Modifier.weight(1f))

        if (model.detail != null) {
            NavItem(
                label = "返回列表",
                icon = FnIcon.Back,
                selected = false,
                onClick = { model.back() },
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 14.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    model.session?.username.orEmpty(),
                    color = Fn.textSoft,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text("已连接", color = Fn.faint, fontSize = 10.5.sp)
            }
            FnIconButton(FnIcon.Logout, onClick = { model.logout() }, size = 30.dp, glyph = 15.dp)
        }
    }
}

@Composable
private fun NavItem(label: String, icon: FnIcon, selected: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val fill = when {
        selected -> Fn.accentWash
        hovered -> Fn.surfaceAlt
        else -> Fn.surface
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 1.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(fill)
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        FnGlyph(icon, size = 16.dp, tint = if (selected) Fn.accent else Fn.textSoft)
        Text(
            label,
            color = if (selected) Fn.text else Fn.textSoft,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
        )
    }
}

// ---- Listing --------------------------------------------------------------

@Composable
private fun ContentPane(model: AppModel, modifier: Modifier = Modifier) {
    Column(modifier.background(Fn.bg)) {
        TopBar(model)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            val detail = model.detail
            when {
                model.searching -> SearchPane(model)
                detail != null -> DetailPane(model, detail)
                model.loading && model.albums.isEmpty() && model.tracks.isEmpty() &&
                    model.artists.isEmpty() && model.playlists.isEmpty() && model.favorites.isEmpty() -> EmptyState("正在加载…")
                model.section == Section.Albums -> AlbumGrid(model)
                model.section == Section.Artists -> ArtistList(model)
                model.section == Section.Playlists -> PlaylistGrid(model)
                model.section == Section.Favorites ->
                    if (model.favorites.isEmpty()) EmptyState("还没有收藏的歌曲") else TrackList(model, model.favorites)
                else -> if (model.tracks.isEmpty()) EmptyState("曲库是空的") else TrackList(model, model.tracks)
            }
        }
    }
}

@Composable
private fun TopBar(model: AppModel) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(start = 24.dp, end = 20.dp, top = 16.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // A drill-down repeats its title in the header below, so the bar only
        // carries the search field there.
        if (model.detail != null) {
            Spacer(Modifier.weight(1f))
        } else {
            Column(Modifier.weight(1f)) {
                val title = if (model.searching) "搜索 “${model.query}”" else model.section.label
                val subtitle = when {
                    model.searching -> "${model.searchResults.size} 个结果"
                    model.section == Section.Tracks -> "${model.tracks.size} / 共 ${model.total} 首"
                    else -> model.section.subtitle
                }
                Text(
                    title,
                    color = Fn.text,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(subtitle, color = Fn.faint, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }

        FnSearchField(
            value = model.query,
            onValueChange = { model.updateQuery(it) },
            onSubmit = { model.submitSearch() },
            onClear = { model.clearSearch() },
            modifier = Modifier.width(228.dp),
        )
        FnIconButton(FnIcon.Search, onClick = { model.submitSearch() }, size = 34.dp, glyph = 16.dp)
        FnIconButton(FnIcon.Refresh, onClick = { model.load(initial = true) }, size = 34.dp, glyph = 16.dp)
    }
}

@Composable
private fun EmptyState(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            FnGlyph(FnIcon.Album, size = 34.dp, tint = Fn.faint)
            Spacer(Modifier.height(12.dp))
            Text(text, color = Fn.muted, fontSize = 13.sp)
        }
    }
}

// ---- Track rows -----------------------------------------------------------

@Composable
private fun TrackList(model: AppModel, tracks: List<Track>) {
    val state = rememberLazyListState()
    val audio by model.player.state.collectAsState()
    val playingId = audio.trackId

    // Paging: ask for the next page once the tail of the list is on screen.
    val nearEnd by remember(tracks.size) {
        derivedStateOf {
            val last = state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1
            last >= tracks.size - 8
        }
    }
    LaunchedEffect(nearEnd, tracks.size) {
        if (nearEnd && model.canLoadMore) model.loadMore()
    }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(state = state, modifier = Modifier.fillMaxSize()) {
            itemsIndexed(tracks, key = { index, track -> "${track.id.value}-$index" }) { index, track ->
                TrackRow(
                    index = index,
                    track = track,
                    active = track.id.value == playingId,
                    coverUrl = model.coverUrl(track.coverId),
                    onPlay = { model.playFrom(tracks, index) },
                )
            }
            item {
                if (model.loadingMore) {
                    Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) {
                        Text("正在加载…", color = Fn.faint, fontSize = 11.5.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun TrackRow(
    index: Int,
    track: Track,
    active: Boolean,
    coverUrl: String?,
    onPlay: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (hovered) Fn.surfaceAlt else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) { onPlay() }
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(30.dp), contentAlignment = Alignment.Center) {
            if (hovered || active) {
                FnGlyph(if (active) FnIcon.Volume else FnIcon.Play, size = 13.dp, tint = Fn.accent)
            } else {
                Text("${index + 1}", color = Fn.faint, fontSize = 11.5.sp)
            }
        }
        CoverArt(coverUrl, size = 38.dp, corner = 5.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(2f)) {
            Text(
                track.title,
                color = if (active) Fn.accent else Fn.text,
                fontSize = 13.sp,
                fontWeight = if (active) FontWeight.Medium else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                track.artists.joinToString(" / ") { it.name }.ifBlank { "未知艺术家" },
                color = Fn.faint,
                fontSize = 11.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            track.album?.name.orEmpty(),
            color = Fn.muted,
            fontSize = 11.5.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1.2f),
        )
        if (track.isFavorite) {
            FnGlyph(FnIcon.Heart, size = 12.dp, tint = Fn.accent)
            Spacer(Modifier.width(14.dp))
        }
        Text(
            formatTime(track.durationSeconds),
            color = Fn.faint,
            fontSize = 11.5.sp,
            modifier = Modifier.padding(start = 14.dp, end = 4.dp),
        )
    }
}

// ---- Detail ---------------------------------------------------------------

@Composable
private fun DetailPane(model: AppModel, detail: Detail) {
    Column(Modifier.fillMaxSize()) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp)) {
            CoverArt(model.coverUrl(detail.coverId), size = 132.dp, corner = 10.dp)
            Spacer(Modifier.width(20.dp))
            Column(Modifier.weight(1f).padding(top = 6.dp)) {
                Text(
                    detail.title,
                    color = Fn.text,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(6.dp))
                Text(detail.subtitle, color = Fn.muted, fontSize = 12.5.sp)
                Spacer(Modifier.height(18.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    FnPrimaryButton(
                        label = "播放全部",
                        onClick = { model.playFrom(detail.tracks, 0) },
                        enabled = detail.tracks.isNotEmpty(),
                        height = 36.dp,
                        modifier = Modifier.width(110.dp),
                    )
                    FnGhostButton(label = "返回", icon = FnIcon.Back, onClick = { model.back() })
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        if (detail.loading) {
            EmptyState("正在加载曲目…")
        } else if (detail.tracks.isEmpty()) {
            EmptyState("这个列表还没有歌曲")
        } else {
            TrackList(model, detail.tracks)
        }
    }
}

// ---- Grids ----------------------------------------------------------------

@Composable
private fun AlbumGrid(model: AppModel) {
    val state = rememberLazyGridState()
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 190.dp),
        state = state,
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, bottom = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        items(model.albums, key = { it.id.value }) { album ->
            AlbumCard(album, model) { model.openAlbum(album) }
        }
    }
}

@Composable
private fun AlbumCard(album: Album, model: AppModel, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(if (hovered) Fn.surfaceAlt else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(6.dp),
    ) {
        CoverArt(
            url = model.coverUrl(album.coverId),
            modifier = Modifier.fillMaxWidth().aspectRatio(1f),
            corner = 8.dp,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            album.name,
            color = Fn.text,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            album.artists.joinToString(" / ") { it.name }.ifBlank { "未知艺术家" },
            color = Fn.faint,
            fontSize = 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PlaylistGrid(model: AppModel) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 190.dp),
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, bottom = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        if (model.playlists.isEmpty() && !model.loading) {
            item { EmptyState("还没有歌单") }
        }
        items(model.playlists, key = { it.id.value }) { playlist ->
            PlaylistCard(playlist, model) { model.openPlaylist(playlist) }
        }
    }
}

@Composable
private fun PlaylistCard(playlist: Playlist, model: AppModel, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(if (hovered) Fn.surfaceAlt else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(6.dp),
    ) {
        CoverArt(
            url = model.coverUrl(playlist.coverId),
            modifier = Modifier.fillMaxWidth().aspectRatio(1f),
            corner = 8.dp,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            playlist.name,
            color = Fn.text,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text("${playlist.trackCount ?: 0} 首", color = Fn.faint, fontSize = 11.sp)
    }
}

@Composable
private fun ArtistList(model: AppModel) {
    val state = rememberLazyListState()
    LazyColumn(state = state, modifier = Modifier.fillMaxSize()) {
        itemsIndexed(model.artists, key = { _, artist -> artist.id.value }) { _, artist ->
            ArtistRow(artist, model)
        }
    }
}

@Composable
private fun ArtistRow(artist: Artist, model: AppModel) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (hovered) Fn.surfaceAlt else Color.Transparent)
            .padding(horizontal = 8.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CoverArt(model.coverUrl(artist.coverId), size = 40.dp, circular = true)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(artist.name, color = Fn.text, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                if (artist.trackCount > 0) "${artist.albumCount} 张专辑 · ${artist.trackCount} 首" else "${artist.albumCount} 张专辑",
                color = Fn.faint,
                fontSize = 11.5.sp,
            )
        }
    }
}

@Composable
private fun SearchPane(model: AppModel) {
    if (model.loading) {
        EmptyState("正在搜索…")
    } else if (model.searchResults.isEmpty()) {
        EmptyState("没有找到匹配的歌曲")
    } else {
        TrackList(model, model.searchResults)
    }
}
