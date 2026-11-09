/// The single source of truth for navigation, listings and playback.
///
/// Mirrors the old desktop state machine so behaviour stays identical: an empty
/// section always reloads, one queue drives the player, and pagination is capped
/// by the server-reported total.
library;

import 'dart:async';

import 'package:dart_cast/dart_cast.dart' hide ServerInfo;
import 'package:flutter/foundation.dart';

import '../audio/media_session.dart';
import '../audio/player.dart';
import '../data/device_did.dart';
import '../data/fn_connect.dart';
import '../data/fnos_client.dart';
import '../data/models.dart';
import '../data/musicfree_client.dart';
import '../data/session_store.dart';
import 'cast_audio_session.dart';

enum Section { home, tracks, albums, artists, playlists, favorites }

extension SectionInfo on Section {
  String get label => switch (this) {
    Section.home => '首页',
    Section.tracks => '歌曲库',
    Section.albums => '专辑',
    Section.artists => '艺术家',
    Section.playlists => '歌单',
    Section.favorites => '收藏',
  };

  String get subtitle => switch (this) {
    Section.home => '你的音乐概览',
    Section.tracks => '全部曲目',
    Section.albums => '按专辑浏览',
    Section.artists => '按艺术家浏览',
    Section.playlists => '我的歌单',
    Section.favorites => '我喜欢的音乐',
  };
}

/// A drill-down page opened from a listing.
class Detail {
  const Detail({
    required this.title,
    required this.subtitle,
    this.coverId,
    this.tracks = const [],
    this.albums = const [],
    this.loading = true,
    this.isAlbum = false,
    this.isArtist = false,
  });

  final String title;
  final String subtitle;
  final String? coverId;
  final List<Track> tracks;

  /// An artist page lists the albums instead of a flat track list.
  final List<Album> albums;
  final bool loading;
  final bool isAlbum;

  /// Marks the artist page, which shows a circular avatar and the album
  /// grid instead of a track list.
  final bool isArtist;

  Detail copyWith({
    List<Track>? tracks,
    List<Album>? albums,
    bool? loading,
    String? subtitle,
  }) => Detail(
    title: title,
    subtitle: subtitle ?? this.subtitle,
    coverId: coverId,
    tracks: tracks ?? this.tracks,
    albums: albums ?? this.albums,
    loading: loading ?? this.loading,
    isAlbum: isAlbum,
    isArtist: isArtist,
  );
}

class AppModel extends ChangeNotifier {
  AppModel({
    MusicFreeClient? client,
    SessionStore? store,
    MfPlayer? player,
    @visibleForTesting SessionFactory? castSessionFactory,
  }) : client = client ?? MusicFreeClient(),
       _store = store ?? SessionStore(),
       player = player ?? MfPlayer(),
       // Named private parameters do not exist; the lint's suggestion does
       // not apply to a test-only injection.
       // ignore: prefer_initializing_formals
       _castSessionFactory = castSessionFactory {
    this.player.onCompleted = _handleCompleted;
    this.player.onFailed = _handleFailure;
    // Lock screen / headset buttons drive the same queue as the in-app
    // transport, so there is only ever one source of truth for "next".
    MfMediaSession.instance?.bind(
      this.player,
      onNext: next,
      onPrevious: previous,
    );
  }

  final MusicFreeClient client;
  final MfPlayer player;
  final SessionStore _store;

  /// Overridable so tests can hand back a fake [CastSession].
  final SessionFactory? _castSessionFactory;

  MusicFreeSession? _session;
  bool _connecting = false;
  String? _error;

  ServerInfo? _serverInfo;
  bool _probingServer = false;

  // ---- Multi-address failover (LAN preferred) ------------------------------

  /// Periodic reachability probe across all configured server addresses.
  Timer? _addressTimer;
  Map<String, ServerInfo> _addressStatuses = {};
  bool _probingAddresses = false;

  Section _section = Section.home;
  Detail? _detail;

  bool _loading = false;
  bool _loadingMore = false;

  List<Track> _tracks = const [];
  List<Album> _albums = const [];
  List<Artist> _artists = const [];
  List<Playlist> _playlists = const [];
  List<Track> _favorites = const [];

  String _query = '';
  bool _searching = false;
  // Every list type carries its own result bucket, because each section
  // renders a different kind of item.
  List<Track> _searchTracks = const [];
  List<Album> _searchAlbums = const [];
  List<Artist> _searchArtists = const [];
  List<Playlist> _searchPlaylists = const [];

  // ---- Home ----------------------------------------------------------------

  bool _homeLoading = false;
  List<Track> _homeHot = const [];
  List<Album> _homeRecent = const [];
  List<Album> _homeAlbums = const [];
  List<Artist> _homeArtists = const [];
  List<Playlist> _homePlaylists = const [];
  List<Track> _homeFavorites = const [];
  bool _homeLoaded = false;
  int _homeRun = 0;

  String _homeQuery = '';
  bool _homeSearching = false;
  SearchAll _homeSearch = const SearchAll.empty();

  List<Track> _queue = const [];
  int _queueIndex = -1;

  int _page = 0;
  int _total = 0;
  static const _pageSize = 120;

  Lyrics? _lyrics;
  bool _lyricsLoading = false;
  int _lyricsRun = 0;
  bool _lyricsVisible = false;
  bool _nowPlaying = false;

  // ---- Cast ---------------------------------------------------------------

  CastService? _castService;
  List<CastDevice> _castDevices = const [];
  bool _castScanning = false;
  bool _castScanDone = false;
  CastDevice? _castDevice;
  CastSession? _castSession;
  StreamSubscription<SessionState>? _castStateSub;
  StreamSubscription<double>? _castVolumeSub;
  double _castVolume = 1.0;

  Future<void>? _loadTask;
  bool _completedGuard = false;
  bool _booting = true;
  bool _disposed = false;

  /// How many tracks in a row we silently stepped over because the server
  /// could not hand them over. Reset as soon as something plays.
  int _failedSkips = 0;
  static const _maxFailedSkips = 6;

  // ---- Getters ------------------------------------------------------------

