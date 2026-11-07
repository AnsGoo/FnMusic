package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * A hairline scrubbing bar.
 *
 * Material's `Slider` is sized for touch: a 20dp thumb on a 4dp track reads as a
 * heavy, pill-shaped control in a mouse-driven player bar. This one draws a 2dp
 * line with a small dot that grows only on hover, while keeping a comfortable
 * 18dp hit area so it is still easy to grab.
 */
@Composable
fun FnScrubber(
    fraction: Float,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    activeColor: Color = Fn.accent,
    trackColor: Color = Fn.track,
    thumbColor: Color = Fn.accent,
    onScrub: (Float) -> Unit,
    onCommit: () -> Unit = {},
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    var dragging by remember { mutableStateOf(false) }

    val engaged = enabled && (hovered || dragging)
    val trackHeight: Dp = if (engaged) 3.dp else 2.dp
    val thumbDiameter: Dp = if (engaged) 11.dp else 8.dp
    val value = fraction.coerceIn(0f, 1f)

    Box(
        modifier = modifier
            .height(18.dp)
            .hoverable(interaction, enabled = enabled)
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    val width = size.width.toFloat().coerceAtLeast(1f)
                    val down = awaitFirstDown(requireUnconsumed = false)
                    dragging = true
                    var last = (down.position.x / width).coerceIn(0f, 1f)
                    onScrub(last)
                    down.consume()
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: break
                        if (!change.pressed) break
                        last = (change.position.x / width).coerceIn(0f, 1f)
                        onScrub(last)
                        change.consume()
                    }
                    dragging = false
                    onCommit()
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = trackHeight.toPx()
            val thumbRadius = thumbDiameter.toPx() / 2f
            val centerY = size.height / 2f
            val startX = thumbRadius
            val endX = size.width - thumbRadius
            val span = (endX - startX).coerceAtLeast(1f)
            val headX = startX + span * value

            drawLine(
                color = trackColor,
                start = Offset(startX, centerY),
                end = Offset(endX, centerY),
                strokeWidth = stroke,
                cap = StrokeCap.Round,
            )
            if (value > 0f) {
                drawLine(
                    color = if (enabled) activeColor else trackColor,
                    start = Offset(startX, centerY),
                    end = Offset(headX, centerY),
                    strokeWidth = stroke,
                    cap = StrokeCap.Round,
                )
            }
            // An idle bar (no track loaded) keeps the groove only: a handle
            // parked at zero reads as a control you can drag when you cannot.
            if (enabled) {
                drawCircle(color = thumbColor, radius = thumbRadius, center = Offset(headX, centerY))
            }
        }
    }
}
