/// Fn Connect (飞牛快连) integration.
///
/// Lets the user type a FNID instead of a server URL. The FNID is resolved
/// through Feiniu's connection broker into candidate endpoints (NAS LAN IPs,
/// public IPv4/IPv6 and relay domains), which are probed for a reachable
/// Music Free backend; the winner becomes the login address and **every**
/// candidate is registered in the session's failover pool — including links
/// that are unreachable from the current network, so leaving the LAN can hop
/// to a WAN / gateway / relay link instead of losing the connection.
///
/// The broker endpoint and the `authx` signing scheme are the same ones the
/// Feiniu clients use (reverse engineered, see XDORG-N1/FnMusic).
///
/// Relay addresses (hosts under `.5ddd.com`) additionally carry a
/// `Cookie: mode=relay` on every request — audio streams and cover art
/// included — mirroring how the Feiniu music app tags relayed traffic.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_defaults.dart';

/// Host suffixes served by the Feiniu relay; requests there need the relay
/// cookie so the gateway recognizes the traffic. Older deployments use
/// `*.5ddd.com`, newer ones (and the broker's `fn` field today) use
/// `*.fnos.net`.
const List<String> kFnRelayHostSuffixes = ['.5ddd.com', '.fnos.net'];

/// True when [host] is a Feiniu relay endpoint.
bool isFnRelayHost(String host) {
  final h = host.toLowerCase();
  for (final suffix in kFnRelayHostSuffixes) {
    if (h.endsWith(suffix)) return true;
  }
  return false;
}

/// Cookie header for requests routed through the Feiniu relay.
const Map<String, String> kFnRelayCookie = {'Cookie': 'mode=relay'};

/// The relay gateway authorizes app-subdomain traffic with the `entry-token`
/// cookie issued by the fnOS session (see `FnOsClient.exchangeEntryToken`);
/// `mode=relay` alone only works for the device's own web UI.
String? _relayEntryToken;

/// Currently cached relay entry-token, or null before the first fnOS sign-in.
String? get fnRelayEntryToken => _relayEntryToken;

set fnRelayEntryToken(String? token) {
  _relayEntryToken = (token == null || token.isEmpty) ? null : token;
}

/// fnOS session token used by the unified gateway for `/app/<name>` paths
/// (`Authorization: trim <token>`). Captured from the fnOS WebSocket login
/// response; also persisted so gateway links keep working after a restart.
String? _fnGatewayToken;

String? get fnGatewayToken => _fnGatewayToken;

set fnGatewayToken(String? token) {
  _fnGatewayToken = (token == null || token.isEmpty) ? null : token;
}

/// True when [url] is a fnOS unified-gateway app path (`/app/<name>/...`).
///
/// Only these requests reach the backend through its Unix socket, where the
/// gateway has already validated the NAS session and injected the trusted
/// `X-Trim-*` identity headers — the precondition for passwordless login.
/// Direct TCP and relay subdomain links are not gateway paths.
bool isFnGatewayPath(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.path.startsWith('/app/');
}

/// Relay-ready headers for [url], or null when the URL is not relayed.
///
/// Two kinds of Feiniu links exist:
/// - relay subdomains (`<app>.<fnid>.fnos.net`): authorized by the
///   `entry-token` cookie;
/// - unified-gateway app paths (`https://<nas-domain>/app/<name>/...`):
///   authorized by the fnOS session token via `Authorization: trim <token>`
///   (see [fnGatewayToken]). When [bearerToken] is given it rides in
///   `X-ND-Authorization` (Navidrome-style, supported by the Music Free
///   backend) because the gateway owns `Authorization`.
Map<String, String>? fnRelayHeadersFor(String url, {String? bearerToken}) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '' ;
  if (isFnGatewayPath(url) && _fnGatewayToken != null) {
    return {
      'Authorization': 'trim $_fnGatewayToken',
      if (bearerToken != null && bearerToken.isNotEmpty)
        'X-ND-Authorization': 'Bearer $bearerToken',
    };
  }
  if (!isFnRelayHost(host)) return null;
  final entry = _relayEntryToken;
  return {
    'Cookie': entry == null
        ? 'mode=relay'
        : 'mode=relay; entry-token=$entry',
  };
}

