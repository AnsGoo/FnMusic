/// Domain models shared by every screen.
///
/// These mirror the Kotlin models one-for-one so the Music Free REST surface
/// behaves the same way it does on Android and the old desktop build.
library;

class Track {
  const Track({
    required this.id,
    required this.title,
    this.artists = const [],
    this.album,
    this.coverId,
    this.durationSeconds = 0,
    this.isFavorite = false,
    this.format,
  });

  final String id;
  final String title;
  final List<Artist> artists;
  final Album? album;
  final String? coverId;
  final double durationSeconds;
  final bool isFavorite;

  /// File container/suffix from the server ("mp3", "flac", "wma", …), used to
  /// decide whether the player can take the raw file or needs a transcode.
  final String? format;

  Track copyWith({bool? isFavorite}) => Track(
    id: id,
    title: title,
    artists: artists,
    album: album,
    coverId: coverId,
    durationSeconds: durationSeconds,
    isFavorite: isFavorite ?? this.isFavorite,
    format: format,
  );

  String get artistLine =>
      artists.isEmpty ? '未知艺术家' : artists.map((a) => a.name).join(' / ');

  /// "artist · album", the second line under a title.
  String get subtitle {
    final albumName = album?.name;
    if (albumName == null || albumName.isEmpty) return artistLine;
    return '$artistLine · $albumName';
  }

  String get durationLabel => formatDuration(durationSeconds);
}

class Album {
  const Album({
    required this.id,
    required this.name,
    this.artists = const [],
    this.coverId,
    this.trackCount = 0,
  });

  final String id;
  final String name;
  final List<Artist> artists;
  final String? coverId;
  final int trackCount;

  String get artistLine =>
      artists.isEmpty ? '未知艺术家' : artists.map((a) => a.name).join(' / ');
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.coverId,
    this.trackCount = 0,
    this.albumCount = 0,
  });

  final String id;
  final String name;
  final String? coverId;
  final int trackCount;
  final int albumCount;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.coverId,
    this.trackCount,
  });

  final String id;
  final String name;
  final String? coverId;
  final int? trackCount;
}

/// An artist drill-down: the artist plus the albums attributed to them.
class ArtistPage {
  const ArtistPage({required this.artist, required this.albums});

  final Artist artist;
  final List<Album> albums;
}

class Page<T> {
  const Page(this.items, this.total);

  final List<T> items;
  final int total;
}

/// The three result groups of a comprehensive search (search3 in one call).
class SearchAll {
  const SearchAll({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });

  const SearchAll.empty()
    : tracks = const [],
      albums = const [],
      artists = const [];

  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Everything needed to sign Music Free API and media requests.
class MusicFreeSession {
  const MusicFreeSession({
    required this.baseUrl,
    required this.token,
    required this.username,
    this.subsonicToken = '',
    required this.clientSalt,
    this.addresses = const [],
    this.fnConnect = false,
  });

  /// The address every request currently goes to. One of [addresses] —
  /// the address prober promotes it automatically (LAN preferred).
  final Uri baseUrl;
  final String token;
  final String username;
  final String subsonicToken;
  final String clientSalt;

  /// Every address the failover prober may hop to. May be empty for sessions
  /// persisted before multi-address support; [baseUrl] always stands in for
  /// it then.
  ///
  /// For [fnConnect] sessions this is the **internal** pool of links reported
  /// by the Feiniu broker — never user input, and never shown in settings.
  final List<Uri> addresses;

  /// True when the session was established through FNID. The address pool is
  /// then owned by the app (LAN / WAN / gateway / relay auto-switching), so the
  /// settings page exposes only the active endpoint and refuses edits. An
  /// ordinary login keeps [addresses] as a user-managed backup list.
  final bool fnConnect;

  /// Full address list: [addresses] when present, else just [baseUrl].
  List<Uri> get allAddresses => addresses.isEmpty ? <Uri>[baseUrl] : addresses;

  /// Addresses the user is allowed to see and manage. A FNID session hides
  /// its pool entirely — those links are an implementation detail.
  List<Uri> get visibleAddresses =>
      fnConnect ? <Uri>[baseUrl] : allAddresses;

  MusicFreeSession copyWith({
    Uri? baseUrl,
    List<Uri>? addresses,
    bool? fnConnect,
  }) => MusicFreeSession(
    baseUrl: baseUrl ?? this.baseUrl,
    token: token,
    username: username,
    subsonicToken: subsonicToken,
    clientSalt: clientSalt,
    addresses: addresses ?? this.addresses,
    fnConnect: fnConnect ?? this.fnConnect,
  );

  String get hostLabel {
    final defaultPort = baseUrl.scheme == 'https' ? 443 : 80;
    return baseUrl.port == defaultPort
        ? baseUrl.host
        : '${baseUrl.host}:${baseUrl.port}';
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl.toString(),
    'addresses': [
      for (final address in allAddresses)
        if (address != baseUrl) address.toString(),
    ],
    'token': token,
    'username': username,
    'subsonicToken': subsonicToken,
    'clientSalt': clientSalt,
    'fnConnect': fnConnect,
  };

