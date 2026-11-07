package com.seasonyuu.fnmusic.core.network.musicfree

import com.seasonyuu.fnmusic.core.network.md5
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MusicFreeMappingTest {

    private val json = Json { ignoreUnknownKeys = true }
    private fun obj(raw: String) = json.parseToJsonElement(raw).jsonObject

    private fun clientFor(server: MockWebServer) = MusicFreeClient(
        http = OkHttpClient(),
        json = json,
        baseUrl = server.url("/"),
        auth = { MusicFreeAuth("jwt", "admin", "sub", "salt", "client-salt") },
    )

    @Test
    fun `open subsonic child maps to track with millisecond duration`() {
        val track = obj(
            """{"id":"song-1","title":"夜航","artist":" pilot ","artistId":"ar-1",
               "album":"云图","albumId":"al-1","duration":215.5,"coverArt":"so-song-1",
               "year":2024,"track":3,"discNumber":1,"starred":"2026-01-01T00:00:00Z",
               "suffix":"flac","size":123456,"bitRate":960}""".trimIndent()
        ).toTrackDto()

        assertEquals("song-1", track.guid)
        assertEquals("夜航", track.title)
        assertEquals(215_500.0, track.duration, 0.01)
        assertEquals("so-song-1", track.coverId)
        assertEquals("ar-1", track.artists.single().guid)
        assertEquals("al-1", track.album?.guid)
        assertEquals(2024, track.year)
        assertEquals(3, track.trackNo)
        assertEquals(1, track.discNo)
        assertTrue(track.isFavorite)
        assertEquals("flac", track.audioSpec?.format)
        // TrackDto.toDomain converts milliseconds back to seconds.
        assertEquals(215.5, track.toDomain().durationSeconds, 0.01)
    }

    @Test
    fun `compact song map still produces a usable track`() {
        val track = obj(
            """{"id":"s2","title":"Demo","artist":"Someone","album":"Album",
               "duration":90,"coverArt":"so-s2"}""".trimIndent()
        ).toTrackDto()

        assertEquals("s2", track.guid)
        assertEquals(90_000.0, track.duration, 0.01)
        assertEquals("Someone", track.artists.single().name)
        assertEquals("Album", track.album?.name)
        assertFalse(track.isFavorite)
    }

    @Test
    fun `album artist and playlist DTOs use their cover art ids`() {
        val album = obj("""{"id":"al-1","name":"云图","artist":"pilot","artistId":"ar-1","year":2024,"songCount":9,"coverArt":"al-al-1"}""").toAlbumDto()
        assertEquals("al-1", album.guid)
        assertEquals("2024", album.releaseDate)
        assertEquals(9, album.trackCount)
        assertEquals("al-al-1", album.coverId)

        val artist = obj("""{"id":"ar-1","name":"pilot","albumCount":3,"coverArt":"ar-ar-1"}""").toArtistDto()
        assertEquals("ar-1", artist.guid)
        assertEquals(3, artist.albumCount)

        val playlist = obj("""{"id":"pl-1","name":"深夜","songCount":12,"coverArt":"pl-pl-1"}""").toPlaylistDto()
        assertEquals("pl-1", playlist.guid)
        assertEquals(12, playlist.trackCount)
    }

    @Test
    fun `artist song count falls back to the sum of album counts`() {
        // /rest/api/v1/artists has no song count at all.
        val listed = obj("""{"id":"ar-1","name":"pilot","albumCount":2,"coverArt":"ar-ar-1"}""").toArtistDto()
        assertEquals(0, listed.trackCount)
        assertEquals(2, listed.albumCount)

        // getArtist.view can supply it without another request.
        val detail = obj(
            """{"id":"ar-1","name":"pilot","albumCount":2,"album":[
                 {"id":"al-1","songCount":9},{"id":"al-2","trackCount":4},{"id":"al-3"}]}""".trimIndent()
        )
        assertEquals(13, detail.artistTrackCount())
        assertEquals(13, detail.toArtistDto().copy(trackCount = detail.artistTrackCount()).toDomain().trackCount)

        // Compatible servers that already report a count are left untouched.
        val explicit = obj("""{"id":"ar-2","name":"harbor","songCount":7,"albumCount":1}""").toArtistDto()
        assertEquals(7, explicit.trackCount)
    }

    @Test
    fun `playlist stubs are not treated as playable tracks`() {
        assertFalse(obj("""{"id":"pls-999"}""").containsUsableTrackId())
        assertTrue(obj("""{"id":"song-1"}""").containsUsableTrackId())
    }

    @Test
    fun `play history prefers the nested song payload`() {
        val history = obj(
            """{"Song":{"id":"s9","title":"History Song","artist":"A","duration":100}}""".trimIndent()
        )
        assertEquals("s9", history.historyTrackDto().guid)
        assertEquals("History Song", history.historyTrackDto().title)
    }

    @Test
    fun `auth survives a vault round trip`() {
        val auth = MusicFreeAuth("jwt-token", "admin", "deadbeef", "server-salt", "client-salt")
        val restored = MusicFreeAuth.decode(json, auth.encode(json))
        assertNotNull(restored)
        assertEquals(auth, restored)
        assertNull(MusicFreeAuth.decode(json, "not-json"))
    }

    @Test
    fun `play history resolves embedded artist and album objects`() {
        // Real /api/v1/play-history nests full objects under "artist"/"album",
        // unlike the library list which uses plain strings.
        val track = obj(
            """{"song":{"id":"s7","title":"长街万象","duration":209,
                 "Format":"flac","coverArt":"sha256-abc",
                 "artist":{"id":"ar-7","name":"Real Artist"},
                 "album":{"id":"al-7","name":"Real Album"}}}""".trimIndent()
        ).historyTrackDto()

        assertEquals("s7", track.guid)
        assertEquals("长街万象", track.title)
        assertEquals("ar-7", track.artists.single().guid)
        assertEquals("Real Artist", track.artists.single().name)
        assertEquals("al-7", track.album?.guid)
        assertEquals("Real Album", track.album?.name)
        assertEquals("flac", track.audioSpec?.format)

        // The library list still uses plain strings and must keep working.
        val listed = obj("""{"id":"s8","title":"T","artist":"A","album":"B","suffix":"mp3"}""").toTrackDto()
        assertEquals("A", listed.artists.single().name)
        assertEquals("B", listed.album?.name)
        assertEquals("mp3", listed.audioSpec?.format)
    }

    @Test
    fun `repeated plays collapse to one entry per song`() {
        val server = MockWebServer()
        server.enqueue(
            MockResponse().setBody(
                """{"histories":[
                     {"song":{"id":"a","title":"A","duration":100,"Format":"flac",
                              "artist":{"id":"ar-1","name":"Artist One"},
                              "album":{"id":"al-1","name":"Album One"}}},
                     {"song":{"id":"a","title":"A","duration":100}},
                     {"song":{"id":"b","title":"B","duration":120}}]}""".trimIndent()
            ).setHeader("Content-Type", "application/json")
        )
        server.start()
        try {
            val client = MusicFreeClient(
                http = OkHttpClient(),
                json = json,
                baseUrl = server.url("/"),
                auth = { MusicFreeAuth("jwt", "admin", "sub", "salt", "client-salt") },
            )
            val page = runBlocking { MusicFreeApi(client).history(1, 20) }.data!!

            // Three rows, two distinct songs: the duplicate must not survive,
            // otherwise LazyColumn sees the same key twice and crashes.
            assertEquals(listOf("a", "b"), page.list.map { it.guid })
            assertEquals(2, page.total)
            assertEquals("Artist One", page.list.first().artists.single().name)
            assertEquals("Album One", page.list.first().album?.name)
            assertEquals("flac", page.list.first().audioSpec?.format)

            val request = server.takeRequest()
            assertEquals("/rest/api/v1/play-history", request.path!!.substringBefore('?'))
            assertEquals("json", request.requestUrl!!.queryParameter("f"))
            assertEquals("Bearer jwt", request.getHeader("Authorization"))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `navidrome artist listing carries the per artist song count`() {
        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setBody(
                    """[{"id":"ar-1","name":"pilot","songCount":16,"albumCount":1,
                         "coverArt":"ar-ar-1","starred":false},
                        {"id":"ar-2","name":"harbor","songCount":0,"albumCount":2,
                         "coverArt":""}]""".trimIndent()
                )
                .setHeader("Content-Type", "application/json")
                .setHeader("X-Total-Count", "1951")
        )
        server.start()
        try {
            val page = runBlocking { MusicFreeApi(clientFor(server)).artists(1, 30) }.data!!

            assertEquals(1951, page.total)
            assertEquals(listOf("ar-1", "ar-2"), page.list.map { it.guid })
            // The whole point of switching endpoints: the count is real here.
            assertEquals(16, page.list.first().trackCount)
            assertEquals(1, page.list.first().albumCount)
            assertEquals(16, page.list.first().toDomain().trackCount)
            assertEquals(0, page.list[1].trackCount)

            val request = server.takeRequest()
            assertEquals("/api/artist", request.path!!.substringBefore('?'))
            // Navidrome routes take plain query params, not Subsonic ones.
            assertNull(request.requestUrl!!.queryParameter("f"))
            assertEquals("name", request.requestUrl!!.queryParameter("_sort"))
            assertEquals("0", request.requestUrl!!.queryParameter("_start"))
            assertEquals("30", request.requestUrl!!.queryParameter("_limit"))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `listing larger than the server page cap is stitched together`() {
        fun chunk(from: Int, count: Int): String = (from until from + count)
            .joinToString(",", "[", "]") {
                """{"id":"ar-$it","name":"Artist $it","songCount":$it,"albumCount":1}"""
            }
        val server = MockWebServer()
        // _limit is capped at 100 server side, so Paging's 200-per-load (or any
        // larger batch) has to be split without leaving gaps.
        listOf(chunk(0, 100), chunk(100, 100), chunk(200, 50)).forEach { body ->
            server.enqueue(
                MockResponse().setBody(body)
                    .setHeader("Content-Type", "application/json")
                    .setHeader("X-Total-Count", "250")
            )
        }
        server.start()
        try {
            val page = runBlocking { MusicFreeApi(clientFor(server)).artists(1, 250) }.data!!

            assertEquals(250, page.total)
            assertEquals(250, page.list.size)
            assertEquals("ar-0", page.list.first().guid)
            assertEquals("ar-249", page.list.last().guid)

            val requests = List(3) { server.takeRequest().requestUrl!! }
            assertEquals(listOf("0", "100", "200"), requests.map { it.queryParameter("_start") })
            assertEquals(listOf("100", "100", "50"), requests.map { it.queryParameter("_limit") })
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `artist detail and tracks use the navidrome routes`() {
        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setBody("""{"id":"ar-1","name":"pilot","songCount":2,"albumCount":1}""")
                .setHeader("Content-Type", "application/json")
        )
        server.enqueue(
            MockResponse()
                .setBody(
                    """[{"id":"s1","title":"夜航","artist":"pilot","artistId":"ar-1",
                         "album":"云图","albumId":"al-1","duration":215,"suffix":"flac",
                         "trackNumber":3,"starred":false,"hasCoverArt":true}]""".trimIndent()
                )
                .setHeader("Content-Type", "application/json")
                .setHeader("X-Total-Count", "2")
        )
        server.start()
        try {
            val api = MusicFreeApi(clientFor(server))
            val detail = runBlocking { api.artistDetail("ar-1") }.data!!
            assertEquals(2, detail.trackCount)

            val tracks = runBlocking { api.artistTracks("ar-1", 1, 30) }.data!!
            assertEquals(2, tracks.total)
            assertEquals(1, tracks.list.size)
            val track = tracks.list.single()
            assertEquals("夜航", track.title)
            assertEquals(215_000.0, track.duration, 0.01)
            assertEquals(3, track.trackNo)
            // Navidrome rows omit coverArt entirely; getCoverArt accepts an
            // album id, so the album is used as the cover handle.
            assertEquals("al-1", track.coverId)
            assertEquals("ar-1", track.artists.single().guid)

            val detailRequest = server.takeRequest()
            assertEquals("/api/artist/ar-1", detailRequest.path!!.substringBefore('?'))
            val tracksRequest = server.takeRequest()
            assertEquals("/api/song", tracksRequest.path!!.substringBefore('?'))
            assertEquals("ar-1", tracksRequest.requestUrl!!.queryParameter("artist_id"))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `missing navidrome routes fall back to the subsonic listing`() {
        val server = MockWebServer()
        // An older build without /api/artist answers with an error object, which
        // is not a JSON array.
        server.enqueue(
            MockResponse().setBody("""{"error":"not found"}""")
                .setHeader("Content-Type", "application/json")
                .setResponseCode(404)
        )
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"subsonic-response":{"status":"ok","artists":
                        [{"id":"ar-9","name":"legacy","albumCount":2}],"total":1}}""".trimIndent()
                )
                .setHeader("Content-Type", "application/json")
        )
        server.start()
        try {
            val page = runBlocking { MusicFreeApi(clientFor(server)).artists(1, 30) }.data!!

            assertEquals(1, page.list.size)
            assertEquals("legacy", page.list.single().name)
            assertEquals(2, page.list.single().albumCount)

            assertEquals("/api/artist", server.takeRequest().path!!.substringBefore('?'))
            assertEquals("/rest/api/v1/artists", server.takeRequest().path!!.substringBefore('?'))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `artist with songs on albums but no song artist id still resolves`() {
        // Real data: some albums' songs never had their artist_id rewritten, so
        // /api/artist reports songCount 0 even though the artist has tracks.
        val server = MockWebServer()
        // artistDetail: listing says 0, album sum says 4.
        server.enqueue(
            MockResponse().setBody("""{"id":"ar-x","name":"A Si","songCount":0,"albumCount":1}""")
                .setHeader("Content-Type", "application/json")
        )
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"subsonic-response":{"status":"ok","artist":{"id":"ar-x","name":"A Si",
                        "albumCount":1,"album":[{"id":"al-1","songCount":4}]}}}""".trimIndent()
                )
                .setHeader("Content-Type", "application/json")
        )
        // artistTracks: no rows by artist_id, so it walks the albums instead.
        server.enqueue(
            MockResponse().setBody("[]")
                .setHeader("Content-Type", "application/json")
                .setHeader("X-Total-Count", "0")
        )
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"subsonic-response":{"status":"ok","artist":{"id":"ar-x",
                        "album":[{"id":"al-1","songCount":2}]}}}""".trimIndent()
                )
                .setHeader("Content-Type", "application/json")
        )
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"subsonic-response":{"status":"ok","album":{"id":"al-1","song":[
                         {"id":"s1","title":"一","artist":"A Si","duration":100},
                         {"id":"s2","title":"二","artist":"A Si","duration":120}]}}}""".trimIndent()
                )
                .setHeader("Content-Type", "application/json")
        )
        server.start()
        try {
            val api = MusicFreeApi(clientFor(server))
            assertEquals(4, runBlocking { api.artistDetail("ar-x") }.data!!.trackCount)

            val tracks = runBlocking { api.artistTracks("ar-x", 1, 30) }.data!!
            assertEquals(listOf("s1", "s2"), tracks.list.map { it.guid })
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `roam window is synthesized from random songs with unique ids`() = runBlocking {
        val server = MockWebServer()
        repeat(2) {
            server.enqueue(
                MockResponse()
                    .setBody(
                        """{"subsonic-response":{"status":"ok","randomSongs":{"song":[
                             {"id":"s1","title":"一","artist":"A","duration":100},
                             {"id":"s2","title":"二","artist":"B","duration":120}]}}}""".trimIndent()
                    )
                    .setHeader("Content-Type", "application/json")
            )
        }
        server.start()
        try {
            val api = MusicFreeApi(clientFor(server))
            val first = api.roamStart("device").data!!

            assertEquals(
                "/rest/getRandomSongs.view?f=json&v=1.16.1&c=FnMusic&size=8",
                server.takeRequest().path,
            )
            assertEquals("s1", first.current?.track?.guid)
            assertEquals("s2", first.next?.track?.guid)
            assertNotNull(first.current?.roamId)

            // The same two songs come back, yet a fresh roam id must still be
            // handed out or extendRoamFrom stops requesting more.
            val second = api.roamNext("device", first.next!!.roamId!!).data!!
            assertEquals("s1", second.current?.track?.guid)
            assertNotEquals(first.current?.roamId, second.current?.roamId)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `roam window is empty when the library has no songs`() = runBlocking {
        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setBody("""{"subsonic-response":{"status":"ok","randomSongs":{"song":[]}}}""")
                .setHeader("Content-Type", "application/json")
        )
        server.start()
        try {
            val api = MusicFreeApi(clientFor(server))
            assertNull(api.roamStart("device").data!!.current)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `media urls are absolute and carry subsonic credentials`() {
        val auth = MusicFreeAuth("jwt-token", "admin", "deadbeef", "server-salt", "client-salt")
        val urls = MusicFreeUrls("http://192.168.1.10:14533/".toHttpUrl()) { auth }

        val stream = urls.streamUrl("song-1").toHttpUrl()
        assertEquals("192.168.1.10", stream.host)
        assertEquals(14533, stream.port)
        assertEquals("/rest/stream", stream.encodedPath)
        assertEquals("song-1", stream.queryParameter("id"))
        assertEquals("admin", stream.queryParameter("u"))
        assertEquals("client-salt", stream.queryParameter("s"))
        assertEquals(("deadbeef" + "client-salt").md5(), stream.queryParameter("t"))

        val cover = urls.coverUrl("al-al-1", 640)!!.toHttpUrl()
        assertEquals("/rest/getCoverArt", cover.encodedPath)
        assertEquals("al-al-1", cover.queryParameter("id"))
        assertEquals("640", cover.queryParameter("size"))
        assertNull(urls.coverUrl("", 640))
    }
}
