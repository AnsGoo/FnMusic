package com.seasonyuu.musicfly

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
    }
}