class FnConnectException implements Exception {
  FnConnectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Connection parameters returned by the Feiniu broker for a FNID.
///
/// Shape: `{"ddns":null,"ipv4":["192.168.1.10"],"publicIpv4":["1.2.3.4"],
/// "publicIpv6":["2409:..."],"fn":["myid.5ddd.com:443"],
/// "port":{"httpsPort":5667,"httpPort":5666}}`. The reported ports belong to
/// the Feiniu web portal and are reused for unified-gateway candidates
/// (`/app/<name>` paths live on the same web listener); the Music Free
/// backend port itself is supplied by the caller.
class FnConnectionParams {
  const FnConnectionParams({
    required this.internalIPv4s,
    required this.publicIPv4s,
    required this.publicIPv6s,
    required this.relayDomains,
    this.httpsPort,
    this.httpPort,
  });

  final List<String> internalIPv4s;
  final List<String> publicIPv4s;
  final List<String> publicIPv6s;

  /// Relay hostnames (host or host:port). Port is dropped when building
  /// candidates: our backend's relay domain always serves HTTPS on 443.
  final List<String> relayDomains;

  /// fnOS web portal ports from the broker's `port` map (fnOS gateway
  /// listeners); null when the broker did not report them.
  final int? httpsPort;
  final int? httpPort;

  factory FnConnectionParams.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>?)?.whereType<String>().toList() ??
        const <String>[];
    final ports = json['port'];
    int? port(String key) =>
        ports is Map<String, dynamic> ? ports[key] as int? : null;

    return FnConnectionParams(
      internalIPv4s: strings('ipv4'),
      publicIPv4s: strings('publicIpv4'),
      publicIPv6s: strings('publicIpv6'),
      relayDomains: strings('fn'),
      httpsPort: port('httpsPort'),
      httpPort: port('httpPort'),
    );
  }
}

/// Broker endpoint (Feiniu connection dispatch).
const String kFnApiPath = '/api/v1/fn/con';
const String kFnApiUrl = 'https://5ddd.com$kFnApiPath';

// Signing constants extracted from the Feiniu client (see XDORG-N1/FnMusic).
const String _authxPrefix = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
const String _authxApiKey = 'zIGtkc3dqZnJpd29qZXJqa2w7c';

String _md5(String input) => crypto.md5.convert(utf8.encode(input)).toString();

/// Builds the broker's `authx` header.
///
/// `raw = PREFIX + path + nonce + timestamp + md5(payload) + apiKey`,
/// `sign = md5(raw)`. [nonce]/[timestampMs] are injectable for tests; POST
/// payloads are JSON-encoded, matching how the broker reads them.
String computeAuthx(
  String method,
  String path,
  String payload, {
  String? nonce,
  int? timestampMs,
}) {
  final n = nonce ?? _randomNonce();
  final ts = (timestampMs ?? DateTime.now().millisecondsSinceEpoch).toString();
  final raw = [_authxPrefix, path, n, ts, _md5(payload), _authxApiKey].join('_');
  return 'nonce=$n&timestamp=$ts&sign=${_md5(raw)}';
}

String _randomNonce() =>
    (Random().nextInt(900000) + 100000).toString().padLeft(6, '0');

