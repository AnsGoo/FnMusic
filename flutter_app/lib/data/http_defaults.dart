/// Network defaults applied to every HttpClient the app creates.
///
/// Music Free usually lives on localhost or the LAN, and desktop systems
/// export a proxy that plain Dart sockets cannot tunnel through — cover art
/// and audio then fail even though the API works. Loopback and RFC1918
/// addresses therefore always bypass the proxy.
library;

import 'dart:io';

/// True for localhost, `.local` mDNS names and private IPv4 ranges.
bool isPrivateHost(String host) {
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

/// Proxy string for [uri]: direct for LAN, environment otherwise.
String proxyFor(Uri uri) =>
    isPrivateHost(uri.host) ? 'DIRECT' : HttpClient.findProxyFromEnvironment(uri);

/// Installs the rule on `HttpOverrides.global`, so image loading, audio
/// players and anything else opening a socket follow it too.
class LocalNetworkDirect extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = proxyFor;
    return client;
  }
}
