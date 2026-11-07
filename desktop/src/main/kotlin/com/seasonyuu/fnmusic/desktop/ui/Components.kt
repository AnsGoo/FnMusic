package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The one primary action style: a filled vermilion pill. */
@Composable
fun FnPrimaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    height: Dp = 42.dp,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val fill = when {
        !enabled -> Fn.raised
        hovered -> Fn.accentHover
        else -> Fn.accent
    }
    Box(
        modifier = modifier
            .height(height)
            .clip(RoundedCornerShape(10.dp))
            .background(fill)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (enabled) Fn.cream else Fn.faint,
            fontSize = 13.5.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** A quiet bordered control used for secondary actions. */
@Composable
fun FnGhostButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: FnIcon? = null,
    height: Dp = 34.dp,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    Row(
        modifier = modifier
            .height(height)
            .clip(RoundedCornerShape(8.dp))
            .background(if (hovered) Fn.raised else Fn.surfaceAlt)
            .border(1.dp, Fn.border, RoundedCornerShape(8.dp))
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        if (icon != null) FnGlyph(icon, size = 15.dp, tint = if (hovered) Fn.text else Fn.textSoft)
        Text(label, color = if (hovered) Fn.text else Fn.textSoft, fontSize = 12.5.sp)
    }
}

/** A round icon button; `active` paints it with the accent. */
@Composable
fun FnIconButton(
    icon: FnIcon,
    onClick: () -> Unit,
    size: Dp = 34.dp,
    glyph: Dp = 17.dp,
    enabled: Boolean = true,
    active: Boolean = false,
    tint: Color = Fn.textSoft,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val resolved = when {
        !enabled -> Fn.faint
        active -> Fn.accent
        hovered -> Fn.text
        else -> tint
    }
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(percent = 50))
            .background(if (hovered && enabled) Fn.raised else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        FnGlyph(icon, size = glyph, tint = resolved)
    }
}

/** Section label used above every listing. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        color = Fn.faint,
        fontSize = 10.5.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 1.1.sp,
    )
}

/**
 * The compact search box used in the library toolbar.
 *
 * `OutlinedTextField` carries a 56dp minimum height with floating labels, which
 * is right for a login form and wrong for a toolbar. This one is a plain
 * `BasicTextField` in a 34dp pill with the magnifier inline, so the toolbar
 * stays the height of its buttons.
 */
@Composable
fun FnSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "搜索歌曲、专辑…",
    onSubmit: (() -> Unit)? = null,
    onClear: (() -> Unit)? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val hovered by interaction.collectIsHoveredAsState()
    val borderColor = when {
        focused -> Fn.accent
        hovered -> Fn.muted
        else -> Fn.border
    }

    Row(
        modifier = modifier
            .height(34.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(Fn.surfaceAlt)
            .border(1.dp, borderColor, RoundedCornerShape(9.dp))
            .hoverable(interaction)
            .padding(start = 10.dp, end = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FnGlyph(FnIcon.Search, size = 13.dp, tint = if (focused) Fn.muted else Fn.faint)
        Box(Modifier.width(7.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty()) {
                Text(placeholder, color = Fn.faint, fontSize = 12.5.sp, maxLines = 1)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = TextStyle(color = Fn.text, fontSize = 12.5.sp),
                cursorBrush = SolidColor(Fn.accent),
                interactionSource = interaction,
                modifier = Modifier
                    .fillMaxWidth()
                    .onPreviewKeyEvent { event ->
                        if (event.type != KeyEventType.KeyDown) {
                            false
                        } else {
                            when (event.key) {
                                Key.Enter, Key.NumPadEnter -> {
                                    onSubmit?.invoke()
                                    true
                                }
                                Key.Escape -> {
                                    onClear?.invoke()
                                    true
                                }
                                else -> false
                            }
                        }
                    },
            )
        }
        if (value.isNotEmpty() && onClear != null) {
            FnIconButton(FnIcon.Close, onClick = onClear, size = 22.dp, glyph = 11.dp)
        } else {
            Box(Modifier.width(7.dp))
        }
    }
}

/**
 * A compact labelled form field for the login gate.
 *
 * `OutlinedTextField` reserves 56dp plus a floating label, which looks like a
 * phone form on a desktop window. Here the label sits above the box in small
 * type and the box itself is 38dp, so three fields fit without dominating the
 * screen.
 */
@Composable
fun FnFormField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    password: Boolean = false,
    onSubmit: (() -> Unit)? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val hovered by interaction.collectIsHoveredAsState()
    val borderColor = when {
        focused -> Fn.accent
        hovered -> Fn.muted
        else -> Fn.border
    }

    Column(modifier) {
        Text(
            label,
            color = if (focused) Fn.accent else Fn.muted,
            fontSize = 11.5.sp,
            fontWeight = FontWeight.Medium,
        )
        Spacer(Modifier.height(6.dp))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(38.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Fn.surfaceAlt)
                .border(1.dp, borderColor, RoundedCornerShape(8.dp))
                .hoverable(interaction)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty() && placeholder != null) {
                    Text(placeholder, color = Fn.faint, fontSize = 13.sp, maxLines = 1)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    singleLine = true,
                    textStyle = TextStyle(color = Fn.text, fontSize = 13.sp),
                    cursorBrush = SolidColor(Fn.accent),
                    visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
                    interactionSource = interaction,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { onSubmit?.invoke() }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .onPreviewKeyEvent { event ->
                            if (event.type == KeyEventType.KeyDown &&
                                (event.key == Key.Enter || event.key == Key.NumPadEnter)
                            ) {
                                onSubmit?.invoke()
                                true
                            } else {
                                false
                            }
                        },
                )
            }
        }
    }
}
