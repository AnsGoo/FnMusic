package com.seasonyuu.fnmusic.desktop

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.seasonyuu.fnmusic.core.model.Album
import com.seasonyuu.fnmusic.core.model.Artist
import com.seasonyuu.fnmusic.core.model.Playlist
import com.seasonyuu.fnmusic.core.model.Track
import com.seasonyuu.fnmusic.desktop.data.MusicFreeClient
import com.seasonyuu.fnmusic.desktop.data.MusicFreeSession
import com.seasonyuu.fnmusic.desktop.play.DesktopAudioPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.File

enum class Section(val label: String, val subtitle: String) {
    Tracks("歌曲库", "全部曲目"),
    Albums("专辑", "按专辑浏览"),
    Artists("艺术家", "按艺术家浏览"),
    Playlists("歌单", "我的歌单"),
    Favorites("收藏", "我喜欢的音乐"),
}

/** A drill-down page: an album or a playlist opened from a listing. */
data class Detail(
    val title: String,
    val subtitle: String,
    val coverId: String?,
    val tracks: List<Track> = emptyList(),
    val loading: Boolean = true,
)

class AppModel(private val scope: CoroutineScope) {

    val client = MusicFreeClient()
    val player = DesktopAudioPlayer(scope)

    var session by mutableStateOf<MusicFreeSession?>(null)
        private set
    var connecting by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)

    var section by mutableStateOf(Section.Tracks)
        private set
    var detail by mutableStateOf<Detail?>(null)
        private set

    var loading by mutableStateOf(false)
        private set
    var loadingMore by mutableStateOf(false)
        private set

    var tracks by mutableStateOf<List<Track>>(emptyList())
        private set
    var albums by mutableStateOf<List<Album>>(emptyList())
        private set
    var artists by mutableStateOf<List<Artist>>(emptyList())
        private set
    var playlists by mutableStateOf<List<Playlist>>(emptyList())
        private set
    var favorites by mutableStateOf<List<Track>>(emptyList())
        private set

    var query by mutableStateOf("")
        private set
    var searching by mutableStateOf(false)
        private set
    var searchResults by mutableStateOf<List<Track>>(emptyList())
        private set

    var queue by mutableStateOf<List<Track>>(emptyList())
        private set
    var queueIndex by mutableStateOf(-1)
        private set

    var page = 0
        private set
    var total = 0L
        private set
    private val pageSize = 120
    private var loadJob: Job? = null

    val canLoadMore: Boolean
        get() = !searching && detail == null && when (section) {
            Section.Tracks -> tracks.size < total
            Section.Albums -> albums.size < total
            Section.Artists -> artists.size < total
            else -> false
        }

    // ---- Session ----------------------------------------------------------

    fun restoreSession() {
        val saved = SessionStore.load() ?: return
        val base = saved.baseUrl.toHttpUrlOrNull() ?: return
        val restored = MusicFreeSession(
            baseUrl = base,
            token = saved.token,
            username = saved.username,
            subsonicToken = saved.subsonicToken,
            clientSalt = saved.clientSalt,
        )
        client.restore(restored)
        session = restored
        select(Section.Tracks)
    }

    fun login(rawUrl: String, username: String, password: String) {
        if (connecting) return
        if (username.isBlank() || password.isBlank()) {
            error = "请填写账号和密码"
            return
        }
        connecting = true
        error = null
        scope.launch {
            try {
                val active = client.login(rawUrl, username, password)
                SessionStore.save(active)
                session = active
                select(Section.Tracks)
            } catch (failure: Throwable) {
                error = failure.message ?: "连接失败"
            } finally {
                connecting = false
            }
        }
    }

    fun logout() {
        player.stop()
        client.forget()
        SessionStore.clear()
        session = null
        detail = null
        tracks = emptyList()
        albums = emptyList()
        artists = emptyList()
        playlists = emptyList()
        favorites = emptyList()
        searchResults = emptyList()
        queue = emptyList()
        queueIndex = -1
        section = Section.Tracks
    }

    // ---- Navigation -------------------------------------------------------

    fun select(target: Section) {
        // Re-selecting the visible tab is a no-op, but an empty section always
        // reloads: both restore and login land here before any data exists.
        val loaded = when (target) {
            Section.Tracks -> tracks.isNotEmpty()
            Section.Albums -> albums.isNotEmpty()
            Section.Artists -> artists.isNotEmpty()
            Section.Playlists -> playlists.isNotEmpty()
            Section.Favorites -> favorites.isNotEmpty()
        }
        if (section == target && detail == null && !searching && loaded) return
        section = target
        detail = null
        searching = false
        query = ""
        searchResults = emptyList()
        page = 0
        total = 0
        tracks = emptyList()
        albums = emptyList()
        artists = emptyList()
        loadJob?.cancel()
        load(initial = true)
    }

    fun back() {
        detail = null
    }

    fun updateQuery(value: String) {
        query = value
    }

    fun submitSearch() {
        val text = query.trim()
        if (text.isEmpty()) {
            searching = false
            searchResults = emptyList()
            return
        }
        searching = true
        detail = null
        loading = true
        error = null
        scope.launch {
            runCatching { client.searchTracks(text) }
                .onSuccess { searchResults = it }
                .onFailure { error = it.message ?: "搜索失败" }
            loading = false
        }
    }

    fun clearSearch() {
        query = ""
        searching = false
        searchResults = emptyList()
    }

    fun load(initial: Boolean = false) {
        if (session == null) return
        if (initial) {
            loading = true
            page = 0
            total = 0
        }
        error = null
        loadJob = scope.launch {
            runCatching {
                when (section) {
                    Section.Tracks -> {
                        val result = client.tracks(page + 1, pageSize)
                        total = result.total
                        tracks = if (page == 0) result.items else tracks + result.items
                    }
                    Section.Albums -> {
                        val result = client.albums(page + 1, pageSize)
                        total = result.total
                        albums = if (page == 0) result.items else albums + result.items
                    }
                    Section.Artists -> {
                        val result = client.artists(page + 1, pageSize)
                        total = result.total
                        artists = if (page == 0) result.items else artists + result.items
                    }
                    Section.Playlists -> playlists = client.playlists()
                    Section.Favorites -> favorites = client.favorites()
                }
                page += 1
            }.onFailure { error = it.message ?: "加载失败" }
            loading = false
            loadingMore = false
        }
    }

    fun loadMore() {
        if (loading || loadingMore || !canLoadMore) return
        loadingMore = true
        load()
    }

    fun openAlbum(album: Album) {
        detail = Detail(
            title = album.name,
            subtitle = artistLine(album.artists.map { it.name }) + " · ${album.trackCount} 首",
            coverId = album.coverId,
        )
        scope.launch {
            runCatching { client.albumTracks(album.id.value) }
                .onSuccess { detail = detail?.copy(tracks = it, loading = false) }
                .onFailure {
                    detail = detail?.copy(loading = false)
                    error = it.message ?: "专辑加载失败"
                }
        }
    }

    fun openPlaylist(playlist: Playlist) {
        detail = Detail(
            title = playlist.name,
            subtitle = "${playlist.trackCount ?: 0} 首",
            coverId = playlist.coverId,
        )
        scope.launch {
            runCatching { client.playlistTracks(playlist.id.value) }
                .onSuccess { detail = detail?.copy(tracks = it, loading = false) }
                .onFailure {
                    detail = detail?.copy(loading = false)
                    error = it.message ?: "歌单加载失败"
                }
        }
    }

    // ---- Playback ---------------------------------------------------------

    fun playFrom(list: List<Track>, index: Int) {
        if (index !in list.indices) return
        queue = list
        queueIndex = index
        startTrack(list[index])
    }

    fun next() {
        if (queue.isEmpty()) return
        queueIndex = (queueIndex + 1).coerceAtMost(queue.lastIndex)
        startTrack(queue[queueIndex])
    }

    fun previous() {
        if (queue.isEmpty()) return
        queueIndex = (queueIndex - 1).coerceAtLeast(0)
        startTrack(queue[queueIndex])
    }

    fun togglePlay() {
        val playing = player.state.value
        if (playing.trackId == null) {
            val list = currentList()
            if (list.isNotEmpty()) playFrom(list, 0)
            return
        }
        player.togglePause()
    }

    private fun startTrack(track: Track) {
        runCatching {
            val url = client.streamUrl(track.id.value)
            player.play(
                trackId = track.id.value,
                title = track.title,
                subtitle = trackSubtitle(track),
                streamUrl = url,
                durationSeconds = track.durationSeconds,
            )
        }.onFailure { error = it.message ?: "无法生成播放地址" }
    }

    private fun currentList(): List<Track> = when {
        searching -> searchResults
        detail != null -> detail?.tracks.orEmpty()
        section == Section.Favorites -> favorites
        else -> tracks
    }

    fun coverUrl(coverId: String?): String? = runCatching { client.coverUrl(coverId) }.getOrNull()

    private fun artistLine(names: List<String>): String =
        if (names.isEmpty()) "未知艺术家" else names.joinToString(" / ")

    private fun trackSubtitle(track: Track): String {
        val artist = artistLine(track.artists.map { it.name })
        val album = track.album?.name
        return if (album.isNullOrBlank()) artist else "$artist · $album"
    }
}

/** Remembers the session between launches. The token is not a password. */
internal object SessionStore {
    private val file = File(System.getProperty("user.home"), "Library/Application Support/FnMusic/session.json")
    private val json = Json { ignoreUnknownKeys = true }

    @Serializable
    internal data class Saved(
        val baseUrl: String,
        val token: String,
        val username: String,
        val subsonicToken: String,
        val clientSalt: String,
    )

    fun save(session: MusicFreeSession) {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(
                json.encodeToString(
                    Saved.serializer(),
                    Saved(
                        baseUrl = session.baseUrl.toString(),
                        token = session.token,
                        username = session.username,
                        subsonicToken = session.subsonicToken,
                        clientSalt = session.clientSalt,
                    ),
                ),
            )
        }
    }

    fun load(): Saved? = runCatching {
        if (!file.isFile) null else json.decodeFromString(Saved.serializer(), file.readText())
    }.getOrNull()

    fun clear() {
        runCatching { file.delete() }
    }
}
