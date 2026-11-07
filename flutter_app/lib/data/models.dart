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

class Page<T> {
  const Page(this.items, this.total);

  final List<T> items;
  final int total;
}

/// Everything needed to sign Music Free API and media requests.
class MusicFreeSession {
  const MusicFreeSession({
    required this.baseUrl,
    required this.token,
    required this.username,
    this.subsonicToken = '',
    required this.clientSalt,
  });

  final Uri baseUrl;
  final String token;
  final String username;
  final String subsonicToken;
  final String clientSalt;

  String get hostLabel {
    final defaultPort = baseUrl.scheme == 'https' ? 443 : 80;
    return baseUrl.port == defaultPort
        ? baseUrl.host
        : '${baseUrl.host}:${baseUrl.port}';
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl.toString(),
    'token': token,
    'username': username,
    'subsonicToken': subsonicToken,
    'clientSalt': clientSalt,
  };

  static MusicFreeSession? fromJson(Map<String, dynamic> json) {
    final raw = json['baseUrl'] as String?;
    final token = json['token'] as String?;
    if (raw == null || token == null || token.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    return MusicFreeSession(
      baseUrl: uri,
      token: token,
      username: (json['username'] as String?) ?? '',
      subsonicToken: (json['subsonicToken'] as String?) ?? '',
      clientSalt: (json['clientSalt'] as String?) ?? '',
    );
  }
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
