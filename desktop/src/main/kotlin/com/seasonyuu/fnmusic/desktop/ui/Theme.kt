package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * The desktop palette.
 *
 * Values are taken from the Music Free mark: warm near-black vinyl, a vermilion
 * label and cream lettering. Every surface in the app derives from these six
 * tones so the three panes read as one material.
 */
object Fn {
    val bg = Color(0xFF131010)
    val surface = Color(0xFF1B1715)
    val surfaceAlt = Color(0xFF241F1B)
    val raised = Color(0xFF2C2521)
    val border = Color(0xFF342C26)
    /** Slider grooves: a touch lighter than a border so a hairline still reads. */
    val track = Color(0xFF3E342C)

    val accent = Color(0xFFE85C3A)
    val accentHover = Color(0xFFF26E4D)
    val accentWash = Color(0xFF3B211A)
    val cream = Color(0xFFF6EFE3)

    val text = Color(0xFFF4EEE4)
    val textSoft = Color(0xFFC9BFB2)
    val muted = Color(0xFF9A8F82)
    val faint = Color(0xFF6B6259)
}

private val FnTypography = Typography(
    displaySmall = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.6).sp),
    headlineSmall = TextStyle(fontSize = 21.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.3).sp),
    titleMedium = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium),
    bodyMedium = TextStyle(fontSize = 13.5.sp),
    bodySmall = TextStyle(fontSize = 12.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.4.sp),
)

@Composable
fun FnTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Fn.accent,
            onPrimary = Fn.cream,
            background = Fn.bg,
            onBackground = Fn.text,
            surface = Fn.surface,
            onSurface = Fn.text,
            surfaceVariant = Fn.surfaceAlt,
            onSurfaceVariant = Fn.textSoft,
            outline = Fn.border,
        ),
        typography = FnTypography,
        content = content,
    )
}

/** `325.4` -> `5:25`; `3700` -> `1:01:40`. */
fun formatTime(seconds: Double): String {
    if (seconds.isNaN() || seconds <= 0.0) return "0:00"
    val total = seconds.toLong()
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