/// Resolves [fnId] through the Feiniu broker.
///
/// Throws [FnConnectException] when the broker rejects the ID or the network
/// fails; both carry user-presentable Chinese messages.
Future<FnConnectionParams> resolveFnId(String fnId, {http.Client? httpClient}) async {
  final trimmed = fnId.trim();
  if (trimmed.isEmpty) {
    throw FnConnectException('请填写 FNID');
  }
  final client =
      httpClient ?? IOClient(HttpClient()..findProxy = proxyFor);
  final body = jsonEncode({'fnId': trimmed});
  try {
    final response = await client
        .post(
          Uri.parse(kFnApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'authx': computeAuthx('post', kFnApiPath, body),
          },
          body: body,
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw FnConnectException('FNID 解析服务返回 HTTP ${response.statusCode}');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw FnConnectException('FNID 解析服务返回了无法解析的内容');
    }
    if (decoded is! Map<String, dynamic>) {
      throw FnConnectException('FNID 解析服务返回了非对象内容');
    }
    final code = decoded['code'];
    if (code is num && code != 0) {
      final msg = decoded['msg'];
      throw FnConnectException(
        msg is String && msg.isNotEmpty ? msg : 'FNID 查询失败，请检查输入',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw FnConnectException('FNID 查询失败，请检查输入');
    }
    final params = FnConnectionParams.fromJson(data);
    if (params.internalIPv4s.isEmpty &&
        params.publicIPv4s.isEmpty &&
        params.publicIPv6s.isEmpty &&
        params.relayDomains.isEmpty) {
      throw FnConnectException('FNID 已解析但没有任何可用链路，请确认设备在线');
    }
    return params;
  } on FnConnectException {
    rethrow;
  } on TimeoutException {
    throw FnConnectException('FNID 解析超时，请检查网络');
  } on http.ClientException catch (error) {
    throw FnConnectException('无法连接 FNID 解析服务：${error.message}');
  } catch (error) {
    throw FnConnectException('FNID 解析失败：$error');
  } finally {
    httpClient ?? client.close();
  }
}

/// One probed endpoint.
class FnCandidate {
  const FnCandidate({required this.address, required this.label, this.relay = false});

  final Uri address;

  /// Human-readable description (shown in error summaries).
  final String label;

  final bool relay;
}

/// Port the Music Free backend listens on for direct FNID links.
///
/// Fixed at 14533 — the FNID form has no port field. Gateway / relay
/// candidates use the fnOS web portal ports reported by the broker instead.
const int kDefaultBackendPort = 14533;

/// The app name registered on the fnOS unified gateway (`/app/<name>`).
const String kFnGatewayApp = 'musicfree';

/// Builds ordered probe candidates for a backend listening on [backendPort]
/// (the FNID flow always passes [kDefaultBackendPort] = 14533).
///
/// Priority mirrors the Feiniu client: LAN IPv4 → public IPv6 → public IPv4 →
/// LAN gateway → NAS-domain gateway → relay subdomains. IP candidates try HTTP
/// first (self-signed certificates on the NAS commonly break native TLS), then
/// HTTPS. Gateway candidates target the fnOS unified gateway
/// (`/app/[gatewayApp]` on the web portal ports / NAS device domain) and are
/// authorized with the fnOS session token; relay candidates always serve
/// HTTPS, are usually entered manually (a Docker app's remote domain) or taken
/// from the broker's `fn` field, and use the entry-token cookie.
List<FnCandidate> buildFnCandidates(
  FnConnectionParams params,
  int backendPort, {
  List<String> extraRelayDomains = const [],
  String gatewayApp = kFnGatewayApp,
}) {
  final candidates = <FnCandidate>[];
  final seen = <String>{};

  void addUri(Uri uri, String label, {bool relay = false}) {
    if (seen.add(uri.toString())) {
      candidates.add(FnCandidate(address: uri, label: label, relay: relay));
    }
  }

  void addIp(String host, String label, {bool ipv6 = false}) {
    final hostPart = ipv6 ? '[$host]' : host;
    addUri(
      Uri(scheme: 'http', host: host, port: backendPort, path: '/'),
      'HTTP ($hostPart:$backendPort)',
    );
    addUri(
      Uri(scheme: 'https', host: host, port: backendPort, path: '/'),
      'HTTPS ($hostPart:$backendPort)',
    );
  }

  for (final ip in params.internalIPv4s) {
    addIp(ip, ip, ipv6: ip.contains(':'));
  }
  for (final ip in params.publicIPv6s) {
    addIp(ip, ip, ipv6: true);
  }
  for (final ip in params.publicIPv4s) {
    addIp(ip, ip);
  }

  // Unified-gateway candidates. The trailing slash matters: the probe appends
  // `rest/ping.view` to the base path. LAN gateway first (fast, but the
  // portal's self-signed certificate may break native TLS), then the NAS
  // device domain (works from anywhere, session-token authorized).
  final gatewayPath = '/app/$gatewayApp/';
  for (final ip in params.internalIPv4s) {
    final hostPart = ip.contains(':') ? '[$ip]' : ip;
    addUri(
      Uri(
        scheme: 'https',
        host: ip,
        port: params.httpsPort ?? 5667,
        path: gatewayPath,
      ),
      'Gateway HTTPS ($hostPart)',
      relay: true,
    );
    addUri(
      Uri(
        scheme: 'http',
        host: ip,
        port: params.httpPort ?? 5666,
        path: gatewayPath,
      ),
      'Gateway HTTP ($hostPart)',
      relay: true,
    );
  }
  final deviceDomain = params.relayDomains.isEmpty
      ? null
      : params.relayDomains.first.trim().replaceFirst(RegExp(r':\d+$'), '');
  if (deviceDomain != null && deviceDomain.isNotEmpty) {
    addUri(
      Uri(scheme: 'https', host: deviceDomain, port: 443, path: gatewayPath),
      'Gateway ($deviceDomain)',
      relay: true,
    );
  }

  // Relay subdomains last (per-app remote domains, entry-token cookie). The
  // broker's device domain is kept for completeness; probes reject it unless
  // it actually fronts a Music Free backend.
  final relayDomains = [
    ...extraRelayDomains,
    ...params.relayDomains,
  ];
  for (final raw in relayDomains) {
    final host = raw.trim().replaceFirst(RegExp(r':\d+$'), '');
    if (host.isEmpty) continue;
    addUri(
      Uri(scheme: 'https', host: host, port: 443, path: '/'),
      'HTTPS ($host)',
      relay: true,
    );
  }

  return candidates;
}

/// Outcome of probing every candidate.
class FnProbeResult {
  const FnProbeResult({
    required this.best,
    required this.reachable,
    this.candidates = const [],
  });

  /// Highest-priority reachable address; null when everything failed.
  final Uri? best;

  /// Reachable addresses in candidate order (shown as "N links found" on the
  /// login page). This is a snapshot of the *current* network only.
  final List<Uri> reachable;

  /// All endpoints that were probed, in priority order. Unlike [reachable]
  /// these are kept even when offline right now — see [buildAddressPool].
  final List<Uri> candidates;
}

/// Builds the session's failover pool after a Fn Connect sign-in.
///
/// [active] is pinned first; every link FN reported follows in FN's priority
/// order. Keeping the currently-unreachable ones is the whole point: the
/// prober can only switch to an address it knows about, and a WAN / gateway /
/// link that fails from inside the LAN often becomes the only working one
/// once the device leaves the house.
List<Uri> buildAddressPool(Uri active, Iterable<Uri> fnCandidates) {
  final pool = <Uri>[active];
  for (final candidate in fnCandidates) {
    if (!pool.contains(candidate)) pool.add(candidate);
  }
  return pool;
}

/// Probes [candidates] concurrently (direct links 3 s, relay 10 s) and ranks
/// the survivors by candidate priority.
///
/// A candidate counts as reachable when it answers the Music Free ping with
/// HTTP 200 and parseable JSON — that rejects Feiniu's gateway pages (HTML)
/// and anything else that is not our backend.
Future<FnProbeResult> probeFnCandidates(
  List<FnCandidate> candidates, {
  http.Client? httpClient,
}) async {
  final client =
      httpClient ?? IOClient(HttpClient()..findProxy = proxyFor);
  try {
    final results = await Future.wait([
      for (final candidate in candidates) _probeOne(client, candidate),
    ]);

    Uri? best;
    final reachable = <Uri>[];
    final failures = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      if (results[i]) {
        reachable.add(candidates[i].address);
        best ??= candidates[i].address;
      } else {
        failures.add(candidates[i].label);
      }
    }
    return FnProbeResult(
      best: best,
      reachable: reachable,
      candidates: [for (final candidate in candidates) candidate.address],
    );
  } finally {
    httpClient ?? client.close();
  }
}

