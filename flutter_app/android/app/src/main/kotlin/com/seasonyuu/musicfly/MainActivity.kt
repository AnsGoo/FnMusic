package com.seasonyuu.musicfly

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FnConnect stable device ID: ANDROID_ID is scoped to the device +
        // user + app signing key and survives uninstall/reinstall (reset only
        // by a factory reset), which is exactly what the fnOS trusted-device
        // (`did`) binding needs. No permission required on Android 8+.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "musicfly/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                    else -> result.notImplemented()
                }
            }
        // Android 13+ 的媒体通知（锁屏 / 通知栏播放控制器）需要 POST_NOTIFICATIONS
        // 才显示：前台服务通知本身豁免，但暂停后服务退出前台、通知变成普通通知，
        // 没授权就会瞬间消失，用户就点不回播放了。由 Dart 侧在第一次播放时请求，
        // 不在启动时弹窗打扰。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "musicfly/notification")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPostNotifications" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                POST_NOTIFICATIONS_REQUEST
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val POST_NOTIFICATIONS_REQUEST = 4701
    }
}
