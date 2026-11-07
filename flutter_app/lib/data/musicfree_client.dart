/// A read-mostly client for the Music Free REST surface.
///
/// Endpoint names and field fallbacks are kept in sync with the Kotlin client
/// (`core/network/.../musicfree/MusicFreeApi.kt`) so both clients understand the
/// same server replies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';

class MusicFreeException implements Exception {
  MusicFreeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthException extends MusicFreeException {
  AuthException(super.message);
}

class MusicFreeClient {
  MusicFreeClient({http.Client? httpClient}) : _http = httpClient ?? _defaultClient();

  final http.Client _http;
  MusicFreeSession? _session;

  MusicFreeSession? get session => _session;

  void restore(MusicFreeSession session) => _session = session;

  void forget() => _session = null;

  // ---- Session ------------------------------------------------------------

  Future<MusicFreeSession> login(
    String rawUrl,
    String username,
    String password,
  ) async {
    final base = _normalize(rawUrl);
    final root = await _post('rest/api/v1/auth/login', {
      'username': username,
      'password': password,
    }, base: base);
    final token = _string(root, ['token']);
    if (token == null || token.isEmpty) {
      throw AuthException('登录失败，请检查账号和密码');
    }
    final salt = _randomSalt();
    final session = MusicFreeSession(
      baseUrl: base,
      token: token,
      username: _string(root, ['username']) ?? username,
      subsonicToken: _string(root, ['subsonicToken']) ?? '',
      clientSalt: salt,
    );
    _session = session;
    return session;
  }

  /// A LAN server must not be routed through the system HTTP proxy: on a Mac
  /// with a proxy configured, `127.0.0.1:4533` otherwise answers from the proxy
  /// (404 / connection refused). Private hosts go direct; everything else keeps
  /// the user's proxy.
  static http.Client _defaultClient() {
    final client = HttpClient()
      ..findProxy = (uri) => _isPrivateHost(uri.host)
          ? 'DIRECT'
          : HttpClient.findProxyFromEnvironment(uri);
    return IOClient(client);
  }

  static bool _isPrivateHost(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.isLoopback) return true;
    final raw = address.rawAddress;
    if (raw.length == 4) {
      return raw[0] == 10 ||
          (raw[0] == 192 && raw[1] == 168) ||
          (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31);
    }
    return false;
  }