Future<bool> _probeOne(http.Client client, FnCandidate candidate) async {
  final timeout = candidate.relay
      ? const Duration(seconds: 10)
      : const Duration(seconds: 3);
  final uri = candidate.address.replace(
    path: '${candidate.address.path}rest/ping.view',
    queryParameters: const {'f': 'json', 'v': '1.16.1', 'c': 'MusicFly'},
  );
  try {
    final response = await client
        .get(uri, headers: fnRelayHeadersFor(uri.toString()))
        .timeout(timeout);
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>;
  } catch (_) {
    return false;
  }
}

/// Remembers the last successfully resolved FNID so the login page can
/// prefill it (kept across logout, like the Feiniu client does).
const String _lastFnIdKey = 'musicfly.fnid';

Future<String?> loadLastFnId() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_lastFnIdKey);
  return (value == null || value.isEmpty) ? null : value;
}

Future<void> saveLastFnId(String fnId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastFnIdKey, fnId.trim());
}

/// Remembers the relay entry-token issued for the current fnOS session so
/// playback/cover requests keep working after the app restarts (a fresh one
/// is minted on every FnConnect sign-in).
const String _lastEntryTokenKey = 'musicfly.fn.entryToken';

Future<void> saveLastEntryToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastEntryTokenKey, token);
  fnRelayEntryToken = token;
}

