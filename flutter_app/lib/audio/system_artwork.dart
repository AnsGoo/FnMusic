/// Cover bytes for the system media UI (HarmonyOS AVSession).
///
/// `AVMetadata.mediaImage` accepts a URI *or* an `image.PixelMap`. Handing it
/// the `rest/getCoverArt` URL means the **system service** downloads the image:
/// Fn Connect relay links need `Cookie: mode=relay; entry-token=...`, and the
/// unified gateway needs `Authorization: trim <token>`. The system has neither,
/// so the request gets a 401 and the lock screen falls back to a blank cover.
/// The in-app `CoverImage` works because it explicitly adds
/// `fnRelayHeadersFor(url)`.
///
/// Fix: download the bytes here, inside the app, with exactly those headers,
/// and hand the bytes to the native side to decode into a PixelMap. The same
/// bytes can later be reused for Android/iOS artwork without a second request.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/fn_connect.dart';

class SystemArtworkLoader {
  SystemArtworkLoader({http.Client? client, this.maxBytes = defaultMaxBytes})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Cover art is usually a few hundred KB. Refuse anything bigger so a
  /// misconfigured endpoint (an HTML error page, a full-size scan) cannot be
  /// pushed through the platform channel or decoded into a huge PixelMap.
  static const int defaultMaxBytes = 2 * 1024 * 1024;
  static const Duration requestTimeout = Duration(seconds: 8);
  static const int maxCacheEntries = 12;

  final http.Client _client;
  final bool _ownsClient;
  final int maxBytes;

  /// Insertion-ordered LRU: a hit removes and re-inserts the key.
  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _pending = <String, Future<Uint8List?>>{};

  /// Returns the encoded image bytes (jpeg/png/webp, undecoded), or null when
  /// the URL is missing or the request is not usable. Never throws.
  Future<Uint8List?> load(String? url) {
    if (url == null || url.isEmpty) return Future<Uint8List?>.value(null);
    final hit = _cache.remove(url);
    if (hit != null) {
      _cache[url] = hit;
      return Future<Uint8List?>.value(hit);
    }
    final running = _pending[url];
    if (running != null) return running;
    final future = _fetch(url);
    _pending[url] = future;
    unawaited(future.whenComplete(() => _pending.remove(url)));
    return future;
  }

  Future<Uint8List?> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    // Exactly the headers the in-app CoverImage uses. Subsonic cover URLs
    // already carry the u/t/s token in the query string, so no JWT is needed.
    final headers = fnRelayHeadersFor(url) ?? const <String, String>{};
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: headers)
            .timeout(requestTimeout);
        // 401/403/404 will not improve on retry — give up immediately.
        if (response.statusCode != 200) return null;
        final bytes = response.bodyBytes;
        if (bytes.isEmpty || bytes.length > maxBytes) return null;
        final type = response.headers['content-type'];
        if (type != null &&
            type.isNotEmpty &&
            !type.toLowerCase().startsWith('image/')) {
          return null;
        }
        _put(url, bytes);
        return _cache[url];
      } catch (_) {
        // One retry covers a dropped socket / timeout; every other failure is
        // also swallowed so a missing cover never affects playback.
      }
    }
    return null;
  }

  void _put(String url, Uint8List bytes) {
    _cache[url] = bytes;
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void dispose() {
    _cache.clear();
    _pending.clear();
    if (_ownsClient) _client.close();
  }
}
