/// 鸿蒙锁屏 / 媒体面板的「上一首 / 下一首」命令。
///
/// Android / iOS / macOS 由 audio_service 的 MediaSession 接管（见
/// media_session.dart）；鸿蒙没有 audio_service 实现，系统 AVSession 是
/// just_audio 的 ohos 分支在 ArkTS 侧创建的，命令会先落到插件里。而插件内部
/// 的播放列表恒为 1 首（本 App 每次只 setUrl 一首，队列在 AppModel），原生
/// 切歌无从下手。插件因此把命令经下面这条通道转发过来，这里再交给 AppModel
/// 的队列，保证系统面板与应用内按钮用的是同一个 next / previous。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MfOhosMediaControl {
  MfOhosMediaControl._();

  /// 与 ohos 侧 MainMethodCallHandler 里创建的 MethodChannel 同名。
  static const String channelName = 'com.seasonyuu.musicfly/media_control';

  static const MethodChannel _channel = MethodChannel(channelName);

  /// 每次开播都会重新绑定：Flutter 引擎热重启后旧的 handler 会失效，只绑一次
  /// 时锁屏按钮发出去的命令会被系统静默丢弃。`setMethodCallHandler` 是覆盖式，
  /// 重复调用没有副作用（其它平台不会收到这条通道的消息，注册本身不发起平台
  /// 调用，widget tests 里也安全）。
  static void bind({
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    _channel.setMethodCallHandler((call) async {
      debugPrint('MF media control: received ${call.method}');
      // 不 await 队列切换：一次 setUrl 可能要几秒，回执卡住时系统侧会认为
      // 命令没送达；命令本身在 AppModel 里串行合并，不怕连点。
      if (call.method == 'next') {
        unawaited(onNext().catchError((Object error) {
          debugPrint('MF media control: next failed: $error');
        }));
      } else if (call.method == 'previous') {
        unawaited(onPrevious().catchError((Object error) {
          debugPrint('MF media control: previous failed: $error');
        }));
      }
      return null;
    });
    debugPrint('MF media control: handler bound');
  }
}
