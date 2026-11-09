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
  }) async {
    if (_subs.isEmpty) _bind();
    _reportedFailure = null;
    _probedTrackId = null;
    _probeResult = null;
    _currentUrl = streamUrl;
    _stopClock();
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
    try {
      // Feiniu relay endpoints (Fn Connect) expect their cookie on audio
      // requests too; other servers never see it.
      await _player.setUrl(
        streamUrl,
        headers: fnRelayHeadersFor(streamUrl),
      );
      await _player.setVolume(_volume);
      // 鸿蒙锁屏播控面板的内容：加载成功后把曲目信息推给 AVSession。
      unawaited(_pushSystemMetadata(title, artist, coverUrl));
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
  Future<void> _pushSystemMetadata(
    String title,
    String? artist,
    String? coverUrl,
  ) async {
    try {
      await _justAudioMain.invokeMethod('setMetadata', {
        'title': title,
        'artist': artist ?? '',
        'artUri': coverUrl ?? '',
      });
    } catch (_) {
      // 平台不支持：Android/iOS 走各自的 media_session/notification 通道。
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
    await _engine?.stop();
    state.value = const PlaybackState();
    // Nothing is loaded any more, so the HarmonyOS long-running task would just
    // hold the process awake for no reason.
    unawaited(BackgroundAudioTask.release());
  }

  void dispose() {
    _stopClock();
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
