/// Audio playback on top of `just_audio`.
///
/// The player owns no queue logic: it plays exactly the URL it is handed and
/// reports state. Queue navigation lives in [AppModel] so every platform (and
/// the tests) share one implementation.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../data/fn_connect.dart';
import 'background_task.dart';
import 'stream_probe.dart';
import 'ohos_media_control.dart';
import 'system_artwork.dart';

class PlaybackState {
  const PlaybackState({
    this.trackId,
    this.title = '',
    this.subtitle = '',
    this.coverId,
    this.coverUrl,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });

  final String? trackId;
  final String title;
  final String subtitle;
  final String? coverId;

  /// 封面绝对地址（Subsonic 的 coverArt 带上鉴权参数）。系统媒体中心靠它显示
  /// 锁屏封面，取不到时留空即可。
  final String? coverUrl;
  final bool playing;
  final Duration position;
  final Duration duration;
  final String? error;

  bool get hasTrack => trackId != null;

  PlaybackState copyWith({
    String? trackId,
    String? title,
    String? subtitle,
    String? coverId,
    String? coverUrl,
    bool? playing,
    Duration? position,
    Duration? duration,
    String? error,
    bool clearError = false,
  }) => PlaybackState(
    trackId: trackId ?? this.trackId,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    coverId: coverId ?? this.coverId,
    coverUrl: coverUrl ?? this.coverUrl,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    // Position ticks must not wipe the failure the listener is reading.
    error: clearError ? null : (error ?? this.error),
  );
}

class MfPlayer {
  MfPlayer();

  /// 主通道（与鸿蒙 just_audio 插件的 MainMethodCallHandler 对应）。锁屏
  /// 媒体面板的元数据由 App 直接下发：插件自己的 AVMetadataExtractor 对网络
  /// 流抽不到信息，而曲名/歌手/封面地址 App 本来就知道。其他平台没有这个
  /// handler，调用会抛 MissingPluginException，静默忽略即可。
  static const MethodChannel _justAudioMain = MethodChannel(
    'com.ryanheise.just_audio.methods',
  );

  /// Created on the first play so widget tests (and the splash screen) never
  /// touch a platform channel.
  AudioPlayer? _engine;

  AudioPlayer get _player => _engine ??= AudioPlayer();

  final ValueNotifier<PlaybackState> state = ValueNotifier(
    const PlaybackState(),
  );

  final List<StreamSubscription<dynamic>> _subs = [];
  VoidCallback? onCompleted;

  /// 鸿蒙锁屏 / 媒体面板的「上一首 / 下一首」最终落到这里，由队列所有者
  /// (AppModel) 注入。注册平台通道需要 WidgetsBinding，所以放在第一次真正
  /// 播放时的 [_bind] 里，纯 Dart 测试构造 AppModel 不会碰到它。
  Future<void> Function()? onSystemNext;
  Future<void> Function()? onSystemPrevious;

  /// Fires when a track cannot be played: (trackId, human readable reason).
  /// The queue owner uses it to explain the failure and move on.
  void Function(String trackId, String reason)? onFailed;

  double _volume = 1;

  /// Guards [onFailed] from firing twice for the same track — `setUrl` throws
  /// and the error stream reports the same failure again.
  String? _reportedFailure;

  /// Last URL handed to the engine, needed to diagnose errors that arrive on
  /// the event stream instead of through [play]'s catch block.
  String? _currentUrl;

  /// Wall-clock fallback for transcode streams. The mp3 transcoder answers
  /// with a chunked, unseekable body whose position AVPlayer never advances,
  /// which froze the progress bar while audio kept playing. While active the
  /// engine's position stream is ignored and a timer advances [position].
  bool _clockActive = false;
  DateTime? _clockStamp;
  Timer? _clock;

  /// One probe per track even when both failure channels fire.
  String? _probedTrackId;
  Future<String>? _probeResult;

  /// Cover bytes for the system media UI. Kept alive across tracks so replaying
  /// a song does not fetch the same image twice.
  final SystemArtworkLoader _artwork = SystemArtworkLoader();

  /// Bumped on every play/stop: a slow cover download for the previous track
  /// must not overwrite the new track's lock-screen metadata.
  int _metadataGeneration = 0;

