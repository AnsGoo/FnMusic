/// 鸿蒙（HarmonyOS NEXT）后台播放的「长时任务」桥接。
///
/// 鸿蒙和 Android 的差别在于：只申请前台服务还不够，应用必须在
/// `module.json5` 里声明 `backgroundModes: ["audioPlayback"]`，并在运行时显式
/// 起一个长时任务，系统才允许进程在灭屏 / 切后台后继续跑。少了这一步，锁屏后
/// 音频线程会被功耗管理挂起，表现为「放几秒就停」。
///
/// 系统媒体面板那部分不用这里操心：just_audio 的 ohos 分支在初始化播放器时就
/// 建好并激活了 AVSession，锁屏上的播放控制由它提供。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundAudioTask {
  BackgroundAudioTask._();

  static const _channel = MethodChannel('com.seasonyuu.musicfly/background_audio');

  /// `dart:io` 在鸿蒙 fork 上把操作系统报成 `ohos`（与 `theme.dart` 里的判断
  /// 保持一致）。用字符串判断而不是 `Platform.isOhos`：官方 SDK 的 dart:io
  /// 没有这个 getter，写了会编译不过。
  static bool get supported =>
      !kIsWeb && Platform.operatingSystem == 'ohos';

  static bool _running = false;

  /// 起长时任务。播放前调用，重复调用无副作用。
  static Future<void> ensureRunning() async {
    if (!supported || _running) return;
    // 先置位再 await：连续切歌时不会并发打进来两次。
    _running = true;
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // 理论上不会发生（supported 已经限定了平台），真发生了也只是没有后台
      // 保活，不该影响播放。
      _running = false;
    } catch (error) {
      _running = false;
      debugPrint('鸿蒙长时任务启动失败：$error');
    }
  }

  /// 停长时任务。彻底停止播放（[MfPlayer.stop] / dispose）时调用；暂停不要停，
  /// 否则锁屏上的播放键点下去时进程已被冻结，反而叫不醒。
  static Future<void> release() async {
    if (!supported || !_running) return;
    _running = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('鸿蒙长时任务停止失败：$error');
    }
  }
}
