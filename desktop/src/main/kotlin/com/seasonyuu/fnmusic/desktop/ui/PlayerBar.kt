package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seasonyuu.fnmusic.desktop.AppModel

/**
 * The transport bar.
 *
 * Position is driven by the audio thread through a [androidx.compose.runtime.StateFlow];
 * while the user drags the scrubber, the local value wins so the thumb does not
 * snap back on every progress tick.
 */
@Composable
fun PlayerBar(model: AppModel) {
    val audio by model.player.state.collectAsState()
    var scrubbing by remember { mutableStateOf<Float?>(null) }
    var volume by remember { mutableStateOf(0.85f) }

    val duration = audio.durationSeconds
    val position = scrubbing ?: audio.positionSeconds.toFloat()

    val coverId = remember(audio.trackId, model.queueIndex) {
        model.queue.getOrNull(model.queueIndex)
            ?.takeIf { it.id.value == audio.trackId }
            ?.coverId
    }
    val coverUrl = remember(coverId) { coverId?.let { model.coverUrl(it) } }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(78.dp)
            .background(Fn.surface)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CoverArt(coverUrl, size = 48.dp, corner = 6.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.width(180.dp)) {
            Text(
                audio.title.ifBlank { "未在播放" },
                color = Fn.text,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                audio.subtitle.ifBlank { if (audio.buffering) "缓冲中…" else "选择一首歌开始" },
                color = Fn.faint,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Spacer(Modifier.width(14.dp))
        FnIconButton(
            FnIcon.Previous,
            onClick = { model.previous() },
            size = 32.dp,
            glyph = 16.dp,
            enabled = model.queue.isNotEmpty(),
        )
        Box(Modifier.width(6.dp))
        FnIconButton(
            if (audio.playing) FnIcon.Pause else FnIcon.Play,
            onClick = { model.togglePlay() },
            size = 40.dp,
            glyph = 19.dp,
            active = true,
            tint = Fn.accent,
        )
        Box(Modifier.width(6.dp))
        FnIconButton(
            FnIcon.Next,
            onClick = { model.next() },
            size = 32.dp,
            glyph = 16.dp,
            enabled = model.queue.isNotEmpty(),
        )

        Spacer(Modifier.width(16.dp))
        Text(
            formatTime(position.toDouble()),
            color = Fn.muted,
            fontSize = 11.sp,
            modifier = Modifier.width(42.dp),
        )
        FnScrubber(
            fraction = if (duration > 0) (position / duration).toFloat() else 0f,
            enabled = duration > 0,
            modifier = Modifier.weight(1f),
            onScrub = { fraction -> if (duration > 0) scrubbing = (fraction * duration).toFloat() },
            onCommit = {
                val target = scrubbing
                scrubbing = null
                if (target != null) model.player.seekTo(target.toDouble())
            },
        )
        Text(
            formatTime(duration),
            color = Fn.muted,
            fontSize = 11.sp,
            modifier = Modifier.width(44.dp),
        )

        Spacer(Modifier.width(10.dp))
        FnGlyph(FnIcon.Volume, size = 15.dp, tint = Fn.faint)
        FnScrubber(
            fraction = volume,
            modifier = Modifier.width(88.dp),
            thumbColor = Fn.textSoft,
            activeColor = Fn.muted,
            onScrub = {
                volume = it
                model.player.setVolume(it)
            },
        )
    }
}
