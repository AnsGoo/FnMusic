package com.seasonyuu.fnmusic.desktop.data

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import com.seasonyuu.fnmusic.desktop.play.DesktopAudioPlayer
import kotlinx.coroutines.delay
import org.junit.Test
import java.nio.file.Files
import javax.sound.sampled.AudioSystem

/**
 * Exercises the desktop REST client against a real Music Free server.
 *
 * The test is skipped unless `FNMUSIC_TEST_SERVER` points at one, so a plain
 * `gradle test` stays hermetic:
 *
 * ```
 * FNMUSIC_TEST_SERVER=http://127.0.0.1:14533 \
 * FNMUSIC_TEST_USER=admin FNMUSIC_TEST_PASSWORD=admin \
 * ./gradlew :desktop:test --tests '*MusicFreeClientTest*'
 * ```
 */
class MusicFreeClientTest {

    private val server = System.getenv("FNMUSIC_TEST_SERVER")
    private val user = System.getenv("FNMUSIC_TEST_USER") ?: "admin"
    private val password = System.getenv("FNMUSIC_TEST_PASSWORD") ?: "admin"

    @Test
    fun `signs in and walks the library`() = runBlocking {
        assumeTrue("set FNMUSIC_TEST_SERVER to run this test", server != null)
        val client = MusicFreeClient()
        val session = client.login(server!!, user, password)
        assertTrue("login should return a token", session.token.isNotBlank())

        val tracks = client.tracks(1, 20)
        assertTrue("library should expose tracks", tracks.items.isNotEmpty())
        assertTrue("total should be reported", tracks.total >= tracks.items.size)
        val first = tracks.items.first()
        assertTrue("track titles should parse", first.title.isNotBlank())

        val albums = client.albums(1, 8)
        assertTrue("albums should parse", albums.items.isNotEmpty())
        val albumTracks = client.albumTracks(albums.items.first().id.value)
        assertTrue("album detail should list songs", albumTracks.isNotEmpty())

        val artists = client.artists(1, 8)
        assertTrue("artists should parse", artists.items.isNotEmpty())

        val found = client.searchTracks(first.title.take(4))
        assertTrue("search should find what the listing showed", found.isNotEmpty())

        // Favourites may legitimately be empty; the call must still parse.
        client.favorites()
        client.playlists()

        val stream = client.streamUrl(first.id.value)
        OkHttpClient().newCall(Request.Builder().url(stream).build()).execute().use { response ->
            assertEquals("stream should answer 200", 200, response.code)
            val contentType = response.header("Content-Type").orEmpty()
            assertTrue("stream should be audio, was $contentType", contentType.startsWith("audio/"))
            // Transcodes are chunked, so the length header is absent: read instead.
            val head = response.body?.byteStream()?.let { input ->
                val buffer = ByteArray(64 * 1024)
                input.read(buffer).coerceAtLeast(0)
            } ?: 0
            assertTrue("stream should carry bytes, read $head", head > 1024)
        }

        // Playback relies on the JLayer SPI being visible to the desktop runtime.
        OkHttpClient().newCall(Request.Builder().url(stream).build()).execute().use { response ->
            val cache = Files.createTempFile("fnmusic-test", ".mp3")
            response.body?.byteStream()?.use { input -> Files.newOutputStream(cache).use(input::copyTo) }
            AudioSystem.getAudioInputStream(cache.toFile()).use { decoded ->
                assertTrue("decoded audio should report a sample rate", decoded.format.sampleRate > 8000)
            }
            Files.deleteIfExists(cache)
        }
        Unit
    }

    /**
     * End-to-end playback check: fetch, decode and push through the system audio
     * line. Audible for a few seconds, so it only runs when asked for.
     */
    @Test
    fun `plays a track through the audio line`() = runBlocking {
        assumeTrue("set FNMUSIC_AUDIO_TEST=1 to run this test", System.getenv("FNMUSIC_AUDIO_TEST") != null)
        assumeTrue("set FNMUSIC_TEST_SERVER to run this test", server != null)

        val client = MusicFreeClient()
        client.login(server!!, user, password)
        val track = client.tracks(1, 1).items.first()
        val player = DesktopAudioPlayer(this)
        player.play(
            trackId = track.id.value,
            title = track.title,
            subtitle = "",
            streamUrl = client.streamUrl(track.id.value),
            durationSeconds = track.durationSeconds,
        )
        try {
            val deadline = System.currentTimeMillis() + 25_000
            while (player.state.value.positionSeconds < 0.5 &&
                player.state.value.error == null &&
                System.currentTimeMillis() < deadline
            ) {
                delay(200)
            }
            val state = player.state.value
            assertEquals("playback should not report an error, was ${state.error}", null, state.error)
            assertTrue("position should advance, was ${state.positionSeconds}", state.positionSeconds >= 0.5)
        } finally {
            player.stop()
        }
        Unit
    }
}