  /// 最近一次完整下发给系统面板的曲目信息（含已下载封面）。鸿蒙 AVSession 是
  /// 异步创建的，第一次 setMetadata 可能赶在会话就绪之前；播放真正开始后
  /// 再补推一次，锁屏就一定与 App 内一致。
  Map<String, dynamic>? _systemPayload;
  bool _systemMetadataConfirmed = false;

  /// 鸿蒙没有 audio_service：AVSession 的切歌命令由 ohos 插件转发到 Dart。
  /// 队列回调由 AppModel 注入；没有注入时（例如直接使用 MfPlayer 的测试）
  /// 不注册通道，避免在 binding 未初始化的环境里断言。
  void _ensureSystemControlBind() {
    final onNext = onSystemNext;
    final onPrevious = onSystemPrevious;
    if (onNext != null && onPrevious != null) {
      MfOhosMediaControl.bind(onNext: onNext, onPrevious: onPrevious);
    }
  }

  void _bind() {
    final player = _player;
    _subs.add(
      player.positionStream.listen((position) {
        final current = state.value;
        if (!current.hasTrack) return;
        // The transcode fallback owns the timeline while active.
        if (_clockActive) return;
        // Ignore the tail beyond the reported duration; the player can drift a
        // few hundred milliseconds past the end while switching tracks.
        final clamped = current.duration > Duration.zero && position > current.duration
            ? current.duration
            : position;
        state.value = current.copyWith(position: clamped);
      }),
    );
    _subs.add(
      player.durationStream.listen((duration) {
        // A chunked/live body (or a decode the engine cannot size) reports
        // zero; that must not wipe the duration the server metadata provided.
        if (duration == null || duration <= Duration.zero) return;
        state.value = state.value.copyWith(duration: duration);
      }),
    );
    _subs.add(
      player.playerStateStream.listen((playerState) {
        final current = state.value;
        final finished =
            playerState.processingState == ProcessingState.completed;
        final playing = playerState.playing && !finished;
        state.value = current.copyWith(playing: playing);
        // 鸿蒙的长时任务要在真的出声之后才申请：系统会校验 AVSession 是否
        // 处于播放态，提前申请会被判成「没有在放音频」而拒掉。
        if (playing) unawaited(BackgroundAudioTask.ensureRunning());
        // 会话此刻一定已激活，补推一次当前曲目，纠正首次推送早于会话创建的
        // 时序问题（其它平台会抛 MissingPluginException，静默忽略）。
        if (playing && !_systemMetadataConfirmed) {
          _systemMetadataConfirmed = true;
          unawaited(_repushSystemMetadata(_metadataGeneration));
        }
        if (finished) onCompleted?.call();
      }),
    );
    _subs.add(
      player.errorStream.listen((error) {
        // Skipping to another track aborts the previous connection; that is a
        // normal interruption, not a broken file.
        if (_isInterruption(error)) return;
        final trackId = state.value.trackId;
        final url = _currentUrl;
        if (trackId == null || url == null) {
          state.value = state.value.copyWith(
            playing: false,
            error: '播放中断：${error.message}',
          );
          return;
        }
        unawaited(_failFromStream(trackId, url, error.message ?? '$error'));
      }),
    );
  }

  static bool _isInterruption(Object error) {
    if (error is PlayerInterruptedException) return true;
    final message = error is PlayerException ? error.message ?? '' : '$error';
    return message.toLowerCase().contains('aborted');
  }

  /// Reports an error the engine pushed on its event stream. The message from
  /// AVPlayer is usually a generic English sentence, so ask the server what is
  /// actually wrong with the file first.
  Future<void> _failFromStream(String trackId, String url, String message) async {
    final reason = await _explain(trackId, url, message);
    if (state.value.trackId != trackId) return;
    state.value = state.value.copyWith(playing: false, error: reason);
    _reportFailure(trackId, reason);
  }

  void _reportFailure(String trackId, String reason) {
    if (_reportedFailure == trackId) return;
    _reportedFailure = trackId;
    onFailed?.call(trackId, reason);
  }

