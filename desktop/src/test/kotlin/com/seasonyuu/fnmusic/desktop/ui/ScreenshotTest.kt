package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seasonyuu.fnmusic.desktop.AppModel
import com.seasonyuu.fnmusic.desktop.Section
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path

/**
 * Renders the window offscreen so the layout can be inspected without a display.
 *
 * Iteration aid only: it needs a live server and writes PNGs to
 * `desktop/build/screens`. Skipped unless `FNMUSIC_SHOTS` is set.
 */
class ScreenshotTest {

    private val enabled = System.getenv("FNMUSIC_SHOTS") != null
    private val dir: Path = Path.of("build/screens")

    /** The scene is rasterised at 2x for a 1180x780 dp window. */
    private fun capture(name: String, settleFrames: Int = 1, content: @Composable () -> Unit) {
        Files.createDirectories(dir)
        val scene = ImageComposeScene(
            width = 1180 * 2,
            height = 780 * 2,
            density = Density(2f),
            content = content,
        )
        try {
            scene.render(0)
            var time = 0L
            repeat(settleFrames) {
                time += 60_000_000L
                scene.render(time)
            }
            Files.write(dir.resolve("$name.png"), scene.render(time + 60_000_000L).encodeToData()!!.bytes)
        } finally {
            scene.close()
        }
    }

    @Test
    fun `renders every pane`() = runBlocking {
        assumeTrue("set FNMUSIC_SHOTS=1 to render screenshots", enabled)

        val model = AppModel(CoroutineScope(Dispatchers.Default))
        capture("login", settleFrames = 2) {
            FnTheme {
                LoginScreen(
                    model = model,
                    url = "http://192.168.1.10:4533",
                    onUrlChange = {},
                    username = "admin",
                    onUsernameChange = {},
                    password = "secret",
                    onPasswordChange = {},
                )
            }
        }

        model.restoreSession()
        assumeTrue("a seeded session with reachable server is required", awaitTracks(model))
        capture("library", settleFrames = 30) { FnTheme { BrowserScreen(model) } }

        model.select(Section.Albums)
        awaitFor { model.albums.isNotEmpty() }
        capture("albums", settleFrames = 25) { FnTheme { BrowserScreen(model) } }

        model.select(Section.Artists)
        awaitFor { model.artists.isNotEmpty() }
        capture("artists", settleFrames = 15) { FnTheme { BrowserScreen(model) } }

        model.select(Section.Playlists)
        awaitFor { model.playlists.isNotEmpty() }
        capture("playlists", settleFrames = 15) { FnTheme { BrowserScreen(model) } }

        model.select(Section.Albums)
        awaitFor { model.albums.isNotEmpty() }
        model.openAlbum(model.albums.first())
        awaitFor { model.detail?.tracks?.isNotEmpty() == true }
        capture("album-detail", settleFrames = 20) { FnTheme { BrowserScreen(model) } }

        model.back()
        model.updateQuery("周杰伦")
        model.submitSearch()
        awaitFor { model.searchResults.isNotEmpty() }
        capture("search", settleFrames = 15) { FnTheme { BrowserScreen(model) } }

        capture("scrubbers", settleFrames = 2) {
            FnTheme {
                Column(
                    modifier = Modifier.fillMaxSize().background(Fn.surface).padding(48.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    Text("进程 42%", color = Fn.muted, fontSize = 12.sp)
                    FnScrubber(fraction = 0.42f, modifier = Modifier.width(460.dp), onScrub = {})
                    Text("音量 72%", color = Fn.muted, fontSize = 12.sp)
                    FnScrubber(
                        fraction = 0.72f,
                        modifier = Modifier.width(160.dp),
                        thumbColor = Fn.textSoft,
                        activeColor = Fn.muted,
                        onScrub = {},
                    )
                }
            }
        }
        Unit
    }

    private suspend fun awaitTracks(model: AppModel): Boolean =
        withTimeoutOrNull(20_000) {
            while (model.tracks.isEmpty()) delay(200)
            true
        } ?: false

    private suspend fun awaitFor(condition: () -> Boolean) {
        withTimeoutOrNull(15_000) {
            while (!condition()) delay(150)
            true
        }
    }
}