  static MusicFreeSession? fromJson(Map<String, dynamic> json) {
    final raw = json['baseUrl'] as String?;
    final token = json['token'] as String?;
    if (raw == null || token == null || token.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final extras = <Uri>[];
    for (final entry in (json['addresses'] as List<dynamic>?) ?? const []) {
      final parsed = Uri.tryParse('$entry');
      if (parsed != null && parsed.host.isNotEmpty && parsed != uri) {
        extras.add(parsed);
      }
    }
    final addresses = <Uri>[uri, ...extras];
    return MusicFreeSession(
      baseUrl: uri,
      token: token,
      username: (json['username'] as String?) ?? '',
      subsonicToken: (json['subsonicToken'] as String?) ?? '',
      clientSalt: (json['clientSalt'] as String?) ?? '',
      addresses: addresses,
      // Sessions saved by builds predating the flag carried the full FN pool
      // in `addresses`; recognize that shape so an upgrade (or a hot reload
      // of an in-memory legacy session) does not suddenly expose the links.
      fnConnect:
          (json['fnConnect'] as bool?) ?? looksLikeFnAddressPool(addresses),
    );
  }
}

/// Recognizes a legacy FNID address pool: a `/app/<name>` gateway link mixed
/// with plain IP endpoints. A hand-maintained backup list never looks like
/// this, so ordinary logins keep their editable addresses after an upgrade.
bool looksLikeFnAddressPool(List<Uri> addresses) {
  if (addresses.length < 3) return false;
  final hasGateway = addresses.any((uri) => uri.path.startsWith('/app/'));
  final hasIpLink = addresses.any((uri) {
    if (uri.path.isNotEmpty && uri.path != '/') return false;
    return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host);
  });
  return hasGateway && hasIpLink;
}

/// The app's own version, shown on the settings page. Keep in sync with
/// `version:` in pubspec.yaml (package_info_plus is deliberately not a
/// dependency for this one string).
const String kAppVersion = '1.0.0';

/// Result of probing the server for the settings page: reachability plus
/// whatever identity the Subsonic ping reports.
class ServerInfo {
  const ServerInfo({
    required this.online,
    this.latencyMs,
    this.serverType,
    this.serverVersion,
    this.subsonicVersion,
    this.openSubsonic = false,
    this.authRequired = false,
  });

  final bool online;
  final int? latencyMs;
  final String? serverType;
  final String? serverVersion;
  final String? subsonicVersion;
  final bool openSubsonic;

  /// The endpoint answered but rejected our credentials (401 / Subsonic
  /// code 40-41). That is *not* an unreachable address: probing other links
  /// cannot fix it, only a fresh sign-in can. Keeping the two cases apart is
  /// what lets an expired day-old JWT go straight to re-login instead of
  /// being retried as a dead network forever.
  final bool authRequired;
}

class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({required this.lines, this.plain, this.raw = ''});

  final List<LyricLine> lines;

  /// Present when the server stores plain, untimed text.
  final String? plain;

  /// The server's original LRC text. The lyric widget parses this itself so it
  /// can keep word-level timing (QRC/YRC) and translations the parsed lines
  /// above deliberately drop.
  final String raw;

  bool get isTimed => lines.isNotEmpty;

  /// Index of the line that should be highlighted at [position].
  int indexAt(Duration position) {
    if (lines.isEmpty) return -1;
    var current = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        current = i;
      } else {
        break;
      }
    }
    return current;
  }
}

/// Parses LRC text (`[mm:ss.xx]line`). Untimed text comes back as [Lyrics.plain].
Lyrics parseLyrics(String raw) {
  final pattern = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];
  var hasTimestamps = false;

  for (final source in raw.split(RegExp(r'\r?\n'))) {
    final matches = pattern.allMatches(source).toList();
    if (matches.isEmpty) continue;
    hasTimestamps = true;
    final text = source.substring(matches.last.end).trim();
    if (text.isEmpty) continue;
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fractionText = match.group(3) ?? '0';
      // `[mm:ss.5]` is half a second, `[mm:ss.50]` is a half too, `[mm:ss.500]` ms.
      final fraction = fractionText.length == 3
          ? int.parse(fractionText)
          : int.parse(fractionText.padRight(2, '0')) * 10;
      lines.add(
        LyricLine(
          Duration(milliseconds: minutes * 60000 + seconds * 1000 + fraction),
          text,
        ),
      );
    }
  }

  if (!hasTimestamps) {
    final plain = raw.trim();
    return Lyrics(
      lines: const [],
      plain: plain.isEmpty ? null : plain,
      raw: raw,
    );
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return Lyrics(lines: lines, raw: raw);
}

/// `325.4` -> `5:25`, `3700` -> `1:01:40`. Zero and junk read `0:00`, which is
/// what the transport wants before a stream reports its length.
String formatClock(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '0:00';
  final total = seconds.floor();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final rest = total % 60;
  final pad = rest.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$pad'
      : '$minutes:$pad';
}

/// List rows keep a placeholder for songs whose length the server never sent.
String formatDuration(double seconds) =>
    seconds.isFinite && seconds > 0 ? formatClock(seconds) : '--:--';