  /// Advances [position] with wall-clock time while the engine's own stream is
  /// useless (transcoded chunked bodies). Keeps ticking at 4 Hz; a paused or
  /// stopped player simply stops moving the stamp forward.
  void _startClock() {
    _clockActive = true;
    _clockStamp = DateTime.now();
    _clock ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      final current = state.value;
      if (!current.playing || !current.hasTrack) {
        _clockStamp = DateTime.now();
        return;
      }
      final now = DateTime.now();
      final elapsed = now.difference(_clockStamp!);
      _clockStamp = now;
      var next = current.position + elapsed;
      if (current.duration > Duration.zero && next > current.duration) {
        next = current.duration;
      }
      state.value = current.copyWith(position: next);
    });
  }

  void _stopClock() {
    _clockActive = false;
    _clock?.cancel();
    _clock = null;
  }

  /// Loads and starts [streamUrl]. Returns false when the server could not
  /// hand over playable audio; the reason is exposed through [state] and
  /// [onFailed].
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    required String streamUrl,
    String? artist,
    String? coverId,
    String? coverUrl,
    Duration? duration,
    bool transcoded = false,
  }  ) async {
    if (_subs.isEmpty) _bind();
    // 每次开播都重新绑定：Flutter 引擎热重启 / 通道重建后，只在第一次绑定
    // 的 handler 会失效，原生转发过来的锁屏命令就全部石沉大海。
    _ensureSystemControlBind();
    _reportedFailure = null;
    _probedTrackId = null;
    _probeResult = null;
    _currentUrl = streamUrl;
    _stopClock();
    final generation = ++_metadataGeneration;
    _systemMetadataConfirmed = false;
    state.value = PlaybackState(
      trackId: trackId,
      title: title,
      subtitle: subtitle,
      coverId: coverId,
      coverUrl: coverUrl,
      playing: false,
      duration: duration ?? Duration.zero,
    );
    if (transcoded) _startClock();
    // 锁屏面板必须在点击后立刻反馈：鸿蒙的 setUrl 会等 AVPlayer prepare，
    // 慢的时候要 6 秒，等它返回再推元数据会让「下一首」看起来毫无反应。
    // duration 随这次一起下发（转码流 chunked 在系统播放器侧拿不到时长，
    // 缺了它锁屏面板的开始/结束时间会显示 "--"）；封面则由该方法异步补推，
    // 不阻塞音频加载。
    unawaited(_pushSystemMetadata(
      title, artist, coverUrl, duration, generation, trackId,
    ));
    try {
      // Feiniu relay endpoints (Fn Connect) expect their cookie on audio
      // requests too; other servers never see it.
      await _player.setUrl(
        streamUrl,
        headers: fnRelayHeadersFor(streamUrl),
      );
      await _player.setVolume(_volume);
      unawaited(_player.play());
      return true;
    } on PlayerInterruptedException {
      // Another load replaced this one; not a failure of the file.
      return false;
    } catch (error) {
      if (_isInterruption(error)) return false;
      final reason = await _explain(trackId, streamUrl, error);
      // The user may have picked another track while the probe was running.
      if (state.value.trackId != trackId) return false;
      state.value = state.value.copyWith(playing: false, error: reason);
      _reportFailure(trackId, reason);
      return false;
    }
  }

  /// 推送锁屏播控面板元数据（仅鸿蒙的 vendored just_audio 插件实现了
  /// setMetadata；iOS/Android/macOS 未实现该 handler，异常直接忽略）。
  ///
  /// 分两步：先把歌名/歌手/时长推下去，面板立刻能显示；封面则由 App 带鉴权头
  /// 下载后再补一次。让系统服务自己去请求 `rest/getCoverArt` 会缺飞牛网关的
  /// Authorization/Cookie，拿到的只会是 401 —— 这正是锁屏封面消失的原因。
  Future<void> _pushSystemMetadata(
    String title,
    String? artist,
    String? coverUrl,
    Duration? duration,
    int generation,
    String trackId,
  ) async {
    final payload = <String, dynamic>{
      'title': title,
      'artist': artist ?? '',
      'artUri': coverUrl ?? '',
      'durationMs': duration?.inMilliseconds ?? 0,
      // 稳定曲目标识：同一首歌的多次推送共用一个 AVSession assetId。
      'trackId': trackId,
    };
    if (generation == _metadataGeneration) _systemPayload = payload;
    try {
      // 第一次调用兼作能力探测：其它平台没有这个 handler，直接抛
      // MissingPluginException，后面就没必要下载封面了。
      await _justAudioMain.invokeMethod('setMetadata', payload);
    } catch (_) {
      // 平台不支持：Android/iOS 走各自的 media_session/notification 通道。
      _systemPayload = null;
      return;
    }
    // 能走到这里就说明对端是鸿蒙的 vendored 插件（唯一实现 setMetadata 的
    // 平台）；不用再靠 Platform.operatingSystem 字符串判断，少一处版本差异。
    if (generation != _metadataGeneration) return;
    final bytes = await _artwork.load(coverUrl);
    // 下载期间用户可能已经切歌，迟到的封面不能盖到新歌上。
    if (bytes == null || generation != _metadataGeneration) return;
    final withArtwork = <String, dynamic>{
      ...payload,
      // StandardMessageCodec：Uint8List → ArkTS Uint8Array / ArrayBuffer。
      'artwork': bytes,
    };
    if (generation == _metadataGeneration) _systemPayload = withArtwork;
    try {
      await _justAudioMain.invokeMethod('setMetadata', withArtwork);
    } catch (_) {
      // 封面补推失败不影响播放，歌名/时长第一次调用时已生效。
    }
  }

  /// 播放真正开始后补推一次。鸿蒙的 AVSession 由插件异步创建，会话就绪前
  /// 到达的 setMetadata 只更新了原生侧快照，系统面板可能还停在上一首。
  Future<void> _repushSystemMetadata(int generation) async {
    final payload = _systemPayload;
    if (payload == null || generation != _metadataGeneration) return;
    try {
      await _justAudioMain.invokeMethod('setMetadata', payload);
    } catch (_) {
      // 平台不支持或会话临时不可用：音频播放本身不受影响。
    }
  }

  /// Turns an opaque platform error into something the listener can act on,
  /// probing at most once per track whatever channel reported the failure.
  Future<String> _explain(String trackId, String streamUrl, Object error) {
    if (_probedTrackId == trackId && _probeResult != null) return _probeResult!;
    _probedTrackId = trackId;
    _probeResult = probeStream(streamUrl).then(
      (problem) => problem ?? '无法播放这首歌：$error',
    );
    return _probeResult!;
  }

  /// Pauses when playing, resumes when paused, and does nothing without a track.
  void toggle() {
    if (!state.value.hasTrack) return;
    if (_player.playing) {
      unawaited(pause());
    } else {
      unawaited(resume());
    }
  }

  /// Explicit transport hooks for the system media session: the notification's
  /// play/pause button must not have to guess the current state.
  Future<void> pause() async {
    if (!state.value.hasTrack) return;
    await _engine?.pause();
  }

  Future<void> resume() async {
    if (!state.value.hasTrack) return;
    await _engine?.play();
  }

  Future<void> seek(Duration position) async {
    if (!state.value.hasTrack) return;
    // Transcoded chunked streams have no ranges, so the engine can only reach
    // data it already buffered; a farther seek throws. Drop it silently — the
    // wall-clock fallback keeps the bar honest afterwards.
    try {
      await _player.seek(position);
      if (_clockActive) {
        state.value = state.value.copyWith(position: position);
        _clockStamp = DateTime.now();
      }
    } catch (_) {}
  }

  void setVolume(double value) {
    _volume = value.clamp(0, 1);
    unawaited(_player.setVolume(_volume));
  }

  double get volume => _volume;

  Future<void> stop() async {
    _stopClock();
    _metadataGeneration++;
    _systemPayload = null;
    _systemMetadataConfirmed = false;
    await _engine?.stop();
    state.value = const PlaybackState();
    // Nothing is loaded any more, so the HarmonyOS long-running task would just
    // hold the process awake for no reason.
    unawaited(BackgroundAudioTask.release());
  }

  void dispose() {
    _stopClock();
    _metadataGeneration++;
    _artwork.dispose();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
    unawaited(BackgroundAudioTask.release());
    state.dispose();
  }
}