  Uri _normalize(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) throw MusicFreeException('请填写 Music Free 地址');
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) {
      throw MusicFreeException('地址格式不正确：$rawUrl');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw MusicFreeException('只支持 http 或 https 地址');
    }
    return parsed;
  }

  // ---- Listings -----------------------------------------------------------

  Future<Page<Track>> tracks(int page, int size) async {
    final offset = (page - 1).clamp(0, 1 << 30) * size;
    final root = await _get('rest/api/v1/songs', {
      'offset': '$offset',
      'limit': '$size',
    });
    final items = _objects(root['songs']).map(_toTrack).toList();
    return Page(items, _int(root, ['total']) ?? offset + items.length);
  }

  Future<Page<Album>> albums(int page, int size) async {
    final offset = (page - 1).clamp(0, 1 << 30) * size;
    final root = await _get('rest/api/v1/albums', {
      'offset': '$offset',
      'limit': '$size',
    });
    final items = _objects(root['albums']).map(_toAlbum).toList();
    return Page(items, _int(root, ['total']) ?? offset + items.length);
  }

  Future<Page<Artist>> artists(int page, int size) async {
    final offset = (page - 1).clamp(0, 1 << 30) * size;
    final root = await _get('rest/api/v1/artists', {
      'offset': '$offset',
      'limit': '$size',
    });
    final items = _objects(root['artists']).map(_toArtist).toList();
    return Page(items, _int(root, ['total']) ?? offset + items.length);
  }

  Future<List<Playlist>> playlists() async {
    final root = await _get('rest/api/v1/playlists');
    return _objects(root['playlists']).map(_toPlaylist).toList();
  }

  Future<List<Track>> albumTracks(String albumId) async {
    final root = await _get('rest/getAlbum.view', {'id': albumId});
    final album = _child(root, 'album');
    final songs = album != null ? _objects(album['song']) : _objects(root['song']);
    return songs.map(_toTrack).toList();
  }

  Future<List<Track>> playlistTracks(String playlistId) async {
    final root = await _get('rest/getPlaylist.view', {'id': playlistId});
    final playlist = _child(root, 'playlist');
    final entries = playlist != null
        ? _objects(playlist['entry'])
        : _objects(root['songs']);
    return entries.map(_toTrack).toList();
  }

  Future<List<Track>> favorites() async {
    final root = await _get('rest/getStarred2.view');
    final starred = _child(root, 'starred2') ?? _child(root, 'starred');
    return _objects(starred?['song']).map(_toTrack).toList();
  }

  Future<List<Track>> searchTracks(String query, {int limit = 60}) async {
    if (query.trim().isEmpty) return const [];
    final root = await _get('rest/search3.view', {
      'query': query,
      'songCount': '$limit',
      'albumCount': '0',
      'artistCount': '0',
    });
    final result = _child(root, 'searchResult3');
    final songs = result != null ? _objects(result['song']) : _objects(root['song']);
    return songs.map(_toTrack).toList();
  }

  /// The server keeps lyrics on the song row but does not list them.
  Future<Lyrics?> lyrics(String trackId) async {
    try {
      final root = await _get('rest/getSong.view', {'id': trackId});
      final song = _child(root, 'song');
      final content =
          (_text(song?['lyrics'])) ?? _text(root['lyrics']);
      if (content == null || content.trim().isEmpty) return null;
      return parseLyrics(content);
    } on MusicFreeException {
      return null;
    }
  }

  // ---- Media URLs ---------------------------------------------------------

  String streamUrl(String trackId, {String? format = 'mp3', int? maxBitRate = 192}) {
    final params = <String, String>{'id': trackId};
    if (format != null) params['format'] = format;
    if (maxBitRate != null) params['maxBitRate'] = '$maxBitRate';
    return _mediaUrl('rest/stream', params);
  }

  String? coverUrl(String? coverId, {int size = 320}) {
    if (coverId == null || coverId.isEmpty) return null;
    try {
      return _mediaUrl('rest/getCoverArt', {'id': coverId, 'size': '$size'});
    } on MusicFreeException {
      return null;
    }
  }

  String _mediaUrl(String path, Map<String, String> params) {
    final active = _session;
    if (active == null) throw AuthException('尚未登录');
    final query = <String, String>{'v': '1.16.1', 'c': 'FnMusic', ...params};
    if (active.subsonicToken.isNotEmpty) {
      query['u'] = active.username;
      query['t'] = _md5('${active.subsonicToken}${active.clientSalt}');
      query['s'] = active.clientSalt;
    }
    return _uri(active.baseUrl, path, query).toString();
  }

  // ---- Transport ----------------------------------------------------------

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> params = const {},
  ]) async {
    final active = _session;
    if (active == null) throw AuthException('尚未登录');
    final uri = _uri(active.baseUrl, path, {
      'f': 'json',
      'v': '1.16.1',
      'c': 'FnMusic',
      ...params,
    });
    return _send(() => _http.get(uri, headers: _headers()));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    Uri? base,
  }) async {
    final target = base ?? _session?.baseUrl;
    if (target == null) throw AuthException('尚未登录');
    final uri = _uri(target, path, const {});
    return _send(
      () => _http.post(
        uri,
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
  }

  Map<String, String> _headers() {
    final token = _session?.token;
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw MusicFreeException('服务器响应超时，请检查网络或地址');
    } catch (error) {
      throw MusicFreeException('无法连接服务器：$error');
    }

    final body = response.body;
    if (body.trim().isEmpty) {
      throw MusicFreeException('服务器返回 HTTP ${response.statusCode}');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw MusicFreeException('服务器返回了无法解析的内容');
    }
    if (decoded is! Map<String, dynamic>) {
      throw MusicFreeException('服务器返回了非对象内容');
    }
    return _unwrap(decoded);
  }

  /// Music Free answers both `subsonic-response` envelopes and bare objects.
  Map<String, dynamic> _unwrap(Map<String, dynamic> root) {
    final envelope = _child(root, 'subsonic-response');
    if (envelope == null) return root;
    if (_text(envelope['status']) == 'failed') {
      final error = _child(envelope, 'error');
      final message = _text(error?['message']) ?? '服务器拒绝了请求';
      final code = _int(error, ['code']) ?? 0;
      if (code == 40 || code == 41) throw AuthException(message);
      throw MusicFreeException(message);
    }
    return envelope;
  }

  Uri _uri(Uri base, String path, Map<String, String> query) {
    final segments = <String>[
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      ...path.split('/').where((segment) => segment.isNotEmpty),
    ];
    return base.replace(
      pathSegments: segments,
      queryParameters: query.isEmpty ? null : query,
    );
  }
}

// ---- JSON helpers ---------------------------------------------------------

