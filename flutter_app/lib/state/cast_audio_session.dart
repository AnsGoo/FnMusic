/// DLNA casting tuned for music.
///
/// [DlnaSession.loadMedia] in dart_cast is built around video: it funnels
/// every remote URL through its local HTTP proxy and labels the DIDL-Lite
/// metadata `videoItem` / `video/mp4`. Many audio renderers sniff the actual
/// stream and cope, but strict ones refuse the mismatched protocolInfo. This
/// subclass pushes the server's direct stream URL with proper audio metadata
/// instead, and polls position/transport state itself so the shared
/// [CastSession] streams keep working.
library;

import 'dart:async';

import 'package:dart_cast/dart_cast.dart';

/// A [DlnaSession] that casts audio via the source URL directly.
///
/// The server's stream endpoint embeds its own auth token, so the renderer
/// only needs LAN access to the media server — no local proxy hop — and the
/// direct body supports byte ranges, which DLNA renderers use to seek.
class AudioDlnaSession extends DlnaSession {
  AudioDlnaSession({required super.device, required super.description});

  /// Builds a session from a [CastDevice] produced by
  /// [DlnaDiscoveryProvider] — the parent's factory is not inherited.
  factory AudioDlnaSession.fromDevice(CastDevice device) {
    final parent = DlnaSession.fromDevice(device);
    return AudioDlnaSession(device: device, description: parent.description);
  }

  /// Standard DLNA flags (STREAMING | BACKGROUND | CONNECTION_STALL | V1.5),
  /// the same set VLC and MiniDLNA advertise. OP=01 grants byte and time
  /// seek, which the direct server stream supports.
  static const String _audioProtocolInfo =
      'http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;'
      'DLNA.ORG_OP=01;DLNA.ORG_CI=0;'
      'DLNA.ORG_FLAGS=01700000000000000000000000000000';

  final DlnaHttpClient _http = DlnaHttpClient();
  Timer? _pollTimer;
  bool _pollBusy = false;

  String? get _controlUrl => description.avTransportControlUrl;

  @override
  Future<void> loadMedia(CastMedia media) async {
    final controlUrl = _controlUrl;
    if (controlUrl == null) {
      throw StateError(
        'No AVTransport control URL for "${device.name}" — the device must '
        'come from DlnaDiscoveryProvider.',
      );
    }
    stateMachine.transitionTo(SessionState.loading);
    final duration =
        media.duration != null && media.duration! > Duration.zero
        ? media.duration
        : null;
    await _http.sendAction(
      controlUrl,
      DlnaServiceType.avTransport,
      'SetAVTransportURI',
      DlnaSoapBuilder.buildSetAVTransportURI(
        media.url,
        title: media.title,
        protocolInfo: _audioProtocolInfo,
        duration: duration == null
            ? null
            : NetworkUtils.formatDuration(duration),
      ),
    );
    await _http.sendAction(
      controlUrl,
      DlnaServiceType.avTransport,
      'Play',
      DlnaSoapBuilder.buildPlay(),
    );
    updatePosition(Duration.zero);
    if (duration != null) updateDuration(duration);
    stateMachine.transitionTo(SessionState.playing);
    _startPolling();
  }

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final controlUrl = _controlUrl;
    if (controlUrl != null) {
      try {
        await _http.sendAction(
          controlUrl,
          DlnaServiceType.avTransport,
          'Stop',
          DlnaSoapBuilder.buildStop(),
        );
      } catch (_) {
        // The renderer may already be gone; dropping the session locally is
        // what matters.
      }
    }
    stateMachine.transitionTo(SessionState.disconnected);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _http.close();
    super.dispose();
  }

  // ---- Renderer polling ---------------------------------------------------

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_pollBusy) return;
    if (stateMachine.state == SessionState.disconnected) return;
    final controlUrl = _controlUrl;
    if (controlUrl == null) return;
    _pollBusy = true;
    try {
      final position = await _http.sendAction(
        controlUrl,
        DlnaServiceType.avTransport,
        'GetPositionInfo',
        DlnaSoapBuilder.buildGetPositionInfo(),
      );
      final info = DlnaSoapParser.parsePositionInfo(position);
      updatePosition(info.position);
      if (info.duration > Duration.zero) updateDuration(info.duration);

      final transport = await _http.sendAction(
        controlUrl,
        DlnaServiceType.avTransport,
        'GetTransportInfo',
        DlnaSoapBuilder.buildGetTransportInfo(),
      );
      _handleTransport(DlnaSoapParser.parseTransportInfo(transport));

      // RenderingControl is optional on some renderers; a missing volume is
      // not worth failing the whole poll over.
      final renderingUrl = description.renderingControlUrl;
      if (renderingUrl != null) {
        try {
          final volume = await _http.sendAction(
            renderingUrl,
            DlnaServiceType.renderingControl,
            'GetVolume',
            DlnaSoapBuilder.buildGetVolume(),
          );
          updateVolume(DlnaSoapParser.parseVolume(volume) / 100.0);
        } catch (_) {}
      }
    } catch (_) {
      // A single dropped poll is normal on Wi-Fi renderers.
    } finally {
      _pollBusy = false;
    }
  }

  void _handleTransport(String transportState) {
    switch (transportState) {
      case 'PLAYING':
      case 'TRANSITIONING':
        if (stateMachine.state != SessionState.playing &&
            stateMachine.canTransitionTo(SessionState.playing)) {
          stateMachine.transitionTo(SessionState.playing);
        }
      case 'PAUSED_PLAYBACK':
        if (stateMachine.state != SessionState.paused &&
            stateMachine.canTransitionTo(SessionState.paused)) {
          stateMachine.transitionTo(SessionState.paused);
        }
      case 'STOPPED':
        if (stateMachine.state != SessionState.idle &&
            stateMachine.canTransitionTo(SessionState.idle)) {
          stateMachine.transitionTo(SessionState.idle);
          _pollTimer?.cancel();
          _pollTimer = null;
        }
      case 'NO_MEDIA_PRESENT':
        break;
    }
  }
}