/// Restores the cached entry-token into the module state; call once at app
/// startup. Returns the restored token (null when there is none).
Future<String?> loadLastEntryToken() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_lastEntryTokenKey);
  fnRelayEntryToken = value;
  return (value == null || value.isEmpty) ? null : value;
}

/// Remembers the fnOS session token for unified-gateway links
/// (`/app/<name>` paths) across restarts; captured on every FnConnect
/// sign-in (a fresh one is issued on each NAS login).
const String _lastFnosTokenKey = 'musicfly.fn.fnosToken';

Future<void> saveLastFnosToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastFnosTokenKey, token);
  fnGatewayToken = token;
}

/// Restores the cached fnOS session token into the module state; call once
/// at app startup. Returns the restored token (null when there is none).
Future<String?> loadLastFnosToken() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_lastFnosTokenKey);
  fnGatewayToken = value;
  return (value == null || value.isEmpty) ? null : value;
}

/// Remembered fnOS account for the current FNID. Persisted (plaintext, in the
/// app's private store) so the app can silently re-establish the fnOS session
/// and refresh the gateway / relay tokens when the device changes networks or
/// the cached token expires — that is what makes FNID switch LAN↔WAN without
/// the user re-entering anything.
const String _fnosUserKey = 'musicfly.fn.nasUser';
const String _fnosPassKey = 'musicfly.fn.nasPass';

class FnOsCredentials {
  const FnOsCredentials(this.username, this.password);

  final String username;
  final String password;
}

Future<void> saveFnOsCredentials(String username, String password) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_fnosUserKey, username.trim());
  await prefs.setString(_fnosPassKey, password);
}

Future<FnOsCredentials?> loadFnOsCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  final user = prefs.getString(_fnosUserKey);
  final pass = prefs.getString(_fnosPassKey);
  if (user == null || user.isEmpty || pass == null) return null;
  return FnOsCredentials(user, pass);
}

/// Drops the remembered fnOS account (e.g. on a full reset).
Future<void> clearFnOsCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_fnosUserKey);
  await prefs.remove(_fnosPassKey);
}
