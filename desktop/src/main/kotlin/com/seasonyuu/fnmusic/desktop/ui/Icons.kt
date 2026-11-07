package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Icons as 24x24 path data.
 *
 * Compose Desktop has no `material-icons` artifact wired into this build, and
 * pulling one in for a dozen glyphs is not worth the dependency: each icon is a
 * single path string drawn on a scaled canvas.
 */
enum class FnIcon(val path: String) {
    Play("M8 5v14l11-7z"),
    Pause("M6 19h4V5H6v14zm8-14v14h4V5h-4z"),
    Next("M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"),
    Previous("M6 6h2v12H6zm3.5 6l8.5 6V6z"),
    Search(
        "M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 " +
            "5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 " +
            "5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
    ),
    Heart(
        "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09" +
            "C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z",
    ),
    Tracks(
        "M4 6h11v2H4V6zm0 5h11v2H4v-2zm0 5h8v2H4v-2zm16-9v9.28c-.47-.17-.97-.28-1.5-.28" +
            "-1.93 0-3.5 1.34-3.5 3s1.57 3 3.5 3 3.5-1.34 3.5-3V9h3V6h-5z",
    ),
    Album(
        "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14.5" +
            "c-2.49 0-4.5-2.01-4.5-4.5S9.51 7.5 12 7.5s4.5 2.01 4.5 4.5-2.01 4.5-4.5 4.5z" +
            "m0-5.5c-.55 0-1 .45-1 1s.45 1 1 1 1-.45 1-1-.45-1-1-1z",
    ),
    Artist(
        "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4z" +
            "m0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z",
    ),
    Playlist(
        "M3 6h13v2H3V6zm0 5h13v2H3v-2zm0 5h9v2H3v-2zm15-9v9.28c-.47-.17-.97-.28-1.5-.28" +
            "-1.93 0-3.5 1.34-3.5 3s1.57 3 3.5 3 3.5-1.34 3.5-3V9h3V6h-5z",
    ),
    Back("M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"),
    Refresh(
        "M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8" +
            "c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6" +
            "c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z",
    ),
    Volume(
        "M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z" +
            "M14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77" +
            "s-2.99-7.86-7-8.77z",
    ),
    Logout(
        "M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14" +
            "c0 1.1.9 2 2 2h8v-2H4V5z",
    ),
    Close(
        "M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 " +
            "13.41 12z",
    ),
}

@Composable
fun FnGlyph(
    icon: FnIcon,
    size: Dp = 20.dp,
    tint: Color = Fn.text,
    modifier: Modifier = Modifier,
) {
    val path = remember(icon) { PathParser().parsePathString(icon.path).toPath() }
    Canvas(modifier = modifier.then(Modifier.size(size))) {
        val side = this.size.minDimension
        scale(scaleX = side / 24f, scaleY = side / 24f, pivot = androidx.compose.ui.geometry.Offset.Zero) {
            drawPath(path, SolidColor(tint))
        }
    }
}
