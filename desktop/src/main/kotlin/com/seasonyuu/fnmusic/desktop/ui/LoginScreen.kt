package com.seasonyuu.fnmusic.desktop.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seasonyuu.fnmusic.desktop.AppModel
import org.jetbrains.skia.Image as SkiaImage

private val logo: ImageBitmap? by lazy {
    runCatching {
        val stream = Thread.currentThread().contextClassLoader
            ?.getResourceAsStream("music_free_logo.png")
            ?: return@runCatching null
        stream.use { SkiaImage.makeFromEncoded(it.readBytes()).toComposeImageBitmap() }
    }.getOrNull()
}

/**
 * The connection gate.
 *
 * Like the phone build, only one backend is offered: a Music Free server. The
 * address is free-form so a LAN box, a tunnel host or `localhost` all work
 * without a separate discovery step.
 */
@Composable
fun LoginScreen(
    model: AppModel,
    url: String,
    onUrlChange: (String) -> Unit,
    username: String,
    onUsernameChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxSize().background(Fn.bg),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.widthIn(max = 400.dp).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val mark = logo
            if (mark != null) {
                Image(
                    bitmap = mark,
                    contentDescription = "Music Free",
                    modifier = Modifier.size(104.dp).clip(RoundedCornerShape(percent = 50)),
                )
            }
            Spacer(Modifier.height(22.dp))
            Text("Music Free", color = Fn.text, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            Text(
                "让听歌这件事简单一点",
                color = Fn.muted,
                fontSize = 13.sp,
            )
            Spacer(Modifier.height(26.dp))

            FnFormField(
                value = url,
                onValueChange = onUrlChange,
                label = "服务器地址",
                placeholder = "http://192.168.1.10:4533",
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            FnFormField(
                value = username,
                onValueChange = onUsernameChange,
                label = "账号",
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            FnFormField(
                value = password,
                onValueChange = onPasswordChange,
                label = "密码",
                password = true,
                onSubmit = { model.login(url, username, password) },
                modifier = Modifier.fillMaxWidth(),
            )

            val error = model.error
            if (error != null) {
                Spacer(Modifier.height(14.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Fn.accentWash)
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                ) {
                    Text(error, color = Fn.accentHover, fontSize = 12.sp)
                }
            }

            Spacer(Modifier.height(22.dp))
            FnPrimaryButton(
                label = if (model.connecting) "连接中…" else "连接",
                onClick = { model.login(url, username, password) },
                enabled = !model.connecting,
                height = 40.dp,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(16.dp))
            Text(
                "需要 Music Free 服务端 · 兼容 Navidrome / Subsonic",
                color = Fn.faint,
                fontSize = 11.5.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}