  MusicFreeSession? get session => _session;
  bool get connecting => _connecting;
  String? get error => _error;
  ServerInfo? get serverInfo => _serverInfo;
  bool get probingServer => _probingServer;
  List<Uri> get serverAddresses => _session?.allAddresses ?? const [];
  ServerInfo? addressStatus(Uri address) =>
      _addressStatuses[address.toString()];
  Section get section => _section;
  Detail? get detail => _detail;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  List<Track> get tracks => _tracks;
  List<Album> get albums => _albums;
  List<Artist> get artists => _artists;
  List<Playlist> get playlists => _playlists;
  List<Track> get favorites => _favorites;
  String get query => _query;
  bool get searching => _searching;
  List<Track> get searchResults => _searchTracks;
  List<Album> get searchAlbums => _searchAlbums;
  List<Artist> get searchArtists => _searchArtists;
  List<Playlist> get searchPlaylists => _searchPlaylists;

  // ---- Home ----------------------------------------------------------------

  bool get homeLoading => _homeLoading;
  List<Track> get homeHotTracks => _homeHot;
  List<Album> get homeRecentAlbums => _homeRecent;
  List<Album> get homeAlbums => _homeAlbums;
  List<Artist> get homeArtists => _homeArtists;
  List<Playlist> get homePlaylists => _homePlaylists;
  List<Track> get homeFavorites => _homeFavorites;

  String get homeQuery => _homeQuery;
  bool get homeSearching => _homeSearching;
  SearchAll get homeSearch => _homeSearch;
  List<Track> get queue => _queue;
  int get queueIndex => _queueIndex;
  Lyrics? get lyrics => _lyrics;
  bool get lyricsLoading => _lyricsLoading;
  bool get lyricsVisible => _lyricsVisible;

  /// The full-window player opened by tapping the cover in the transport.
  bool get nowPlayingVisible => _nowPlaying;

  // ---- Cast ---------------------------------------------------------------

  /// Renderers found by the latest scan.
  List<CastDevice> get castDevices => _castDevices;

  /// True while an SSDP scan is running.
  bool get castScanning => _castScanning;

  /// True once a scan finished (successfully or not), so the picker can show
  /// "nothing found" instead of an endless spinner.
  bool get castScanDone => _castScanDone;

  /// The renderer playback is currently pushed to, if any.
  CastDevice? get castDevice => _castDevice;

  /// True while audio is being cast — local playback is parked.
  bool get casting => _castSession != null;

  /// Remote transport state, null when not casting.
  SessionState? get castState => _castSession?.state;

  /// The live session, for UI that follows the renderer's position stream.
  CastSession? get castSession => _castSession;

  double get castVolume => _castVolume;

  bool get signedIn => _session != null;

  /// True until the saved session has been read, so the first frame does not
  /// flash the login page at a returning user.
  bool get booting => _booting;

  bool get canLoadMore {
    if (_searching || _detail != null || _loading || _loadingMore) return false;
    return switch (_section) {
      Section.home => false,
      Section.tracks => _tracks.length < _total,
      Section.albums => _albums.length < _total,
      Section.artists => _artists.length < _total,
      _ => false,
    };
  }

  String get headerTitle {
    if (_searching) return '搜索 “$_query”';
    if (_detail != null) return _detail!.title;
    return _section.label;
  }

  String get headerSubtitle {
    if (_searching) return '$_searchCount 个结果';
    if (_detail != null) return _detail!.subtitle;
    if (_section == Section.tracks) {
      return '${_tracks.length} / 共 $_total 首';
    }
    return _section.subtitle;
  }

  int get _searchCount => switch (_section) {
    Section.albums => _searchAlbums.length,
    Section.artists => _searchArtists.length,
    Section.playlists => _searchPlaylists.length,
    Section.home => 0,
    _ => _searchTracks.length,
  };

  List<Track> get visibleTracks => switch (true) {
    _ when _searching => _searchTracks,
    _ when _detail != null => _detail!.tracks,
    _ when _section == Section.favorites => _favorites,
    _ => _tracks,
  };

  List<Album> get visibleAlbums => _searching ? _searchAlbums : _albums;

  List<Artist> get visibleArtists => _searching ? _searchArtists : _artists;

  List<Playlist> get visiblePlaylists =>
      _searching ? _searchPlaylists : _playlists;

  Track? get currentTrack {
    if (_queueIndex < 0 || _queueIndex >= _queue.length) return null;
    return _queue[_queueIndex];
  }

  /// [size] is the pixel width requested from the server; list thumbnails use
  /// a small one so scrolling a long library does not pull full-size art.
  String? coverUrl(String? coverId, {int size = 320}) =>
      client.coverUrl(coverId, size: size);

  // ---- Session ------------------------------------------------------------

  Future<void> restoreSession() async {
    // Restore the relay entry-token before probing addresses so a saved
    // session reached through Fn Connect keeps answering on the subdomain,
    // and the fnOS session token for unified-gateway (`/app/<name>`) links.
    // Tolerant: the tokens are optimizations, never a gate for restore.
    try {
      await loadLastEntryToken();
      await loadLastFnosToken();
    } catch (_) {}
    final saved = await _store.load();
    if (saved == null) {
      _booting = false;
      notifyListeners();
      return;
    }
    client.restore(saved);
    _session = saved;
    _booting = false;
    notifyListeners();
    _startAddressProbe();
    await select(Section.home);
  }

