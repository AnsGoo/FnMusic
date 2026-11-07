package com.seasonyuu.fnmusic.desktop.data

import com.seasonyuu.fnmusic.core.model.Album
import com.seasonyuu.fnmusic.core.model.AlbumId
import com.seasonyuu.fnmusic.core.model.Artist
import com.seasonyuu.fnmusic.core.model.ArtistId
import com.seasonyuu.fnmusic.core.model.AudioSpec
import com.seasonyuu.fnmusic.core.model.MusicError
import com.seasonyuu.fnmusic.core.model.Playlist
import com.seasonyuu.fnmusic.core.model.PlaylistId
import com.seasonyuu.fnmusic.core.model.Track
import com.seasonyuu.fnmusic.core.model.TrackId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

/** One page of a paged Music Free listing. */
data class Page<T>(val items: List<T>, val total: Long)

/** Everything needed to sign Music Free API and media requests. */
data class MusicFreeSession(
    val baseUrl: HttpUrl,
    val token: String,
    val username: String,
    val subsonicToken: String,
    val clientSalt: String,
) {
    val hostLabel: String get() = baseUrl.host + if (baseUrl.port != HttpUrl.defaultPort(baseUrl.scheme)) ":${baseUrl.port}" else ""
}

/**
 * A small, read-mostly Music Free client for the desktop build.
 *
 * The Android client reaches this server through Retrofit plus a shared
 * interceptor stack; the desktop build has no Android runtime, so this file
 * speaks the same REST surface directly. Endpoints and field names are kept in
 * sync with `core/network/.../musicfree/MusicFreeApi.kt`.
 */
