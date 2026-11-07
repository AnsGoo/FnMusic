package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jetbrains.skia.Image as SkiaImage
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Cover art is fetched lazily and kept in a bounded in-memory cache.
 *
 * The Android build leans on Coil; on the desktop one HTTP call plus a Skia
 * decode is all that is needed, and it avoids a second image stack for a grid
 * that rarely holds more than a few hundred thumbnails.
 */
private val http = OkHttpClient.Builder()
    .connectTimeout(8, TimeUnit.SECONDS)
    .readTimeout(15, TimeUnit.SECONDS)
    .build()

private val cache = ConcurrentHashMap<String, ImageBitmap>()
private val inFlight = ConcurrentHashMap<String, Boolean>()

private fun decode(url: String): ImageBitmap? = runCatching {
    val request = Request.Builder().url(url).build()
    http.newCall(request).execute().use { response ->
        if (!response.isSuccessful) return null
        val bytes = response.body?.bytes() ?: return null
        if (bytes.isEmpty()) return null
        SkiaImage.makeFromEncoded(bytes).toComposeImageBitmap()
    }
}.getOrNull()

@Composable
fun rememberCover(url: String?): ImageBitmap? {
    var bitmap by remember(url) { mutableStateOf(url?.let { cache[it] }) }
    LaunchedEffect(url) {
        if (url.isNullOrBlank() || cache.containsKey(url)) return@LaunchedEffect
        if (inFlight.putIfAbsent(url, true) != null) return@LaunchedEffect
        val loaded = withContext(Dispatchers.IO) { decode(url) }
        inFlight.remove(url)
        if (loaded != null) {
            if (cache.size > 400) cache.clear()
            cache[url] = loaded
            bitmap = loaded
        }
    }
    return bitmap
}

/** A square cover that falls back to the vinyl mark while loading or when missing. */
@Composable
fun CoverArt(
    url: String?,
    modifier: Modifier = Modifier,
    size: Dp? = null,
    corner: Dp = 6.dp,
    circular: Boolean = false,
) {
    val shape = if (circular) RoundedCornerShape(percent = 50) else RoundedCornerShape(corner)
    val bitmap = rememberCover(url)
    Box(
        modifier = modifier
            .then(if (size != null) Modifier.size(size) else Modifier)
            .clip(shape)
            .background(Fn.surfaceAlt),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            FnGlyph(FnIcon.Album, size = size?.times(0.42f) ?: 32.dp, tint = Fn.faint)
        }
    }
}
