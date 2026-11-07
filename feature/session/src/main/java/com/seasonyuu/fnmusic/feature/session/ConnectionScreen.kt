package com.seasonyuu.fnmusic.feature.session

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.seasonyuu.fnmusic.core.designsystem.FlowingLightBackground
import com.seasonyuu.fnmusic.core.designsystem.FlowingLightStyle
import com.seasonyuu.fnmusic.core.designsystem.FnTextSecondary
import com.seasonyuu.fnmusic.core.designsystem.R
import com.seasonyuu.fnmusic.core.model.ConnectionProfile
import com.seasonyuu.fnmusic.core.model.Endpoint
import com.seasonyuu.fnmusic.core.model.LoginForm
import com.seasonyuu.fnmusic.core.model.SessionState

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ConnectionScreen(
    state: SessionState,
    onConnect: (ConnectionProfile, CharArray) -> Unit,
    form: LoginForm,
    onFormChange: (LoginForm) -> Unit,
    modifier: Modifier = Modifier,
) {
    var passwordVisible by remember { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val connecting = state is SessionState.Restoring || state is SessionState.Locating ||
        state is SessionState.RelaySelected || state is SessionState.RelayActive ||
        state is SessionState.MusicAuthenticated
    val canSubmit = !connecting && form.username.isNotBlank() && form.password.isNotBlank() &&
        form.musicFreeUrl.isNotBlank()
    val submit = {
        if (canSubmit) {
            passwordVisible = false
            focus.clearFocus()
            keyboard?.hide()
            // Music Free is the only supported source.
            val endpoint: Endpoint = Endpoint.MusicFree(form.musicFreeUrl.trim())
            onConnect(ConnectionProfile(endpoint, form.username.trim(), form.allowPrivateLanHttp), form.password.toCharArray())
        }
    }

    Box(modifier.fillMaxSize().background(Color(0xFF090C13))) {
        FlowingLightBackground(FlowingLightStyle.Login)
        // Keep the moving light behind the form subdued enough for readable labels.
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(
            listOf(Color.Black.copy(alpha = .16f), Color(0xD9080B12)),
        )))
        Column(
            Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState())
                .safeDrawingPadding().padding(horizontal = 28.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Column(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Image(painterResource(R.drawable.music_free_logo), null, Modifier.size(64.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "Music Free",
                            fontSize = 32.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                        )
                        Text(
                            "连接你的个人音乐服务器",
                            style = MaterialTheme.typography.bodyMedium, color = FnTextSecondary,
                        )
                    }
                }
                Spacer(Modifier.height(36.dp))
                if (connecting) {
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 48.dp).semantics { liveRegion = LiveRegionMode.Polite },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        LoadingIndicator(Modifier.size(40.dp), color = Color.White)
                        Text(connectionMessage(state), color = FnTextSecondary)
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                        LoginField(
                            value = form.musicFreeUrl,
                            onValueChange = { onFormChange(form.copy(musicFreeUrl = it)) },
                            label = "Music Free 地址",
                            placeholder = "http://192.168.1.10:14533",
                            keyboardType = KeyboardType.Uri,
                            onNext = { focus.moveFocus(FocusDirection.Down) },
                        )
                        PrivateLanHttpCheckbox(form, onFormChange)
                        LoginField(form.username, { onFormChange(form.copy(username = it)) }, "音乐账号", "输入音乐账号", onNext = { focus.moveFocus(FocusDirection.Down) })
                        LoginField(
                            form.password, { onFormChange(form.copy(password = it)) }, "密码", "输入密码",
                            keyboardType = KeyboardType.Password,
                            imeAction = ImeAction.Done,
                            onDone = submit,
                            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                            trailingIcon = {
                                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                                    Icon(if (passwordVisible) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility, if (passwordVisible) "隐藏密码" else "显示密码", tint = FnTextSecondary)
                                }
                            },
                        )
                    }
                    Spacer(Modifier.height(16.dp))
                    Text("自动记住登录信息，仅加密保存在本机", style = MaterialTheme.typography.bodySmall, color = FnTextSecondary)
                    if (state is SessionState.Error) {
                        Text(state.message, Modifier.padding(top = 16.dp).semantics { liveRegion = LiveRegionMode.Polite }, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
                    }
                    Spacer(Modifier.height(28.dp))
                    Button(
                        onClick = submit,
                        enabled = canSubmit,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 58.dp),
                        shape = RoundedCornerShape(16.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color(0xFF101218), disabledContainerColor = Color.White.copy(alpha = .24f), disabledContentColor = Color.White.copy(alpha = .65f)),
                    ) {
                        Text("登录音乐库", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.width(10.dp))
                        Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, Modifier.size(20.dp))
                    }
                }
                Spacer(Modifier.height(32.dp))
                Text("MUSIC FREE  /  私人音乐，随时聆听", color = Color.White.copy(alpha = .5f), style = MaterialTheme.typography.labelSmall, letterSpacing = 1.sp)
            }
        }
    }
}

@Composable
private fun PrivateLanHttpCheckbox(
    form: LoginForm,
    onFormChange: (LoginForm) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(form.allowPrivateLanHttp, { onFormChange(form.copy(allowPrivateLanHttp = it)) })
        Text("允许局域网 HTTP（仅限可信网络）", style = MaterialTheme.typography.bodySmall, color = FnTextSecondary)
    }
}

@Composable
private fun LoginField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Next,
    onNext: () -> Unit = {},
    onDone: () -> Unit = {},
    visualTransformation: VisualTransformation = VisualTransformation.None,
    trailingIcon: @Composable (() -> Unit)? = null,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, color = FnTextSecondary, style = MaterialTheme.typography.labelLarge)
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = label },
            placeholder = { Text(placeholder, style = MaterialTheme.typography.bodyMedium) },
            // The visible label sits above the field, like the Web login form.
            singleLine = true,
            shape = RoundedCornerShape(16.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color.White.copy(alpha = .38f),
                unfocusedBorderColor = Color.Transparent,
                disabledBorderColor = Color.Transparent,
                disabledContainerColor = Color.White.copy(alpha = .08f),
                disabledTextColor = Color.White,
                focusedContainerColor = Color.White.copy(alpha = .16f),
                unfocusedContainerColor = Color.White.copy(alpha = .08f),
                cursorColor = Color.White,
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
            ),
            visualTransformation = visualTransformation,
            trailingIcon = trailingIcon,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
            keyboardActions = KeyboardActions(onNext = { onNext() }, onDone = { onDone() }),
        )
    }
}

private fun connectionMessage(state: SessionState): String = when (state) {
    SessionState.Restoring -> "正在恢复登录状态…"
    SessionState.Locating -> "正在准备连接…"
    SessionState.RelaySelected -> "正在建立远程连接…"
    SessionState.RelayActive -> "正在连接音乐库…"
    SessionState.MusicAuthenticated -> "正在获取服务器配置…"
    else -> "正在连接…"
}
