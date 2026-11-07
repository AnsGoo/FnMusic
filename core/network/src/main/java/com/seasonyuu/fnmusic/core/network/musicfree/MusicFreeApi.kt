package com.seasonyuu.fnmusic.core.network.musicfree

import com.seasonyuu.fnmusic.core.model.MusicError
import com.seasonyuu.fnmusic.core.network.ApiEnvelope
import com.seasonyuu.fnmusic.core.network.AlbumDto
import com.seasonyuu.fnmusic.core.network.ArtistDto
import com.seasonyuu.fnmusic.core.network.FavoriteRequest
import com.seasonyuu.fnmusic.core.network.LyricDataDto
import com.seasonyuu.fnmusic.core.network.LyricDto
import com.seasonyuu.fnmusic.core.network.PageDto
import com.seasonyuu.fnmusic.core.network.PlaylistCreateRequest
import com.seasonyuu.fnmusic.core.network.PlaylistDto
import com.seasonyuu.fnmusic.core.network.PlaylistEditRequest
import com.seasonyuu.fnmusic.core.network.PlaylistGuidRequest
import com.seasonyuu.fnmusic.core.network.PlaylistTracksRequest
import com.seasonyuu.fnmusic.core.network.RoamDto
import com.seasonyuu.fnmusic.core.network.RoamItemDto
import com.seasonyuu.fnmusic.core.network.SearchSuggestionsDto
import com.seasonyuu.fnmusic.core.network.SuggestionGroupDto
import com.seasonyuu.fnmusic.core.network.TrackDto
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Adapts the six supported Music Free library domains to the fnOS-shaped
 * [MusicApi] contract, so every existing repository, screen and player path
 * keeps working without knowing which backend is active.
 *
 * Endpoints without server-side paging (starred, playlists, album/artist/playlist
 * contents, play history) are paged in memory on the 1-based page numbers that
 * [ApiPagingSource] uses.
 */
internal class MusicFreeApi(private val client: MusicFreeClient) : UnsupportedMusicApi() {

    private val playlistCache = ConcurrentHashMap<String, PlaylistDto>()
    private val artistTrackCache = ConcurrentHashMap<String, List<TrackDto>>()

    /** Guards [recentRoamIds] and hands out strictly increasing roam ids. */
    private val roamSerial = AtomicLong()
    private val recentRoamIds = LinkedHashSet<String>()

    private fun <T> pageOf(items: List<T>, page: Int, size: Int): ApiEnvelope<PageDto<T>> {
        val safeSize = size.coerceAtLeast(1)
        val from = ((page - 1).coerceAtLeast(0) * safeSize).coerceAtMost(items.size)
        val to = (from + safeSize).coerceAtMost(items.size)
        return ok(PageDto(items.subList(from, to), items.size))
    }

    private fun offset(page: Int, size: Int): Int = (page - 1).coerceAtLeast(0) * size.coerceAtLeast(1)

    // ---- Song library -----------------------------------------------------

    override suspend fun tracks(page: Int, size: Int, sort: String?): ApiEnvelope<PageDto<TrackDto>> {
        val offset = offset(page, size)
        val root = client.get(
            "rest/api/v1/songs",
            mapOf("offset" to offset.toString(), "limit" to size.coerceAtLeast(1).toString()),
        )
        val items = root.list("songs").asObjects().map { it.toTrackDto() }
        val total = root.integer("total") ?: (offset + items.size)
        return ok(PageDto(items, total))
    }

    // ---- Albums -----------------------------------------------------------

    override suspend fun albums(page: Int, size: Int, sort: String?): ApiEnvelope<PageDto<AlbumDto>> {
        val offset = offset(page, size)
        val root = client.get(
            "rest/api/v1/albums",
            mapOf("offset" to offset.toString(), "limit" to size.coerceAtLeast(1).toString()),
        )
        val items = root.list("albums").asObjects().map { it.toAlbumDto() }
        val total = root.integer("total") ?: (offset + items.size)
        return ok(PageDto(items, total))
    }

    override suspend fun albumDetail(guid: String): ApiEnvelope<AlbumDto> {
        val root = client.get("rest/getAlbum.view", mapOf("id" to guid))
        val album = root.child("album") ?: return ok(AlbumDto(guid))
        return ok(album.toAlbumDto())
    }

