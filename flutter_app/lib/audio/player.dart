/// Audio playback on top of `just_audio`.
///
/// The player owns no queue logic: it plays exactly the URL it is handed and
/// reports state. Queue navigation lives in [AppModel] so every platform (and
/// the tests) share one implementation.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'stream_probe.dart';

class PlaybackState {
  const PlaybackState({
    this.trackId,
    this.title = '',
    this.subtitle = '',
    this.coverId,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });

  final String? trackId;
  final String title;
  final String subtitle;
  final String? coverId;
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
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    // Position ticks must not wipe the failure the listener is reading.
    error: clearError ? null : (error ?? this.error),
  );
}

class MfPlayer {
  MfPlayer();

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

  /// One probe per track even when both failure channels fire.
  String? _probedTrackId;
  Future<String>? _probeResult;

  void _bind() {
    final player = _player;
    _subs.add(
      player.positionStream.listen((position) {
        final current = state.value;
        if (!current.hasTrack) return;
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
        if (duration == null) return;
        state.value = state.value.copyWith(duration: duration);
      }),
    );
    _subs.add(
      player.playerStateStream.listen((playerState) {
        final current = state.value;
        final finished =
            playerState.processingState == ProcessingState.completed;
        state.value = current.copyWith(playing: playerState.playing && !finished);
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

  /// Loads and starts [streamUrl]. Returns false when the server could not
  /// hand over playable audio; the reason is exposed through [state] and
  /// [onFailed].
  Future<bool> play({
    required String trackId,
    required String title,
    required String subtitle,
    required String streamUrl,
    String? coverId,
    Duration? duration,
  }) async {
    if (_subs.isEmpty) _bind();
    _reportedFailure = null;
    _probedTrackId = null;
    _probeResult = null;
    _currentUrl = streamUrl;
    state.value = PlaybackState(
      trackId: trackId,
      title: title,
      subtitle: subtitle,
      coverId: coverId,
      playing: false,
      duration: duration ?? Duration.zero,
    );
    try {
      await _player.setUrl(streamUrl);
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
      unawaited(_player.pause());
    } else {
      unawaited(_player.play());
    }
  }

  Future<void> seek(Duration position) async {
    if (!state.value.hasTrack) return;
    await _player.seek(position);
  }

  void setVolume(double value) {
    _volume = value.clamp(0, 1);
    unawaited(_player.setVolume(_volume));
  }

  double get volume => _volume;

  Future<void> stop() async {
    await _engine?.stop();
    state.value = const PlaybackState();
  }

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
    state.dispose();
  }
}