  Future<void> login(String rawUrl, String username, String password) async {
    if (_connecting) return;
    if (username.trim().isEmpty || password.isEmpty) {
      _error = '请填写账号和密码';
      notifyListeners();
      return;
    }
    _connecting = true;
    _error = null;
    notifyListeners();
    try {
      final active = await client.login(rawUrl, username, password);
      await _store.save(active);
      _session = active;
      _startAddressProbe();
      await select(Section.home);
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '连接失败：$failure';
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _teardownCast(restoreLocal: false);
    await player.stop();
    client.forget();
    await _store.clear();
    _session = null;
    _detail = null;
    _detailTrail.clear();
    _tracks = const [];
    _albums = const [];
    _artists = const [];
    _playlists = const [];
    _favorites = const [];
    _clearSearchResults();
    _queue = const [];
    _queueIndex = -1;
    _section = Section.home;
    _lyrics = null;
    _lyricsVisible = false;
    _nowPlaying = false;
    _homeLoaded = false;
    _homeHot = const [];
    _homeRecent = const [];
    _homeAlbums = const [];
    _homeArtists = const [];
    _homePlaylists = const [];
    _homeFavorites = const [];
    _homeQuery = '';
    _homeSearching = false;
    _homeSearch = const SearchAll.empty();
    _serverInfo = null;
    _stopAddressProbe();
    notifyListeners();
  }

  /// Settings-page probe: latency and server identity. Never surfaces as a
  /// global error — the page renders offline state and offers a retry.
  Future<void> refreshServerInfo() async {
    if (_probingServer || _session == null) return;
    _probingServer = true;
    notifyListeners();
    final info = await client.serverInfo();
    if (_disposed) return;
    _serverInfo = info;
    _probingServer = false;
    notifyListeners();
  }

  /// Re-point the app at another server (or the same one with fresh
  /// credentials): drop everything, then sign in again. On failure the user
  /// lands on the login page with the error shown there.
  Future<void> switchServer(
    String rawUrl,
    String username,
    String password,
  ) async {
    await logout();
    await login(rawUrl, username, password);
  }

  // ---- Fn Connect two-step sign-in ------------------------------------------

  /// Result of the NAS connect step (step 1): the probed endpoints of the
  /// Music Free backend behind the FNID. Null until [prepareFnConnect]
  /// succeeds; consumed by [loginFnPrepared].
  FnProbeResult? _fnProbe;

  /// Set when the NAS rejected the first sign-in because the account has
  /// two-step verification enabled — the login page then reveals the 2FA
  /// code field, which is hidden otherwise.
  bool _fnTwoFaRequired = false;

  bool get fnTwoFaRequired => _fnTwoFaRequired;

  /// True when direct links (LAN / public IPs) are unreachable and the FNID
  /// flow needs an fnOS sign-in before gateway / relay links can be probed.
  bool _fnNasRequired = false;
  bool get fnNasRequired => _fnNasRequired;

  /// True when the current probe result was reached through an fnOS sign-in
  /// (gateway / relay links); false for pure direct links.
  bool _fnViaNas = false;
  bool get fnViaNas => _fnViaNas;

  bool get fnPrepared => _fnProbe?.best != null;
  FnProbeResult? get fnProbe => _fnProbe;

  /// Clears the step-1 result so the login page goes back to the NAS form.
  void resetFnConnect() {
    if (_fnProbe == null && !_fnTwoFaRequired && !_fnNasRequired) return;
    _fnProbe = null;
    _fnTwoFaRequired = false;
    _fnNasRequired = false;
    _fnViaNas = false;
    _error = null;
    notifyListeners();
  }

  /// Step 1 of the Fn Connect sign-in: resolve the FNID and probe for the
  /// Music Free backend on [backendPort]. Direct links (LAN / public IPs
  /// straight to the port) are tried first and need no fnOS credentials —
  /// like the official Feiniu music app, where the app account alone is
  /// enough. Only when every direct link is unreachable are the fnOS
  /// gateway / relay subdomains probed, which require an fnOS sign-in
  /// ([nasUsername]/[nasPassword]); in that case [fnNasRequired] flips true
  /// so the login page reveals the NAS form.
  ///
  /// The outcome is stored in [fnProbe]; sign-in itself happens in step 2
  /// ([loginFnPrepared]).
  ///
  /// [nasTwoFaCode] is only needed when the NAS account has two-step
  /// verification enabled; without it the call fails with a message asking
  /// for the code (fill the field and retry).
  Future<void> prepareFnConnect({
    required String fnId,
    String? nasUsername,
    String? nasPassword,
    String? nasTwoFaCode,
    required String backendPort,
  }) async {
    if (_connecting) return;
    _connecting = true;
    _error = null;
    _fnProbe = null;
    _fnTwoFaRequired = false;
    notifyListeners();
    try {
      final port = int.tryParse(backendPort.trim()) ?? 14533;
      final params = await resolveFnId(fnId);
      // Remember the ID even if the step later fails, so the field prefills.
      unawaited(saveLastFnId(fnId));

      // Direct links first: no fnOS session, no tokens — just the backend
      // answering on its own port. This covers the common LAN case and any
      // setup with a public IP / forwarded port.
      final directProbe = await probeFnCandidates(
        buildFnCandidates(params, port).where((c) => !c.relay).toList(),
      );
      if (directProbe.best != null) {
        _fnNasRequired = false;
        _fnViaNas = false;
        _fnProbe = directProbe;
        unawaited(saveLastFnPort(port));
        return;
      }

      // Nothing reachable directly: remote access must ride the fnOS unified
      // gateway or the relay subdomains, and both require an fnOS session.
      final username = nasUsername?.trim() ?? '';
      final password = nasPassword ?? '';
      if (username.isEmpty || password.isEmpty) {
        _fnNasRequired = true;
        notifyListeners();
        return;
      }
      _fnNasRequired = true;
      _fnViaNas = true;

      // Sign in to fnOS over its WebSocket protocol and mint the relay
      // gateway entry-token — without it every app subdomain answers 403.
      final relayHost = params.relayDomains.isEmpty
          ? null
          : params.relayDomains.first;
      if (relayHost == null) {
        throw FnConnectException('FNID 已解析但设备没有中继域名');
      }
      // A stable device ID makes the NAS remember this app as a trusted
      // device after one 2FA verify — later sign-ins skip the code prompt.
      final did = await loadOrCreateFnDid();
      final fnos = FnOsClient(did: did);
      try {
        await fnos.connect('wss://${relayHost.replaceFirst(RegExp(r':\d+$'), '')}/websocket?type=main');
        try {
          await fnos.login(username, password);
        } on FnOsTwoFaRequired {
          // The server itself says this account needs 2FA — flip the flag so
          // the login page reveals the code field, then ask the user to retry
          // with the code filled (a fresh connection is made on the retry).
          if (nasTwoFaCode == null || nasTwoFaCode.trim().isEmpty) {
            _fnTwoFaRequired = true;
            throw FnConnectException('该账号已开启两步验证，请输入 6 位动态验证码后重试');
          }
          await fnos.submitTwoFa(nasTwoFaCode);
        }
        // The unified gateway (device domain `/app/<name>`) authorizes with
        // the fnOS session token from the login response; persist it so
        // gateway links keep working after a restart.
        final fnosToken = fnos.fnosToken;
        if (fnosToken != null && fnosToken.isNotEmpty) {
          fnGatewayToken = fnosToken;
          unawaited(saveLastFnosToken(fnosToken));
        }
        final entryToken = await fnos.exchangeEntryToken();
        unawaited(saveLastEntryToken(entryToken));
        fnRelayEntryToken = entryToken;
        // App relay subdomains (musicfree.<fnId>.fnos.net) — the broker's
        // device domain only fronts fnOS's own web UI.
        final entries = await fnos.listAppEntries();
        final appDomains = [
          for (final entry in entries)
            if (entry.fnDomain.isNotEmpty) '${entry.fnDomain}.${fnId.trim()}.fnos.net',
        ];
        final probe = await probeFnCandidates(
          buildFnCandidates(params, port, extraRelayDomains: appDomains),
        );
        if (probe.best == null) {
          throw MusicFreeException(
            '未找到可达的链路（内网 / 公网 / 网关 / 中继均已探测），'
            '请确认 NAS 在线且 Music Free 服务已在端口 $port 启动',
          );
        }
        _fnProbe = probe;
        unawaited(saveLastFnPort(port));
      } finally {
        await fnos.close();
      }
    } on FnConnectException catch (failure) {
      _error = failure.message;
    } on FnOsException catch (failure) {
      _error = failure.message;
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '连接失败：$failure';
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Step 2 of the Fn Connect sign-in: sign in to the Music Free backend
  /// through the endpoint probed in step 1. Every other reachable endpoint
  /// is registered as a backup address so the regular failover prober can
  /// hop between LAN / WAN / relay automatically afterwards.
  Future<void> loginFnPrepared({
    required String username,
    required String password,
  }) async {
    final probe = _fnProbe;
    final best = probe?.best;
    if (best == null) {
      _error = '请先完成 FNID 连接探测';
      notifyListeners();
      return;
    }
    if (_connecting) return;
    if (username.trim().isEmpty || password.isEmpty) {
      _error = '请填写 Music Free 账号和密码';
      notifyListeners();
      return;
    }
    _connecting = true;
    _error = null;
    notifyListeners();
    try {
      final active = await client.login(best.toString(), username, password);
      final others = probe!.reachable.where((address) => address != best).toList();
      final session = others.isEmpty
          ? active
          : active.copyWith(addresses: [active.baseUrl, ...others]);
      client.restore(session);
      await _store.save(session);
      _session = session;
      _startAddressProbe();
      await select(Section.home);
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '登录失败：$failure';
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  // ---- Multi-address failover ----------------------------------------------

  /// Probes every configured address on a slow cycle and promotes the best
  /// reachable one. Among reachable addresses the lowest latency wins, which
  /// effectively prefers the LAN endpoint whenever both LAN and WAN are up
  /// (a LAN round trip is always far quicker than a WAN one). The cadence is
  /// deliberately relaxed — this is failover, not a heartbeat.
  void _startAddressProbe() {
    _addressTimer?.cancel();
    if (_session == null) return;
    unawaited(_probeAddresses());
    _addressTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_probeAddresses());
    });
  }

  /// Addresses a manual "probe now" is currently running for (settings page).
  final Set<Uri> _manualProbing = {};

  bool isProbingAddress(Uri address) => _manualProbing.contains(address);

  /// Immediate single-address probe, triggered from the settings page's
  /// per-address probe button. Updates that address's status in place (the
  /// row repaints as soon as the result lands) and re-runs the promotion
  /// logic so a fresh result can still switch the active address.
  Future<void> probeAddressNow(Uri address) async {
    if (!_manualProbing.add(address)) return;
    notifyListeners();
    try {
      final info = await client.pingAddress(address);
      if (_disposed) return;
      _addressStatuses[address.toString()] = info;
      notifyListeners();
      final session = _session;
      if (session != null) {
        _promoteBestAddress(session, session.allAddresses, [
          for (final a in session.allAddresses)
            _addressStatuses[a.toString()] ?? const ServerInfo(online: false),
        ]);
      }
    } finally {
      _manualProbing.remove(address);
      notifyListeners();
    }
  }

  void _stopAddressProbe() {
    _addressTimer?.cancel();
    _addressTimer = null;
    _addressStatuses = {};
  }

  Future<void> _probeAddresses() async {
    final session = _session;
    if (session == null || _probingAddresses || _disposed) return;
    _probingAddresses = true;
    try {
      final addresses = session.allAddresses;
      final results = await Future.wait([
        for (final address in addresses) client.pingAddress(address),
      ]);
      if (_disposed) return;
      final next = <String, ServerInfo>{
        for (var i = 0; i < addresses.length; i++)
          addresses[i].toString(): results[i],
      };
      final changed = !mapEquals(next, _addressStatuses);
      _addressStatuses = next;
      _promoteBestAddress(session, addresses, results);
      if (changed || _session != session) notifyListeners();
    } finally {
      _probingAddresses = false;
    }
  }

  /// Switches away from the active address only when it is offline, or when
  /// another address is clearly faster (LAN vs WAN); the hysteresis keeps a
  /// working connection from flapping over marginal latency noise.
  void _promoteBestAddress(
    MusicFreeSession session,
    List<Uri> addresses,
    List<ServerInfo> results,
  ) {
    Uri? bestAddress;
    var bestLatency = -1;
    for (var i = 0; i < addresses.length; i++) {
      final info = results[i];
      if (!info.online) continue;
      final latency = info.latencyMs ?? 1 << 30;
      if (bestAddress == null || latency < bestLatency) {
        bestAddress = addresses[i];
        bestLatency = latency;
      }
    }
    if (bestAddress == null || bestAddress == session.baseUrl) return;
    final active = results[addresses.indexOf(session.baseUrl)];
    if (active.online) {
      final activeLatency = active.latencyMs ?? 1 << 30;
      // Only hop when the alternative is at least twice as fast with a
      // meaningful absolute margin.
      if (!(bestLatency * 2 + 20 < activeLatency)) return;
    }
    _applyAddress(bestAddress);
  }

  /// Re-points the client at [address], persists the choice and refreshes the
  /// probe state. Never re-authenticates — both endpoints share credentials.
  Future<void> useServerAddress(Uri address) async {
    final session = _session;
    if (session == null || address == session.baseUrl) return;
    if (!session.allAddresses.contains(address)) return;
    _applyAddress(address);
    unawaited(_probeAddresses());
  }

  void _applyAddress(Uri address) {
    final session = _session;
    if (session == null || address == session.baseUrl) return;
    final updated = session.copyWith(baseUrl: address);
    client.restore(updated);
    _session = updated;
    unawaited(_store.save(updated));
    debugPrint('[MusicFly] server address switched to $address');
    notifyListeners();
  }

  /// Registers an additional endpoint (e.g. the WAN URL for home use) for
  /// the signed-in server. Duplicates are ignored; returns false when the
  /// URL cannot be parsed so the dialog can show the problem inline.
  Future<bool> addServerAddress(String rawUrl) async {
    final session = _session;
    if (session == null) return false;
    final Uri address;
    try {
      address = client.normalizeAddress(rawUrl);
    } on MusicFreeException {
      return false;
    }
    if (session.allAddresses.contains(address)) return true;
    final updated = session.copyWith(
      addresses: [...session.allAddresses, address],
    );
    client.restore(updated);
    _session = updated;
    await _store.save(updated);
    notifyListeners();
    unawaited(_probeAddresses());
    return true;
  }

  /// Removes an endpoint. When the active one is removed the first remaining
  /// address takes over; the last address cannot be removed.
  Future<void> removeServerAddress(Uri address) async {
    final session = _session;
    if (session == null) return;
    final remaining = session.allAddresses
        .where((existing) => existing != address)
        .toList();
    if (remaining.isEmpty) return;
    final nextActive = session.baseUrl == address
        ? remaining.first
        : session.baseUrl;
    final updated = session.copyWith(baseUrl: nextActive, addresses: remaining);
    client.restore(updated);
    _session = updated;
    _addressStatuses.remove(address.toString());
    await _store.save(updated);
    notifyListeners();
    unawaited(_probeAddresses());
  }

  void consumeError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---- Navigation ---------------------------------------------------------

  Future<void> select(Section target) async {
    if (target == Section.home) {
      _section = target;
      _detail = null;
      _detailTrail.clear();
      _searching = false;
      _query = '';
      _clearSearchResults();
      notifyListeners();
      await loadHome();
      return;
    }
    final loaded = switch (target) {
      Section.home => _homeLoaded,
      Section.tracks => _tracks.isNotEmpty,
      Section.albums => _albums.isNotEmpty,
      Section.artists => _artists.isNotEmpty,
      Section.playlists => _playlists.isNotEmpty,
      Section.favorites => _favorites.isNotEmpty,
    };
    // Re-selecting a hydrated tab is a no-op; an empty one always reloads,
    // because login and session restore land here before any data exists.
    if (_section == target && _detail == null && !_searching && loaded) {
      return;
    }
    _section = target;
    _detail = null;
    _detailTrail.clear();
    _searching = false;
    _query = '';
    _clearSearchResults();
    _page = 0;
    _total = 0;
    _tracks = const [];
    _albums = const [];
    _artists = const [];
    notifyListeners();
    await load(initial: true);
  }

  /// Drill-downs can stack (artist page → album page), so back pops the
  /// trail before closing entirely.
  final List<Detail> _detailTrail = [];

  void _pushDetailTrail() {
    final current = _detail;
    if (current != null) _detailTrail.add(current);
  }

  void back() {
    if (_detail == null) return;
    _detail = _detailTrail.isEmpty ? null : _detailTrail.removeLast();
    notifyListeners();
  }

  void updateQuery(String value) {
    _query = value;
    notifyListeners();
  }

  /// Section-aware search: songs and albums hit the server's search3,
  /// artists too; favorites and playlists are small enough to filter in
  /// memory (the server exposes no search over them).
  Future<void> submitSearch() async {
    final text = _query.trim();
    if (text.isEmpty) {
      _searching = false;
      _clearSearchResults();
      notifyListeners();
      return;
    }
    _searching = true;
    _detail = null;
    _detailTrail.clear();
    _loading = true;
    _error = null;
    _clearSearchResults();
    notifyListeners();
    try {
      switch (_section) {
        case Section.albums:
          final all = await client.searchAll(
            text,
            songLimit: 0,
            albumLimit: 100,
            artistLimit: 0,
          );
          _searchAlbums = all.albums;
        case Section.artists:
          final all = await client.searchAll(
            text,
            songLimit: 0,
            albumLimit: 0,
            artistLimit: 100,
          );
          _searchArtists = all.artists;
        case Section.playlists:
          _searchPlaylists = _filterPlaylists(_playlists, text);
        case Section.favorites:
          _searchTracks = _filterTracks(_favorites, text);
        case Section.tracks:
          _searchTracks = await client.searchTracks(text);
        case Section.home:
          break;
      }
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '搜索失败：$failure';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  static List<Playlist> _filterPlaylists(List<Playlist> source, String text) {
    final needle = text.toLowerCase();
    return [
      for (final playlist in source)
        if (playlist.name.toLowerCase().contains(needle)) playlist,
    ];
  }

  static List<Track> _filterTracks(List<Track> source, String text) {
    final needle = text.toLowerCase();
    return [
      for (final track in source)
        if (track.title.toLowerCase().contains(needle) ||
            track.artistLine.toLowerCase().contains(needle) ||
            (track.album?.name.toLowerCase().contains(needle) ?? false))
          track,
    ];
  }

  void _clearSearchResults() {
    _searchTracks = const [];
    _searchAlbums = const [];
    _searchArtists = const [];
    _searchPlaylists = const [];
  }

  void clearSearch() {
    if (_query.isEmpty && !_searching) return;
    _query = '';
    _searching = false;
    _clearSearchResults();
    notifyListeners();
  }

  // ---- Home ----------------------------------------------------------------

  /// Loads every home card. Runs once per login unless [force] is set; each
  /// card failing alone only surfaces one message and leaves the rest intact.
  Future<void> loadHome({bool force = false}) async {
    if (_session == null || (_homeLoaded && !force) || _homeLoading) return;
    final run = ++_homeRun;
    _homeLoading = true;
    notifyListeners();
    Future<List<T>> guard<T>(Future<List<T>> task) async {
      try {
        return await task;
      } on MusicFreeException {
        return const [];
      } catch (_) {
        return const [];
      }
    }

    try {
      final results = await (
        guard(client.hotTracks(limit: 20)),
        guard(client.albumList(type: 'recent', size: 12)),
        guard(client.albums(1, 12).then((page) => page.items)),
        guard(client.artists(1, 12).then((page) => page.items)),
        guard(client.playlists()),
        guard(client.favorites()),
      ).wait;
      if (run != _homeRun) return;
      _homeHot = results.$1;
      _homeRecent = results.$2;
      _homeAlbums = results.$3;
      _homeArtists = results.$4;
      _homePlaylists = results.$5;
      _homeFavorites = results.$6;
      _homeLoaded = true;
    } finally {
      if (run == _homeRun && !_disposed) {
        _homeLoading = false;
        notifyListeners();
      }
    }
  }

  void updateHomeQuery(String value) {
    _homeQuery = value;
    notifyListeners();
  }

  /// The home page's comprehensive search: one query refreshes the song,
  /// album and artist groups together.
  Future<void> submitHomeSearch() async {
    final text = _homeQuery.trim();
    if (text.isEmpty) {
      _homeSearching = false;
      _homeSearch = const SearchAll.empty();
      notifyListeners();
      return;
    }
    _homeSearching = true;
    _homeLoading = true;
    notifyListeners();
    try {
      final result = await client.searchAll(
        text,
        songLimit: 30,
        albumLimit: 12,
        artistLimit: 12,
      );
      _homeSearch = result;
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '搜索失败：$failure';
    } finally {
      _homeLoading = false;
      notifyListeners();
    }
  }

  void clearHomeSearch() {
    if (_homeQuery.isEmpty && !_homeSearching) return;
    _homeQuery = '';
    _homeSearching = false;
    _homeSearch = const SearchAll.empty();
    notifyListeners();
  }

  // ---- Listings -----------------------------------------------------------

  Future<void> load({bool initial = false}) async {
    if (_session == null) return;
    if (_loadTask != null) return;
    if (initial) {
      _loading = true;
      _page = 0;
      _total = 0;
      notifyListeners();
    }
    _error = null;
    final task = _performLoad();
    _loadTask = task;
    try {
      await task;
    } finally {
      _loadTask = null;
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _performLoad() async {
    try {
      switch (_section) {
        case Section.home:
          // Home loads through loadHome(), not the paged loader.
          break;
        case Section.tracks:
          final result = await client.tracks(_page + 1, _pageSize);
          _total = result.total;
          _tracks = _page == 0 ? result.items : [..._tracks, ...result.items];
        case Section.albums:
          final result = await client.albums(_page + 1, _pageSize);
          _total = result.total;
          _albums = _page == 0 ? result.items : [..._albums, ...result.items];
        case Section.artists:
          final result = await client.artists(_page + 1, _pageSize);
          _total = result.total;
          _artists = _page == 0 ? result.items : [..._artists, ...result.items];
        case Section.playlists:
          _playlists = await client.playlists();
        case Section.favorites:
          _favorites = await client.favorites();
      }
      _page += 1;
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '加载失败：$failure';
    }
  }

  Future<void> loadMore() async {
    if (!canLoadMore) return;
    _loadingMore = true;
    notifyListeners();
    await load();
  }

  Future<void> openAlbum(Album album) async {
    _pushDetailTrail();
    _detail = Detail(
      title: album.name,
      subtitle: '${album.artistLine} · ${album.trackCount} 首',
      coverId: album.coverId,
      isAlbum: true,
    );
    _lyricsVisible = false;
    notifyListeners();
    try {
      final tracks = await client.albumTracks(album.id);
      _detail = _detail?.copyWith(tracks: tracks, loading: false);
    } on MusicFreeException catch (failure) {
      _detail = _detail?.copyWith(loading: false);
      _error = failure.message;
    } finally {
      notifyListeners();
    }
  }

  Future<void> openPlaylist(Playlist playlist) async {
    _pushDetailTrail();
    _detail = Detail(
      title: playlist.name,
      subtitle: '${playlist.trackCount ?? 0} 首',
      coverId: playlist.coverId,
    );
    _lyricsVisible = false;
    notifyListeners();
    try {
      final tracks = await client.playlistTracks(playlist.id);
      _detail = _detail?.copyWith(tracks: tracks, loading: false);
    } on MusicFreeException catch (failure) {
      _detail = _detail?.copyWith(loading: false);
      _error = failure.message;
    } finally {
      notifyListeners();
    }
  }

  /// The artist page mirrors the web player's: a circular avatar header and
  /// the artist's albums beneath it.
  Future<void> openArtist(Artist artist) async {
    _pushDetailTrail();
    _detail = Detail(
      title: artist.name,
      subtitle: artist.albumCount > 0 ? '${artist.albumCount} 张专辑' : '艺术家',
      coverId: artist.coverId,
      isArtist: true,
    );
    _lyricsVisible = false;
    notifyListeners();
    try {
      final page = await client.artistDetail(artist.id);
      _detail = _detail?.copyWith(
        albums: page.albums,
        loading: false,
        subtitle: '${page.albums.length} 张专辑',
      );
    } on MusicFreeException catch (failure) {
      _detail = _detail?.copyWith(loading: false);
      _error = failure.message;
    } finally {
      notifyListeners();
    }
  }

  /// Plays every track of every album on the open artist page, the way the
  /// web player's "播放全部歌曲" does.
  Future<void> playArtistAll() async {
    final detail = _detail;
    if (detail == null || !detail.isArtist || detail.albums.isEmpty) return;
    _detail = detail.copyWith(loading: true);
    notifyListeners();
    try {
      final groups = await Future.wait([
        for (final album in detail.albums) client.albumTracks(album.id),
      ]);
      final all = <Track>[for (final group in groups) ...group];
      _detail = _detail?.copyWith(loading: false);
      if (all.isEmpty) {
        _error = '这位艺术家还没有可播放的歌曲';
        notifyListeners();
        return;
      }
      await playFrom(all, 0);
    } on MusicFreeException catch (failure) {
      _detail = _detail?.copyWith(loading: false);
      _error = failure.message;
      notifyListeners();
    }
  }

  // ---- Playback -----------------------------------------------------------

  Future<void> playFrom(List<Track> list, int index) async {
    if (index < 0 || index >= list.length) return;
    _queue = List<Track>.from(list);
    _queueIndex = index;
    _failedSkips = 0;
    await _startTrack(list[index]);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_queueIndex >= _queue.length - 1) return;
    _queueIndex += 1;
    _failedSkips = 0;
    await _startTrack(_queue[_queueIndex]);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_queueIndex <= 0) return;
    _queueIndex -= 1;
    _failedSkips = 0;
    await _startTrack(_queue[_queueIndex]);
  }

  void togglePlay() {
    final session = _castSession;
    if (session != null) {
      switch (session.state) {
        case SessionState.playing:
        case SessionState.buffering:
          unawaited(session.pause());
        case SessionState.paused:
          unawaited(session.play());
        default:
          // Stopped on the renderer (or loaded but not started): re-cast the
          // current track so the play button always does something sensible.
          final track = currentTrack;
          if (track != null) unawaited(_startTrack(track));
      }
      return;
    }
    if (!player.state.value.hasTrack) {
      final list = visibleTracks;
      if (list.isNotEmpty) unawaited(playFrom(list, 0));
      return;
    }
    player.toggle();
  }

  Future<void> _startTrack(Track track) async {
    _completedGuard = false;
    _lyrics = null;
    // 用户主动开播时顺手要一次通知权限（Android 13+）：没有它，暂停后锁屏
    // 和通知栏上的播放控制器会消失。放在这里而不是启动时，避免一进 App 就弹窗。
    unawaited(MfMediaSession.ensureNotificationPermission());
    final session = _castSession;
    if (session != null) {
      await _castToSession(track, session);
      return;
    }
    try {
      // The transcoder answers with a chunked, unseekable body whose
      // duration AVPlayer cannot read — that froze the progress bar. Only
      // formats the decoders cannot handle go through it. maxBitRate alone
      // also activates the transcoder on this server, so it must be dropped
      // together with format for raw streams.
      final transcode = needsTranscode(track.format);
      final url = client.streamUrl(
        track.id,
        format: transcode ? 'mp3' : null,
        maxBitRate: transcode ? 192 : null,
      );
      final started = await player.play(
        trackId: track.id,
        title: track.title,
        subtitle: track.subtitle,
        // 鸿蒙锁屏播控面板显示的是纯歌手名，subtitle 里的专辑名带过去会乱。
        artist: track.artistLine,
        streamUrl: url,
        coverId: track.coverId,
        // 锁屏封面要的是完整地址（带 token），不是一个 coverId。
        coverUrl: client.coverUrl(track.coverId, size: 640),
        duration: Duration(
          milliseconds: (track.durationSeconds * 1000).round(),
        ),
        // The transcoder answers with a chunked body whose position the
        // engine never advances; the player then times the bar itself.
        transcoded: transcode,
      );
      if (started) _failedSkips = 0;
      notifyListeners();
      // The transport shows the current lyric line, so every track fetches its
      // lyrics up front instead of waiting for the pane to be opened.
      if (started) unawaited(loadLyrics());
    } on MusicFreeException catch (failure) {
      _error = failure.message;
      notifyListeners();
    }
  }

  /// Pushes [track] to the connected renderer. Queue navigation ([next],
  /// [previous], auto-advance) routes through [_startTrack], so casting and
  /// local playback stay one queue with one set of controls.
  Future<void> _castToSession(Track track, CastSession session) async {
    try {
      final transcode = needsTranscode(track.format);
      final url = client.streamUrl(
        track.id,
        format: transcode ? 'mp3' : null,
        maxBitRate: transcode ? 192 : null,
      );
      await session.loadMedia(
        CastMedia(
          url: url,
          // AudioDlnaSession ignores this and labels the item audio/mpeg; a
          // future Chromecast session would read it.
          type: CastMediaType.mp4,
          title: track.title,
          duration: Duration(
            milliseconds: (track.durationSeconds * 1000).round(),
          ),
        ),
      );
      notifyListeners();
      unawaited(loadLyrics());
    } catch (failure) {
      _error = '投屏失败：$failure';
      notifyListeners();
    }
  }

  /// A track the server refused to serve. Step over it when the queue has
  /// more, but stop after [_maxFailedSkips] so a dead media source does not
  /// ripple through an entire playlist.
  void _handleFailure(String trackId, String reason) {
    if (player.state.value.trackId != trackId) return;
    final hasNext = _queueIndex >= 0 && _queueIndex < _queue.length - 1;
    if (!hasNext || _failedSkips >= _maxFailedSkips) {
      _error = _failedSkips >= _maxFailedSkips
          ? '连续 $_maxFailedSkips 首无法播放，请检查媒体源或服务端'
          : reason;
      notifyListeners();
      return;
    }
    _failedSkips++;
    // Only announce the first skip: a dead media source would otherwise throw
    // a snackbar per track while it walks the queue.
    if (_failedSkips == 1) {
      _error = '《${_queue[_queueIndex].title}》$reason，正在跳过无法播放的歌曲';
    }
    _queueIndex++;
    notifyListeners();
    unawaited(_startTrack(_queue[_queueIndex]));
  }

  void _handleCompleted() {
    if (_completedGuard) return;
    _completedGuard = true;
    unawaited(next());
  }

  void setVolume(double value) {
    final session = _castSession;
    if (session != null) {
      _castVolume = value.clamp(0.0, 1.0);
      notifyListeners();
      unawaited(session.setVolume(_castVolume));
      return;
    }
    player.setVolume(value);
    notifyListeners();
  }

  double get volume => _castSession != null ? _castVolume : player.volume;

  Future<void> seek(Duration position) {
    final session = _castSession;
    if (session != null) return session.seek(position);
    return player.seek(position);
  }

  /// Stars/unstars a song. Every cached list (queue, section lists, home
  /// cards, the open detail) is patched optimistically; a failed request
  /// rolls the change back so the UI never disagrees with the server.
  Future<void> toggleFavorite(Track track) async {
    final target = !track.isFavorite;
    _applyFavorite(track.id, target, track);
    notifyListeners();
    try {
      await client.setStarred(track.id, target);
    } catch (failure) {
      if (_disposed) return;
      _applyFavorite(track.id, !target, track);
      _error = target ? '收藏失败：$failure' : '取消收藏失败：$failure';
      notifyListeners();
    }
  }

  void _applyFavorite(String id, bool fav, Track original) {
    List<Track> patchAll(List<Track> list) => [
      for (final t in list) t.id == id ? t.copyWith(isFavorite: fav) : t,
    ];
    _tracks = patchAll(_tracks);
    _searchTracks = patchAll(_searchTracks);
    _homeHot = patchAll(_homeHot);
    _homeFavorites = patchAll(_homeFavorites);
    _queue = patchAll(_queue);
    final detail = _detail;
    if (detail != null && detail.tracks.isNotEmpty) {
      _detail = detail.copyWith(
        tracks: [
          for (final t in detail.tracks)
            t.id == id ? t.copyWith(isFavorite: fav) : t,
        ],
      );
    }
    if (fav) {
      final starred = original.copyWith(isFavorite: true);
      if (!_favorites.any((t) => t.id == id)) {
        _favorites = [starred, ..._favorites];
      }
      if (!_homeFavorites.any((t) => t.id == id)) {
        _homeFavorites = [starred, ..._homeFavorites];
      }
    } else {
      _favorites = _favorites.where((t) => t.id != id).toList();
      _homeFavorites = _homeFavorites.where((t) => t.id != id).toList();
    }
  }

  // ---- Cast ---------------------------------------------------------------

  /// Scans the local network for DLNA renderers. Safe to call repeatedly —
  /// each call replaces the previous scan's results.
  Future<void> startCastScan() async {
    _castService ??= _buildCastService();
    _castScanning = true;
    _castScanDone = false;
    _castDevices = const [];
    notifyListeners();
    try {
      await for (final devices in _castService!.startDiscovery(
        timeout: const Duration(seconds: 8),
      )) {
        _castDevices = devices;
        notifyListeners();
      }
    } catch (_) {
      // Discovery runs on raw UDP; a sandbox without multicast access simply
      // finds nothing instead of being a hard failure.
    } finally {
      _castScanning = false;
      _castScanDone = true;
      notifyListeners();
    }
  }

  CastService _buildCastService() => CastService(
    discoveryProviders: [DlnaDiscoveryProvider()],
    sessionFactory:
        _castSessionFactory ??
        (device) {
          if (device.protocol == CastProtocol.dlna) {
            return AudioDlnaSession.fromDevice(device);
          }
          throw UnsupportedError(
            'Protocol ${device.protocol.name} has no session yet',
          );
        },
  );

  /// Connects to [device] and pushes the current track to it. Local playback
  /// is paused while the session lives, and resumes when the cast ends.
  Future<void> connectCast(CastDevice device) async {
    final service = _castService ??= _buildCastService();
    try {
      final session = await service.connect(device);
      _castDevice = device;
      _castSession = session;
      _castVolume = 1.0;
      _castStateSub?.cancel();
      _castVolumeSub?.cancel();
      _castStateSub = session.stateStream.listen(_onCastState);
      _castVolumeSub = session.volumeStream.listen((value) {
        _castVolume = value.clamp(0.0, 1.0);
        notifyListeners();
      });
      notifyListeners();
      final track = currentTrack;
      if (track != null) await _startTrack(track);
    } catch (failure) {
      _error = '连接「${device.name}」失败：$failure';
      notifyListeners();
    }
  }

  /// Drops the cast session and hands playback back to the local player.
  Future<void> disconnectCast() => _teardownCast(restoreLocal: true);

  Future<void> _teardownCast({required bool restoreLocal}) async {
    final session = _castSession;
    final track = currentTrack;
    // Null out first: the session's own state stream must not observe the
    // disconnect and trigger queue logic.
    _castStateSub?.cancel();
    _castStateSub = null;
    _castVolumeSub?.cancel();
    _castVolumeSub = null;
    _castSession = null;
    _castDevice = null;
    notifyListeners();
    if (session != null) {
      try {
        await session.disconnect();
      } catch (_) {}
    }
    if (restoreLocal && track != null) await _startTrack(track);
  }

  /// Renderer transport updates: playing/paused only refresh the UI, while
  /// a stop near the end of the track advances the queue, mirroring what the
  /// local player does on completion.
  void _onCastState(SessionState state) {
    if (_disposed) return;
    if (state == SessionState.idle) {
      final session = _castSession;
      final nearEnd =
          session != null &&
          session.duration > Duration.zero &&
          session.position >= session.duration - const Duration(seconds: 3);
      if (nearEnd) {
        notifyListeners();
        unawaited(next());
        return;
      }
    }
    notifyListeners();
  }

  // ---- Lyrics -------------------------------------------------------------

  void hideLyrics() {
    _lyricsVisible = false;
    notifyListeners();
  }

  // ---- Now playing --------------------------------------------------------

  /// Opens the full-window player. The lyrics pane and the player share the
  /// same fetch, so opening the player never waits on a second request.
  void openNowPlaying() {
    if (_nowPlaying) return;
    _nowPlaying = true;
    notifyListeners();
    if (_lyrics == null) unawaited(loadLyrics());
  }

  void closeNowPlaying() {
    if (!_nowPlaying) return;
    _nowPlaying = false;
    notifyListeners();
  }

  Future<void> loadLyrics() async {
    // Generation, not a loading flag: skipping two tracks quickly must not
    // swallow the fetch for the newest one; only the latest run may land.
    final run = ++_lyricsRun;
    final track = currentTrack;
    if (track == null) return;
    _lyricsLoading = true;
    notifyListeners();
    try {
      // Same endpoint the web player uses: the server reads its lyrics store
      // first, then the file tags, and reports per-line timestamps when synced.
      final lyrics = await client.structuredLyrics(track.id);
      // The user may have moved to another song while fetching.
      if (run != _lyricsRun || currentTrack?.id != track.id) return;
      _lyrics = lyrics;
    } finally {
      // The fetch may outlive the model (e.g. the app is torn down right
      // after a track change) — never notify from the grave.
      if (run == _lyricsRun && !_disposed) {
        _lyricsLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _addressTimer?.cancel();
    _castStateSub?.cancel();
    _castVolumeSub?.cancel();
    unawaited(_castService?.dispose());
    // 先解绑再销毁播放器：媒体会话的监听器挂在 player.state 上，那个
    // ValueNotifier 马上就要被 dispose 了。
    MfMediaSession.instance?.unbind();
    player.dispose();
    super.dispose();
  }
}
