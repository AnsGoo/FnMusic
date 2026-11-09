/// 让系统把本应用当成「音乐播放器」，而不是一个随手可暂停的普通 App。
///
/// iOS 上这一步是硬性前提：不把 `AVAudioSession` 的 category 设成 `playback`，
/// 系统会按默认的 `soloAmbient` 处理 —— 切后台、锁屏就静音，锁屏上也不会出现
/// 播放控制（Now Playing）。Android 上则决定音频焦点（来电、其他 App 播放时的
/// 暂停/压低），以及音量键该调「媒体音量」还是「铃声」。
///
/// 只在有原生实现的平台调用；桌面 Windows 和鸿蒙没有 audio_session 插件，
/// 调用会抛 [MissingPluginException]，忽略即可。
library;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

Future<void> configureSystemAudio() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (error) {
    // 播放本身不依赖它：拿不到就退化成系统默认策略。
    debugPrint('系统音频会话配置失败（不影响播放）：$error');
  }
}