String? _text(Object? value) {
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

String? _string(Map<String, dynamic> node, List<String> names) {
  for (final name in names) {
    final value = _text(node[name]);
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

int? _int(Map<String, dynamic>? node, List<String> names) {
  if (node == null) return null;
  for (final name in names) {
    final value = node[name];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _double(Map<String, dynamic>? node, List<String> names) {
  if (node == null) return null;
  for (final name in names) {
    final value = node[name];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

Map<String, dynamic>? _child(Map<String, dynamic>? node, String key) {
  final value = node?[key];
  return value is Map<String, dynamic> ? value : null;
}

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is List) {
    return value.whereType<Map<String, dynamic>>().toList();
  }
  return const [];
}

String _md5(String value) =>
    md5.convert(utf8.encode(value)).toString();

final _random = DateTime.now().microsecondsSinceEpoch;

/// Same shape as the Kotlin client: 8 random bytes, hex encoded.
String _randomSalt() {
  var seed = _random ^ identityHashCode(Object());
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    buffer.write((seed & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Track _toTrack(Map<String, dynamic> node) {
  final millis = _double(node, ['durationMs']);
  var duration = millis != null ? millis / 1000 : null;
  if (duration == null) {
    final seconds = _double(node, ['duration']);
    if (seconds != null) {
      // Navidrome reports seconds; Music Free /songs rows report ms.
      duration = seconds > 36000 ? seconds / 1000 : seconds;
    }
  }
  return Track(
    id: _string(node, ['id', 'guid']) ?? '',
    title: _string(node, ['title', 'name']) ?? '',
    artists: _embeddedArtists(node),
    album: _embeddedAlbum(node),
    coverId: _string(node, ['coverArt', 'coverId']) ?? _string(node, ['albumId']),
    durationSeconds: duration ?? 0,
    isFavorite: node.containsKey('starred'),
  );
}

Album _toAlbum(Map<String, dynamic> node) => Album(
  id: _string(node, ['id', 'guid']) ?? '',
  name: _string(node, ['name', 'album', 'title']) ?? '',
  artists: _embeddedArtists(node),
  coverId: _string(node, ['coverArt', 'coverId']),
  trackCount: _int(node, ['songCount', 'trackCount']) ?? 0,
);

Artist _toArtist(Map<String, dynamic> node) => Artist(
  id: _string(node, ['id', 'guid']) ?? '',
  name: _string(node, ['name', 'artist']) ?? '',
  coverId: _string(node, ['coverArt', 'coverId']),
  trackCount: _int(node, ['songCount', 'trackCount']) ?? 0,
  albumCount: _int(node, ['albumCount']) ?? 0,
);

Playlist _toPlaylist(Map<String, dynamic> node) => Playlist(
  id: _string(node, ['id', 'guid']) ?? '',
  name: _string(node, ['name', 'title']) ?? '',
  coverId: _string(node, ['coverArt', 'coverId']),
  trackCount: _int(node, ['songCount', 'trackCount']),
);

/// Rows sometimes embed the artist as an object, sometimes as a plain name.
List<Artist> _embeddedArtists(Map<String, dynamic> node) {
  final array = node['artists'];
  if (array is List) {
    final result = <Artist>[];
    for (final entry in array) {
      if (entry is! Map<String, dynamic>) continue;
      final name = _string(entry, ['name', 'artist']);
      if (name == null) continue;
      result.add(
        Artist(
          id: _string(entry, ['id', 'guid']) ?? '',
          name: name,
          coverId: _string(entry, ['coverArt']),
        ),
      );
    }
    return result;
  }
  final single = _child(node, 'artist');
  if (single != null) {
    final name = _string(single, ['name', 'artist']);
    if (name == null) return const [];
    return [
      Artist(id: _string(single, ['id', 'guid']) ?? '', name: name),
    ];
  }
  final name = _string(node, ['artist', 'artistName']);
  if (name == null) return const [];
  return [Artist(id: _string(node, ['artistId']) ?? '', name: name)];
}

Album? _embeddedAlbum(Map<String, dynamic> node) {
  final child = _child(node, 'album');
  if (child != null) {
    return Album(
      id: _string(child, ['id', 'guid']) ?? '',
      name: _string(child, ['name', 'album', 'title']) ?? '',
      coverId: _string(child, ['coverArt', 'coverId']),
      trackCount: _int(child, ['songCount', 'trackCount']) ?? 0,
    );
  }
  // Subsonic song rows flatten the album into plain attributes.
  final name = _string(node, ['album']);
  if (name == null) return null;
  return Album(
    id: _string(node, ['albumId']) ?? '',
    name: name,
    coverId: _string(node, ['coverArt', 'coverId']),
  );
}
