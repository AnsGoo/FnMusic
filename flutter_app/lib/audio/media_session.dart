/// 把本地播放接入系统的媒体中心：Android 的通知栏 / 锁屏 / 蓝牙耳机按键；
/// iOS / macOS 的控制中心「正在播放」与锁屏控件。
///
/// 只负责「上报状态 + 收下发命令」，播放本身仍在 [MfPlayer] 里。没有这层时，
/// 应用退到后台、屏幕一锁，Android 会把进程当成普通的缓存进程回收掉，音频也就
/// 停了；[AudioService] 拉起一个 foreground service + MediaSession，系统才认为
/// 这是一个正在放音乐的进程，同时把锁屏与通知栏的控制权交给它。
///
/// Android / iOS / macOS 共用 audio_service 的实现（darwin 分支在 macOS 上走
/// MPNowPlayingInfoCenter / MPRemoteCommandCenter，即控制中心的「正在播放」）。
/// 鸿蒙走的是另一条路：系统媒体面板由 just_audio 的 ohos 分支创建 AVSession 来
/// 提供，灭屏存活靠「长时任务」，见 [background_task.dart]；Windows/Linux 没有
/// 接入，直接跳过。
library;

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// `PlaybackState` 两边都有：audio_service 的是媒体中心上报的状态，本项目的是
// 播放器状态。用前缀把本项目的隔开，避免各处 hide/重命名。
import 'player.dart' as mf;

/// 当前平台有没有系统级媒体会话可接。
///
/// macOS 也算：audio_service 的 darwin 实现原生支持（MPNowPlayingInfoCenter），
/// 启用后控制中心 / 菜单栏才会出现「正在播放」卡片。
bool get mediaSessionSupported =>
    !kIsWeb &&
    (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

class MfMediaSession {
  MfMediaSession._(this._handler);

  static MfMediaSession? _instance;

  /// 未初始化时（桌面 / 鸿蒙 / 测试）为 null，调用方一律按可选处理。
  static MfMediaSession? get instance => _instance;

  final _MfAudioHandler _handler;

  mf.MfPlayer? _player;

  /// 初始化系统媒体会话。失败不影响播放本身，所以异常只记日志。
  static Future<MfMediaSession?> start() async {
    if (!mediaSessionSupported) return null;
    if (_instance != null) return _instance;
    try {
      final handler = await AudioService.init(
        builder: _MfAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.seasonyuu.musicfly.playback',
          androidNotificationChannelName: '播放控制',
          androidNotificationChannelDescription: '锁屏和通知栏里的播放控制',
          // 通知栏用单色音符，否则默认的彩色启动图标会被系统渲染成白方块。
          androidNotificationIcon: 'drawable/ic_stat_music',
          // 播放中常驻，避免用户清理通知后前台服务被系统回收。
          androidNotificationOngoing: true,
          // 暂停时退出前台服务：不播放就不要再占着「正在运行」的位置。
          androidStopForegroundOnPause: true,
          androidResumeOnClick: true,
          androidShowNotificationBadge: false,
        ),
      );
      return _instance = MfMediaSession._(handler);
    } catch (error, stack) {
      debugPrint('系统媒体会话初始化失败，仅影响锁屏控制：$error\n$stack');
      return null;
    }
  }

  /// Android 13 起，媒体通知要用户授权才显示在通知栏 / 锁屏。播放中的前台服务
  /// 通知是豁免的，但一暂停服务就退出前台、通知降级为普通通知，没授权会直接
  /// 消失 —— 锁屏上的控制器跟着一起没了，用户就再也没法从锁屏点回播放。
  /// 所以第一次真正播放时讨一次权限，而不是启动时就弹窗。
  static bool _askedNotificationPermission = false;

  static Future<void> ensureNotificationPermission() async {
    if (_askedNotificationPermission || !mediaSessionSupported) return;
    if (!Platform.isAndroid) return;
    _askedNotificationPermission = true;
    try {
      await const MethodChannel(
        'musicfly/notification',
      ).invokeMethod<void>('requestPostNotifications');
    } catch (error) {
      // 通道缺失（旧版壳 / 测试）不影响播放，只是没有通知权限。
      debugPrint('请求通知权限失败：$error');
    }
  }

  /// 把 [player] 的状态同步到系统媒体中心，并把媒体中心下发的命令交回队列。
  /// 队列的上一首 / 下一首在 [onNext] / [onPrevious] 里由 `AppModel` 提供。
  void bind(
    mf.MfPlayer player, {
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    _handler
      ..onPlay = player.resume
      ..onPause = player.pause
      ..onSeek = player.seek
      ..onStop = player.stop
      ..onNext = onNext
      ..onPrevious = onPrevious;
    unbind();
    _player = player;
    // `state` 是 ValueNotifier，没有 stream；位置每 200ms 变一次，监听器里由
    // handler 自己节流，只推秒级增量。
    player.state.addListener(_push);
    _push();
  }

  void _push() {
    final player = _player;
    if (player != null) _handler.publish(player.state.value);
  }

  void unbind() {
    _player?.state.removeListener(_push);
    _player = null;
  }

  void dispose() {
    unbind();
    if (_instance == this) _instance = null;
  }
}

class _MfAudioHandler extends BaseAudioHandler {
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function(Duration position)? onSeek;

  // 媒体中心只需要秒级粒度：播放位置每秒推一次就够，`PlaybackState.speed`
  // 会让系统自己在两次推送之间插值。全量推送会把平台通道刷爆。
  static const _positionEpsilon = Duration(seconds: 1);

  String? _lastTrackId;
  bool? _lastPlaying;
  Duration _lastPosition = Duration.zero;

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> seek(Duration position) async => onSeek?.call(position);

  @override
  Future<void> stop() async {
    await onStop?.call();
    await super.stop();
  }

  /// 把播放器状态翻译成媒体中心要的两样东西：当前曲目（[mediaItem]）和
  /// 可播状态（[playbackState]，决定通知栏按钮长什么样）。
  void publish(mf.PlaybackState state) {
    final trackId = state.trackId;
    if (trackId == null) {
      if (mediaItem.value != null) mediaItem.add(null);
      _lastTrackId = null;
      _lastPlaying = null;
      playbackState.add(
        PlaybackState(processingState: AudioProcessingState.idle),
      );
      return;
    }

    final artUri = _parseUri(state.coverUrl);
    final item = MediaItem(
      id: trackId,
      title: state.title,
      artist: state.subtitle.isEmpty ? null : state.subtitle,
      duration: state.duration > Duration.zero ? state.duration : null,
      artUri: artUri,
    );
    // 换歌才重建 MediaItem：位置跳动不该让通知栏重新加载封面。
    final previous = mediaItem.value;
    if (previous == null ||
        previous.id != item.id ||
        previous.title != item.title ||
        previous.artist != item.artist ||
        previous.duration != item.duration ||
        previous.artUri != item.artUri) {
      mediaItem.add(item);
    }

    final positionJumped =
        (state.position - _lastPosition).abs() >= _positionEpsilon;
    if (_lastTrackId == trackId &&
        _lastPlaying == state.playing &&
        !positionJumped) {
      return;
    }
    _lastTrackId = trackId;
    _lastPlaying = state.playing;
    _lastPosition = state.position;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (state.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: state.playing,
        updatePosition: state.position,
        bufferedPosition: state.position,
        speed: 1.0,
      ),
    );
  }

  static Uri? _parseUri(String? value) {
    if (value == null || value.isEmpty) return null;
    return Uri.tryParse(value);
  }
}