class MusicFreeClient {

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        isLenient = true
    }
    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    @Volatile
    private var session: MusicFreeSession? = null

    val current: MusicFreeSession? get() = session

    fun restore(saved: MusicFreeSession) {
        session = saved
    }

    fun forget() {
        session = null
    }

    // ---- Session ----------------------------------------------------------

    suspend fun login(rawUrl: String, username: String, password: String): MusicFreeSession {
        val base = normalize(rawUrl)
        val payload = buildJsonObject {
            put("username", username)
            put("password", password)
        }
        val root = post("rest/api/v1/auth/login", payload, baseKey = base)
        val token = root.string("token")
            ?: throw MusicError.Authentication("登录失败，请检查账号和密码")
        val salt = ByteArray(8).also(SecureRandom()::nextBytes).joinToString("") { "%02x".format(it) }
        return MusicFreeSession(
            baseUrl = base,
            token = token,
            username = root.string("username") ?: username,
            subsonicToken = root.string("subsonicToken").orEmpty(),
            clientSalt = salt,
        ).also { session = it }
    }

    fun normalize(rawUrl: String): HttpUrl {
        val trimmed = rawUrl.trim()
        if (trimmed.isEmpty()) throw MusicError.UnsafeConnection("请填写 Music Free 地址")
        val withScheme = if (trimmed.contains("://")) trimmed else "http://$trimmed"
        val parsed = withScheme.toHttpUrlOrNull()
            ?: throw MusicError.UnsafeConnection("地址格式不正确：$rawUrl")
        if (parsed.scheme != "http" && parsed.scheme != "https") {
            throw MusicError.UnsafeConnection("只支持 http 或 https 地址")
        }
        return parsed
    }

    // ---- Listings ---------------------------------------------------------

    suspend fun tracks(page: Int, size: Int): Page<Track> {
        val offset = (page - 1).coerceAtLeast(0) * size
        val root = get(
            "rest/api/v1/songs",
            mapOf("offset" to offset.toString(), "limit" to size.toString()),
        )
        val items = root.list("songs").objects().map { it.toTrack() }
        return Page(items, root.int("total")?.toLong() ?: (offset + items.size).toLong())
    }

    suspend fun albums(page: Int, size: Int): Page<Album> {
        val offset = (page - 1).coerceAtLeast(0) * size
        val root = get(
            "rest/api/v1/albums",
            mapOf("offset" to offset.toString(), "limit" to size.toString()),
        )
        val items = root.list("albums").objects().map { it.toAlbum() }
        return Page(items, root.int("total")?.toLong() ?: (offset + items.size).toLong())
    }

    suspend fun albumTracks(albumId: String): List<Track> {
        val root = get("rest/getAlbum.view", mapOf("id" to albumId))
        val album = root.child("album")
        val songs = (album?.list("song") ?: root.list("song")).objects()
        return songs.map { it.toTrack() }
    }

    suspend fun artists(page: Int, size: Int): Page<Artist> {
        val offset = (page - 1).coerceAtLeast(0) * size
        val root = get(
            "rest/api/v1/artists",
            mapOf("offset" to offset.toString(), "limit" to size.toString()),
        )
        val items = root.list("artists").objects().map { it.toArtist() }
        return Page(items, root.int("total")?.toLong() ?: (offset + items.size).toLong())
    }

    suspend fun playlists(): List<Playlist> =
        get("rest/api/v1/playlists").list("playlists").objects().map { it.toPlaylist() }

    suspend fun playlistTracks(playlistId: String): List<Track> {
        val root = get("rest/getPlaylist.view", mapOf("id" to playlistId))
        val entries = (root.child("playlist")?.list("entry") ?: root.list("songs")).objects()
        return entries.map { it.toTrack() }
    }

    suspend fun favorites(): List<Track> {
        val root = get("rest/getStarred2.view")
        val songs = (root.child("starred2")?.list("song") ?: root.child("starred")?.list("song"))
            .orEmpty()
            .objects()
        return songs.map { it.toTrack() }
    }

    suspend fun searchTracks(query: String, limit: Int = 60): List<Track> {
        if (query.isBlank()) return emptyList()
        val root = get(
            "rest/search3.view",
            mapOf(
                "query" to query,
                "songCount" to limit.toString(),
                "albumCount" to "0",
                "artistCount" to "0",
            ),
        )
        val result = root.child("searchResult3")
        val songs = (result?.list("song") ?: root.list("song")).objects()
        return songs.map { it.toTrack() }
    }

    // ---- Media URLs -------------------------------------------------------

    fun streamUrl(trackId: String, format: String? = "mp3", maxBitRate: Int? = 192): String {
        val params = linkedMapOf("id" to trackId)
        if (format != null) params["format"] = format
        if (maxBitRate != null) params["maxBitRate"] = maxBitRate.toString()
        return mediaUrl("rest/stream", params)
    }

    fun coverUrl(coverId: String?, size: Int = 320): String? {
        if (coverId.isNullOrBlank()) return null
        return mediaUrl("rest/getCoverArt", linkedMapOf("id" to coverId, "size" to size.toString()))
    }

    private fun mediaUrl(path: String, params: Map<String, String>): String {
        val active = session ?: throw MusicError.Authentication("尚未登录")
        val builder = active.baseUrl.newBuilder()
            .addPathSegments(path)
            .addQueryParameter("v", "1.16.1")
            .addQueryParameter("c", "FnMusic")
        params.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        if (active.subsonicToken.isNotBlank()) {
            builder.addQueryParameter("u", active.username)
                .addQueryParameter("t", md5(active.subsonicToken + active.clientSalt))
                .addQueryParameter("s", active.clientSalt)
        }
        return builder.build().toString()
    }

    // ---- Transport --------------------------------------------------------

    private suspend fun get(path: String, params: Map<String, String> = emptyMap()): JsonObject =
        execute(buildRequest(path, params), baseKey = null)

    private suspend fun post(path: String, payload: JsonObject, baseKey: HttpUrl?): JsonObject {
        val base = baseKey ?: session?.baseUrl ?: throw MusicError.Authentication("尚未登录")
        val request = Request.Builder()
            .url(url(base, path, emptyMap(), subsonicParams = false))
            .post(payload.toString().toRequestBody(JSON_MEDIA))
            .build()
        return execute(request, baseKey = baseKey)
    }

    private fun buildRequest(path: String, params: Map<String, String>): Request {
        val base = session?.baseUrl ?: throw MusicError.Authentication("尚未登录")
        val request = Request.Builder().url(url(base, path, params)).get().build()
        val token = session?.token
        return if (token.isNullOrBlank()) request else {
            request.newBuilder().header("Authorization", "Bearer $token").build()
        }
    }

    private fun url(
        base: HttpUrl,
        path: String,
        params: Map<String, String>,
        subsonicParams: Boolean = true,
    ): HttpUrl {
        val builder = base.newBuilder().addPathSegments(path.trimStart('/'))
        if (subsonicParams) {
            builder.addQueryParameter("f", "json")
                .addQueryParameter("v", "1.16.1")
                .addQueryParameter("c", "FnMusic")
        }
        params.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return builder.build()
    }

    private suspend fun execute(request: Request, baseKey: HttpUrl?): JsonObject = withContext(Dispatchers.IO) {
        val signed = if (baseKey == null) request else request
        val response = try {
            http.newCall(signed).execute()
        } catch (error: Exception) {
            throw MusicError.Network(error)
        }
        response.use {
            val body = it.body?.string().orEmpty()
            if (!it.isSuccessful && body.isBlank()) {
                throw MusicError.Protocol("服务器返回 HTTP ${it.code}")
            }
            val element = runCatching { json.parseToJsonElement(body) }.getOrNull()
                ?: throw MusicError.Protocol("服务器返回了无法解析的内容")
            val root = element as? JsonObject ?: throw MusicError.Protocol("服务器返回了非对象内容")
            unwrap(root)
        }
    }

    /** Music Free answers both `subsonic-response` envelopes and bare objects. */
    private fun unwrap(root: JsonObject): JsonObject {
        val envelope = root.child("subsonic-response") ?: return root
        val status = envelope.string("status")
        if (status == "failed") {
            val error = envelope.child("error")
            val message = error?.string("message") ?: "服务器拒绝了请求"
            val code = error?.int("code") ?: 0
            if (code == 40 || code == 41) throw MusicError.Authentication(message)
            throw MusicError.Business(code, message)
        }
        return envelope
    }

    private companion object {
        val JSON_MEDIA = "application/json".toMediaType()

        fun md5(value: String): String =
            MessageDigest.getInstance("MD5").digest(value.toByteArray())
                .joinToString("") { "%02x".format(it) }
    }
}