    override suspend fun albumTracks(albumGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> {
        val root = client.get("rest/getAlbum.view", mapOf("id" to albumGuid))
        val items = (root.child("album")?.list("song") ?: root.list("song"))
            .asObjects().filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
        return pageOf(items, page, size)
    }

    // ---- Artists ----------------------------------------------------------

    /**
     * `GET /api/artist` is the only listing that carries a per-artist song
     * count; `/rest/api/v1/artists` exposes just `albumCount`. Builds without
     * the Navidrome-compatible route fall back to the Subsonic listing, where
     * the count stays zero.
     */
    override suspend fun artists(page: Int, size: Int): ApiEnvelope<PageDto<ArtistDto>> {
        val navidrome = navidromeOrFallback {
            navidromePage("api/artist", mapOf("_sort" to "name"), page, size)
        }
        if (navidrome != null) {
            val (rows, total) = navidrome
            return ok(PageDto(rows.map { it.toArtistDto() }, total))
        }
        val offset = offset(page, size)
        val root = client.get(
            "rest/api/v1/artists",
            mapOf("offset" to offset.toString(), "limit" to size.coerceAtLeast(1).toString()),
        )
        val items = root.list("artists").asObjects().map { it.toArtistDto() }
        val total = root.integer("total") ?: (offset + items.size)
        return ok(PageDto(items, total))
    }

    override suspend fun artistDetail(guid: String): ApiEnvelope<ArtistDto> {
        val navidrome = navidromeOrFallback { client.getObject("api/artist/$guid") }
        if (navidrome?.text("id") != null) {
            val dto = navidrome.toArtistDto()
            if (dto.trackCount > 0 || dto.albumCount == 0) return ok(dto)
            // Some artists own albums whose songs never got their artist_id
            // rewritten, so the server reports zero. The album song counts are
            // still right, so use their sum instead of showing "0 首歌曲".
            val derived = navidromeOrFallback { client.get("rest/getArtist.view", mapOf("id" to guid)) }
                ?.child("artist")
                ?.artistTrackCount() ?: 0
            return ok(if (derived > 0) dto.copy(trackCount = derived) else dto)
        }
        val root = client.get("rest/getArtist.view", mapOf("id" to guid))
        val artist = root.child("artist") ?: return ok(ArtistDto(guid))
        val dto = artist.toArtistDto()
        // This route has no song count, but getArtist.view carries one per
        // album; summing it keeps the detail header populated.
        return ok(if (dto.trackCount > 0) dto else dto.copy(trackCount = artist.artistTrackCount()))
    }

    override suspend fun artistAlbums(artistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<AlbumDto>> {
        val root = client.get("rest/getArtist.view", mapOf("id" to artistGuid))
        val items = (root.child("artist")?.list("album") ?: root.list("album"))
            .asObjects().map { it.toAlbumDto() }
        return pageOf(items, page, size)
    }

    override suspend fun artistTracks(artistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> {
        // /api/song?artist_id= counts a song only on its own artist, so the list
        // matches the header count. Fanning out over albums instead would also
        // return every other artist credited on a compilation.
        val navidrome = navidromeOrFallback {
            navidromePage("api/song", mapOf("artist_id" to artistGuid), page, size)
        }
        if (navidrome != null) {
            val (rows, total) = navidrome
            val items = rows.filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
            if (items.isNotEmpty()) return ok(PageDto(items, total))
            // No song points at this artist_id, yet the artist owns albums.
            // Walk those albums so the page matches the detail header.
            val all = artistTrackCache[artistGuid] ?: loadArtistTracks(artistGuid).also {
                artistTrackCache[artistGuid] = it
            }
            return pageOf(all, page, size)
        }
        val all = artistTrackCache[artistGuid] ?: loadArtistTracks(artistGuid).also {
            artistTrackCache[artistGuid] = it
        }
        return pageOf(all, page, size)
    }

    /**
     * Navidrome-compatible routes cap `_limit` at 100, while Paging can ask for
     * a larger initial load. Chunking keeps the requested range contiguous
     * instead of silently dropping the rows past the cap.
     */
    private suspend fun navidromePage(
        path: String,
        params: Map<String, String>,
        page: Int,
        size: Int,
    ): Pair<List<JsonObject>, Int> {
        val want = size.coerceAtLeast(1)
        var cursor = offset(page, size)
        var total: Int? = null
        val collected = ArrayList<JsonObject>(want)
        while (collected.size < want) {
            val chunk = minOf(NAVIDROME_PAGE_LIMIT, want - collected.size)
            val data = client.getArray(
                path,
                params + mapOf("_start" to cursor.toString(), "_limit" to chunk.toString()),
            )
            if (total == null) total = data.total?.toInt()
            if (data.items.isEmpty()) break
            collected += data.items
            cursor += data.items.size
            if (data.items.size < chunk) break
        }
        return collected to (total ?: cursor)
    }

    /** Auth failures must surface; anything else means the route is absent. */
    private suspend fun <T> navidromeOrFallback(block: suspend () -> T): T? =
        try {
            block()
        } catch (error: MusicError.Authentication) {
            throw error
        } catch (_: Throwable) {
            null
        }

    private suspend fun loadArtistTracks(artistGuid: String): List<TrackDto> {
        val root = client.get("rest/getArtist.view", mapOf("id" to artistGuid))
        val albums = (root.child("artist")?.list("album") ?: root.list("album")).asObjects()
        // Bound the fan-out for artists with very large discographies.
        return albums.take(MAX_ARTIST_ALBUMS).flatMap { album ->
            val id = album.text("id") ?: return@flatMap emptyList()
            runCatching {
                client.get("rest/getAlbum.view", mapOf("id" to id))
                    .child("album")?.list("song")
                    .asObjects().filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
            }.getOrDefault(emptyList())
        }
    }

    // ---- Playlists --------------------------------------------------------

    override suspend fun playlists(): ApiEnvelope<PageDto<PlaylistDto>> {
        val root = client.get("rest/api/v1/playlists")
        val items = root.list("playlists").asObjects().map { it.toPlaylistDto() }
        playlistCache.clear()
        items.forEach { playlistCache[it.guid] = it }
        return ok(PageDto(items, items.size))
    }

    override suspend fun playlistDetail(guid: String): ApiEnvelope<PlaylistDto> {
        val cached = playlistCache[guid]
        if (cached != null) return ok(cached)
        val root = client.get("rest/api/v1/playlists/$guid")
        val dto = (root.child("playlist") ?: root).toPlaylistDto()
        return ok(dto.copy(guid = guid, name = dto.name.ifBlank { cached?.name.orEmpty() }))
    }

    override suspend fun playlistTracks(playlistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> {
        val root = client.get("rest/getPlaylist.view", mapOf("id" to playlistGuid))
        val items = (root.child("playlist")?.list("entry") ?: root.list("songs"))
            .asObjects().filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
        return pageOf(items, page, size)
    }

    override suspend fun createPlaylist(body: PlaylistCreateRequest): ApiEnvelope<JsonObject> {
        client.post("rest/api/v1/playlists", buildJsonObject { put("name", body.name) })
        playlistCache.clear()
        return ok(emptyObject())
    }

    override suspend fun editPlaylist(body: PlaylistEditRequest): ApiEnvelope<JsonObject> {
        client.put("rest/api/v1/playlists/${body.guid}", buildJsonObject { put("name", body.name) })
        playlistCache.remove(body.guid)
        return ok(emptyObject())
    }

    override suspend fun deletePlaylist(body: PlaylistGuidRequest): ApiEnvelope<JsonObject> {
        client.delete("rest/api/v1/playlists/${body.guid}")
        playlistCache.remove(body.guid)
        return ok(emptyObject())
    }

    override suspend fun addPlaylistTracks(body: PlaylistTracksRequest): ApiEnvelope<JsonObject> {
        body.trackGUIDs.forEach { id ->
            runCatching {
                client.post(
                    "rest/api/v1/playlists/${body.guid}/songs",
                    buildJsonObject { put("songId", id) },
                )
            }
        }
        return ok(emptyObject())
    }

    override suspend fun removePlaylistTracks(body: PlaylistTracksRequest): ApiEnvelope<JsonObject> {
        body.trackGUIDs.forEach { id ->
            runCatching { client.delete("rest/api/v1/playlists/${body.guid}/songs/$id") }
        }
        return ok(emptyObject())
    }

    // ---- Favorites --------------------------------------------------------

    override suspend fun favorites(page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> {
        val root = client.get("rest/getStarred2.view")
        val items = (root.child("starred2")?.list("song") ?: root.child("starred")?.list("song"))
            .asObjects().filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
        return pageOf(items, page, size)
    }

    override suspend fun createFavorite(body: FavoriteRequest): ApiEnvelope<JsonObject> {
        client.get("rest/star.view", mapOf("id" to body.trackGUID))
        return ok(emptyObject())
    }

    override suspend fun deleteFavorite(body: FavoriteRequest): ApiEnvelope<JsonObject> {
        client.get("rest/unstar.view", mapOf("id" to body.trackGUID))
        return ok(emptyObject())
    }

    // ---- Play history -----------------------------------------------------

    override suspend fun history(page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> {
        // GET /stream already records a play server-side, so reporting events here
        // would double count. reportEvent stays a no-op for this backend.
        val root = client.get("rest/api/v1/play-history", mapOf("limit" to HISTORY_FETCH_LIMIT.toString()))
        val items = root.list("histories").asObjects()
            .filter { it.containsUsableTrackId() || it.child("Song", "song") != null }
            .map { it.historyTrackDto() }
            .filter { it.guid.isNotBlank() }
            // A song can appear once per play (one was played 18 times in a real
            // library). The list renders with the track id as its LazyColumn key,
            // so duplicates crash the page. History is newest-first, therefore
            // keeping the first occurrence keeps the most recent play.
            .distinctBy { it.guid }
        return pageOf(items, page, size)
    }

    // ---- Roam -------------------------------------------------------------
    // fnOS derives its roam window from listening history. Music Free has no
    // equivalent endpoint, so the window is synthesized from random songs:
    // RoamQueue only consumes current + next, and a per-item unique roamId keeps
    // extendRoamFrom advancing instead of short-circuiting on a repeated track.

    override suspend fun roamStart(deviceId: String): ApiEnvelope<RoamDto> = ok(roamWindow())

    override suspend fun roamNext(deviceId: String, relativeRoamId: String): ApiEnvelope<RoamDto> = ok(roamWindow())

    // Walking backwards is served by the queue already inside Media3, so there is
    // nothing a server round-trip could contribute.
    override suspend fun roamPrevious(deviceId: String, relativeRoamId: String): ApiEnvelope<RoamDto> =
        ok(RoamDto())

    private suspend fun roamWindow(): RoamDto {
        val root = client.get("rest/getRandomSongs.view", mapOf("size" to ROAM_FETCH_SIZE.toString()))
        val tracks = root.child("randomSongs")?.list("song").asObjects()
            .filter { it.containsUsableTrackId() }
            .map { it.toTrackDto() }
        val picked = rememberRoamTracks(tracks)
        val current = picked.firstOrNull() ?: return RoamDto()
        return RoamDto(
            current = roamItem(current),
            next = picked.getOrNull(1)?.let(::roamItem),
        )
    }

    /**
     * Skips tracks served moments ago so even a small library keeps moving. A
     * library smaller than the memory window falls back to the raw response;
     * repeating a song beats ending the roam.
     */
    private fun rememberRoamTracks(tracks: List<TrackDto>): List<TrackDto> = synchronized(recentRoamIds) {
        val picked = tracks.filterNot { it.guid in recentRoamIds }.ifEmpty { tracks }
        picked.forEach { recentRoamIds.add(it.guid) }
        while (recentRoamIds.size > ROAM_RECENT_MEMORY) {
            recentRoamIds.remove(recentRoamIds.first())
        }
        picked
    }

    private fun roamItem(track: TrackDto) = RoamItemDto(
        roamId = "mf-${track.guid}-${roamSerial.incrementAndGet()}",
        track = track,
    )

    // ---- Search -----------------------------------------------------------

    override suspend fun searchTracks(query: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> {
        val root = search3(query, songCount = size, songOffset = offset(page, size))
        val items = root.child("searchResult3")?.list("song")
            .asObjects().filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
        return ok(PageDto(items, items.size))
    }

    override suspend fun searchAlbums(query: String, page: Int, size: Int): ApiEnvelope<PageDto<AlbumDto>> {
        val root = search3(query, albumCount = size, albumOffset = offset(page, size))
        val items = root.child("searchResult3")?.list("album").asObjects().map { it.toAlbumDto() }
        return ok(PageDto(items, items.size))
    }

    override suspend fun searchArtists(query: String, page: Int, size: Int): ApiEnvelope<PageDto<ArtistDto>> {
        val root = search3(query, artistCount = size, artistOffset = offset(page, size))
        val items = root.child("searchResult3")?.list("artist").asObjects().map { it.toArtistDto() }
        return ok(PageDto(items, items.size))
    }

    override suspend fun searchPlaylists(query: String, page: Int, size: Int): ApiEnvelope<PageDto<PlaylistDto>> {
        val all = playlists().requireDataOrEmpty().list.filter {
            it.name.contains(query, ignoreCase = true)
        }
        return pageOf(all, page, size)
    }

    override suspend fun suggestions(query: String): ApiEnvelope<SearchSuggestionsDto> {
        if (query.isBlank()) return super.suggestions(query)
        val root = search3(query, songCount = 5, albumCount = 5, artistCount = 5)
        val result = root.child("searchResult3")
        val tracks = result?.list("song").asObjects().filter { it.containsUsableTrackId() }.map { it.toTrackDto() }
        val albums = result?.list("album").asObjects().map { it.toAlbumDto() }
        val artists = result?.list("artist").asObjects().map { it.toArtistDto() }
        val playlists = playlists().requireDataOrEmpty().list.filter {
            it.name.contains(query, ignoreCase = true)
        }.take(5)
        return ok(
            SearchSuggestionsDto(
                track = SuggestionGroupDto(tracks, tracks.size),
                album = SuggestionGroupDto(albums, albums.size),
                artist = SuggestionGroupDto(artists, artists.size),
                playlist = SuggestionGroupDto(playlists, playlists.size),
            )
        )
    }

    private suspend fun search3(
        query: String,
        songCount: Int = 0,
        songOffset: Int = 0,
        albumCount: Int = 0,
        albumOffset: Int = 0,
        artistCount: Int = 0,
        artistOffset: Int = 0,
    ): JsonObject = client.get(
        "rest/search3.view",
        mapOf(
            "query" to query,
            "songCount" to songCount.toString(),
            "songOffset" to songOffset.toString(),
            "albumCount" to albumCount.toString(),
            "albumOffset" to albumOffset.toString(),
            "artistCount" to artistCount.toString(),
            "artistOffset" to artistOffset.toString(),
        ),
    )

    private fun ApiEnvelope<PageDto<PlaylistDto>>.requireDataOrEmpty(): PageDto<PlaylistDto> =
        data ?: PageDto(emptyList(), 0)

    // ---- Lyrics -----------------------------------------------------------
    // The server stores lyrics on the song model but does not expose them in the
    // library list. Returning an empty result lets the existing online-lyrics
    // providers take over, which keeps that feature intact.

    override suspend fun lyrics(trackGuid: String): ApiEnvelope<LyricDataDto> {
        val root = runCatching {
            client.get("rest/getSong.view", mapOf("id" to trackGuid))
        }.getOrNull() ?: return super.lyrics(trackGuid)
        val content = root.child("song")?.text("lyrics") ?: root.text("lyrics")
        if (content.isNullOrBlank()) return super.lyrics(trackGuid)
        return ok(LyricDataDto(listOf(LyricDto(guid = trackGuid, content = content, isLRC = content.contains('[')))))
    }

    private companion object {
        const val HISTORY_FETCH_LIMIT = 200
        const val MAX_ARTIST_ALBUMS = 40

        /** Over-fetched so the recent-track filter still leaves a current + next pair. */
        const val ROAM_FETCH_SIZE = 8

        /** How many recently served tracks a new roam window avoids. */
        const val ROAM_RECENT_MEMORY = 32

        /** Hard cap of the Navidrome-compatible `_limit` query parameter. */
        const val NAVIDROME_PAGE_LIMIT = 100
    }
}
