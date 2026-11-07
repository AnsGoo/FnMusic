package com.seasonyuu.fnmusic.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.seasonyuu.fnmusic.desktop.ui.BrowserScreen
import com.seasonyuu.fnmusic.desktop.ui.Fn
import com.seasonyuu.fnmusic.desktop.ui.FnTheme
import com.seasonyuu.fnmusic.desktop.ui.LoginScreen
import java.awt.Dimension

fun main() = application {
    val scope = rememberCoroutineScope()
    val model = remember { AppModel(scope) }

    LaunchedEffect(Unit) { model.restoreSession() }

    Window(
        onCloseRequest = {
            model.player.stop()
            exitApplication()
        },
        title = "FnMusic",
        state = rememberWindowState(width = 1180.dp, height = 780.dp),
    ) {
        window.minimumSize = Dimension(940, 640)
        FnTheme {
            AppRoot(model)
        }
    }
}

/**
 * Decides between the connection gate and the library.
 *
 * Form state lives here rather than inside the login screen so the typed
 * address survives the transition out and back in after a logout.
 */
@Composable
private fun AppRoot(model: AppModel) {
    var url by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Box(Modifier.fillMaxSize().background(Fn.bg)) {
        if (model.session == null) {
            LoginScreen(
                model = model,
                url = url,
                onUrlChange = { url = it },
                username = username,
                onUsernameChange = { username = it },
                password = password,
                onPasswordChange = { password = it },
            )
        } else {
            BrowserScreen(model)
        }
    }
}