// ---- JSON helpers ---------------------------------------------------------

private fun JsonObject.string(vararg names: String): String? = names.firstNotNullOfOrNull { name ->
    (this[name] as? JsonPrimitive)?.takeIf { it.isString }?.content
}

private fun JsonObject.int(vararg names: String): Int? = names.firstNotNullOfOrNull { name ->
    (this[name] as? JsonPrimitive)?.content?.toIntOrNull()
}

private fun JsonObject.longValue(vararg names: String): Long? = names.firstNotNullOfOrNull { name ->
    (this[name] as? JsonPrimitive)?.content?.toLongOrNull()
}

private fun JsonObject.childObject(key: String): JsonObject? = this[key] as? JsonObject

private fun JsonObject.list(key: String): List<JsonElement> = (this[key] as? JsonArray)?.toList().orEmpty()

internal fun JsonElement.stringOrNull(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

/** `subsonic-response` keeps the payload under a named node. */
private fun JsonObject.child(key: String): JsonObject? = childObject(key)

internal fun List<JsonElement>.objects(): List<JsonObject> = mapNotNull { it as? JsonObject }

private fun JsonObject.toTrack(): Track {
    val duration = longValue("durationMs")
        ?.div(1000.0)
        ?: (this["duration"] as? JsonPrimitive)?.content?.toDoubleOrNull()?.let { seconds ->
            // Navidrome reports seconds; the Music Free /songs rows report ms.
            if (seconds > 36000) seconds / 1000.0 else seconds
        }
        ?: 0.0
    return Track(
        id = TrackId(string("id", "guid").orEmpty()),
        title = string("title", "name").orEmpty(),
        artists = embeddedArtists(),
        album = embeddedAlbum(),
        coverId = string("coverArt", "coverId") ?: string("albumId"),
        durationSeconds = duration,
        isFavorite = containsKey("starred"),
        audioSpec = AudioSpec(
            format = string("suffix", "format", "Format"),
            size = longValue("size"),
            bitrate = longValue("bitRate", "bitrate"),
            duration = duration,
            path = string("path"),
        ),
        year = int("year"),
        trackNo = int("track", "trackNo", "trackNumber"),
        discNo = int("discNumber", "disc", "discNo"),
    )
}

private fun JsonObject.toAlbum(): Album = Album(
    id = AlbumId(string("id", "guid").orEmpty()),
    name = string("name", "album", "title").orEmpty(),
    artists = embeddedArtists(),
    coverId = string("coverArt", "coverId"),
    releaseDate = string("year", "releaseDate"),
    trackCount = int("songCount", "trackCount") ?: 0,
)

private fun JsonObject.toArtist(): Artist = Artist(
    id = ArtistId(string("id", "guid").orEmpty()),
    name = string("name", "artist").orEmpty(),
    coverId = string("coverArt", "coverId"),
    trackCount = int("songCount", "trackCount") ?: 0,
    albumCount = int("albumCount") ?: 0,
)

private fun JsonObject.toPlaylist(): Playlist = Playlist(
    id = PlaylistId(string("id", "guid").orEmpty()),
    name = string("name", "title").orEmpty(),
    coverId = string("coverArt", "coverId"),
    trackCount = int("songCount", "trackCount"),
)

/** Rows sometimes embed the artist as an object, sometimes as a plain name. */
private fun JsonObject.embeddedArtists(): List<Artist> {
    val array = this["artists"] as? JsonArray
    if (array != null) {
        return array.objects().mapNotNull { node ->
            val name = node.string("name", "artist") ?: return@mapNotNull null
            Artist(id = ArtistId(node.string("id", "guid").orEmpty()), name = name, coverId = node.string("coverArt"))
        }
    }
    val single = this["artist"] as? JsonObject
    if (single != null) {
        val name = single.string("name", "artist") ?: return emptyList()
        return listOf(Artist(id = ArtistId(single.string("id", "guid").orEmpty()), name = name))
    }
    val name = string("artist", "artistName") ?: return emptyList()
    return listOf(Artist(id = ArtistId(string("artistId").orEmpty()), name = name))
}

private fun JsonObject.embeddedAlbum(): Album? {
    val node = this["album"] as? JsonObject
    if (node != null) {
        return Album(
            id = AlbumId(node.string("id", "guid").orEmpty()),
            name = node.string("name", "album", "title").orEmpty(),
            coverId = node.string("coverArt", "coverId"),
            trackCount = node.int("songCount", "trackCount") ?: 0,
        )
    }
    // Subsonic song rows flatten the album into plain attributes.
    val name = string("album") ?: return null
    return Album(
        id = AlbumId(string("albumId").orEmpty()),
        name = name,
        coverId = string("coverArt", "coverId"),
    )
}
