/// The single source of truth for navigation, listings and playback.
///
/// Mirrors the old desktop state machine so behaviour stays identical: an empty
/// section always reloads, one queue drives the player, and pagination is capped
/// by the server-reported total.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/player.dart';
import '../data/models.dart';
import '../data/musicfree_client.dart';
import '../data/session_store.dart';

enum Section { tracks, albums, artists, playlists, favorites }

extension SectionInfo on Section {
  String get label => switch (this) {
    Section.tracks => '歌曲库',
    Section.albums => '专辑',
    Section.artists => '艺术家',
    Section.playlists => '歌单',
    Section.favorites => '收藏',
  };

  String get subtitle => switch (this) {
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
    this.loading = true,
    this.isAlbum = false,
  });

  final String title;
  final String subtitle;
  final String? coverId;
  final List<Track> tracks;
  final bool loading;
  final bool isAlbum;

  Detail copyWith({List<Track>? tracks, bool? loading}) => Detail(
    title: title,
    subtitle: subtitle,
    coverId: coverId,
    tracks: tracks ?? this.tracks,
    loading: loading ?? this.loading,
    isAlbum: isAlbum,
  );
}

class AppModel extends ChangeNotifier {
  AppModel({MusicFreeClient? client, SessionStore? store, MfPlayer? player})
    : client = client ?? MusicFreeClient(),
      _store = store ?? SessionStore(),
      player = player ?? MfPlayer() {
    this.player.onCompleted = _handleCompleted;
    this.player.onFailed = _handleFailure;
  }

  final MusicFreeClient client;
  final MfPlayer player;
  final SessionStore _store;

  MusicFreeSession? _session;
  bool _connecting = false;
  String? _error;

  Section _section = Section.tracks;
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
  List<Track> _searchResults = const [];

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

  Future<void>? _loadTask;
  bool _completedGuard = false;
  bool _booting = true;

  /// How many tracks in a row we silently stepped over because the server
  /// could not hand them over. Reset as soon as something plays.
  int _failedSkips = 0;
  static const _maxFailedSkips = 6;

  // ---- Getters ------------------------------------------------------------

  MusicFreeSession? get session => _session;
  bool get connecting => _connecting;
  String? get error => _error;
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
  List<Track> get searchResults => _searchResults;
  List<Track> get queue => _queue;
  int get queueIndex => _queueIndex;
  Lyrics? get lyrics => _lyrics;
  bool get lyricsLoading => _lyricsLoading;
  bool get lyricsVisible => _lyricsVisible;

  /// The full-window player opened by tapping the cover in the transport.
  bool get nowPlayingVisible => _nowPlaying;

  bool get signedIn => _session != null;

  /// True until the saved session has been read, so the first frame does not
  /// flash the login page at a returning user.
  bool get booting => _booting;

  bool get canLoadMore {
    if (_searching || _detail != null || _loading || _loadingMore) return false;
    return switch (_section) {
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
    if (_searching) return '${_searchResults.length} 个结果';
    if (_detail != null) return _detail!.subtitle;
    if (_section == Section.tracks) {
      return '${_tracks.length} / 共 $_total 首';
    }
    return _section.subtitle;
  }

  List<Track> get visibleTracks => switch (true) {
    _ when _searching => _searchResults,
    _ when _detail != null => _detail!.tracks,
    _ when _section == Section.favorites => _favorites,
    _ => _tracks,
  };

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
    await select(Section.tracks);
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
      await select(Section.tracks);
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
    await player.stop();
    client.forget();
    await _store.clear();
    _session = null;
    _detail = null;
    _tracks = const [];
    _albums = const [];
    _artists = const [];
    _playlists = const [];
    _favorites = const [];
    _searchResults = const [];
    _queue = const [];
    _queueIndex = -1;
    _section = Section.tracks;
    _lyrics = null;
    _lyricsVisible = false;
    _nowPlaying = false;
    notifyListeners();
  }

  void consumeError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---- Navigation ---------------------------------------------------------

  Future<void> select(Section target) async {
    final loaded = switch (target) {
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
    _searching = false;
    _query = '';
    _searchResults = const [];
    _page = 0;
    _total = 0;
    _tracks = const [];
    _albums = const [];
    _artists = const [];
    notifyListeners();
    await load(initial: true);
  }

  void back() {
    if (_detail == null) return;
    _detail = null;
    notifyListeners();
  }

  void updateQuery(String value) {
    _query = value;
    notifyListeners();
  }

  Future<void> submitSearch() async {
    final text = _query.trim();
    if (text.isEmpty) {
      _searching = false;
      _searchResults = const [];
      notifyListeners();
      return;
    }
    _searching = true;
    _detail = null;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _searchResults = await client.searchTracks(text);
    } on MusicFreeException catch (failure) {
      _error = failure.message;
    } catch (failure) {
      _error = '搜索失败：$failure';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    if (_query.isEmpty && !_searching) return;
    _query = '';
    _searching = false;
    _searchResults = const [];
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

  /// Artists have no dedicated page on this backend, so tapping one searches
  /// the library for that name.
  Future<void> openArtist(Artist artist) async {
    _query = artist.name;
    await submitSearch();
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
        streamUrl: url,
        coverId: track.coverId,
        duration: Duration(
          milliseconds: (track.durationSeconds * 1000).round(),
        ),
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
    player.setVolume(value);
    notifyListeners();
  }

  double get volume => player.volume;

  Future<void> seek(Duration position) => player.seek(position);

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
      if (run == _lyricsRun) {
        _lyricsLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
