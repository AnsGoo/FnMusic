/// LAN/WAN failover for Fn Connect sign-ins.
///
/// The regression this guards against: a LAN sign-in used to persist only the
/// addresses that answered *right now*, so once the phone left home there was
/// no WAN / gateway / relay address to switch to.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:musicfly/data/fn_connect.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';

final _lan = Uri.parse('http://192.168.1.10:14533/');

MusicFreeClient _clientWith(MockClientHandler handler) =>
    MusicFreeClient(httpClient: MockClient(handler))
      ..restore(MusicFreeSession(
        baseUrl: _lan,
        token: 'jwt',
        username: 'admin',
        clientSalt: 'salt',
      ));

void main() {
  setUp(() {
    fnGatewayToken = null;
    fnRelayEntryToken = null;
  });

  group('buildAddressPool', () {
    test('pins the active address and keeps every FN link in priority order',
        () {
      final pool = buildAddressPool(_lan, [
        _lan, // duplicate of the active address
        Uri.parse('https://1.2.3.4:14533/'),
        Uri.parse('https://myid.5ddd.com/app/musicfree/'),
        Uri.parse('https://musicfree.myid.fnos.net/'),
      ]);

      expect(pool.first, _lan);
      expect(pool.length, 4);
      expect(
        pool.map((uri) => uri.toString()).toList(),
        [
          'http://192.168.1.10:14533/',
          'https://1.2.3.4:14533/',
          'https://myid.5ddd.com/app/musicfree/',
          'https://musicfree.myid.fnos.net/',
        ],
      );
    });

    test('falls back to a single address when FN offered none', () {
      expect(buildAddressPool(_lan, const <Uri>[]), [_lan]);
    });
  });

  group('probeFnCandidates', () {
    test('reports reachable links but retains the full candidate pool',
        () async {
      final candidates = buildFnCandidates(
        const FnConnectionParams(
          internalIPv4s: ['192.168.1.10'],
          publicIPv4s: ['1.2.3.4'],
          publicIPv6s: [],
          relayDomains: ['myid.5ddd.com:443'],
        ),
        14533,
      );
      // Only the LAN HTTP endpoint answers; everything else is "offline"
      // from the current network — exactly the home-WiFi situation.
      final result = await probeFnCandidates(
        candidates,
        httpClient: MockClient((request) async {
          // The LAN gateway shares the same host/scheme on port 5666 — only
          // the direct backend port should answer here.
          if (request.url.host == '192.168.1.10' &&
              request.url.scheme == 'http' &&
              request.url.port == 14533) {
            return http.Response('{}', 200);
          }
          return http.Response('{}', 404);
        }),
      );

      expect(result.best, _lan);
      expect(result.reachable, [_lan]);
      expect(result.candidates.length, candidates.length);
      final strings = result.candidates.map((uri) => uri.toString()).toList();
      expect(strings, contains('https://1.2.3.4:14533/'));
      expect(strings, contains('https://myid.5ddd.com/app/musicfree/'));
      expect(strings, contains('https://myid.5ddd.com/'));

      // What actually gets persisted into the session: the WAN links survive.
      final pool = buildAddressPool(result.best!, result.candidates);
      expect(pool.length, result.candidates.length);
      expect(
        pool.map((uri) => uri.toString()),
        contains('https://myid.5ddd.com/app/musicfree/'),
      );
    });

    test('FnProbeResult defaults to an empty candidate list', () {
      const empty = FnProbeResult(best: null, reachable: []);
      expect(empty.candidates, isEmpty);
    });
  });

  group('onTransportFailure', () {
    test('a socket error asks the host to re-probe immediately', () async {
      var fired = 0;
      final client = _clientWith(
        (_) async => throw http.ClientException('offline'),
      );
      client.onTransportFailure = () => fired++;

      await expectLater(
        client.tracks(1, 10),
        throwsA(isA<MusicFreeException>()),
      );
      expect(fired, 1);
    });

    test('an HTML login page also counts as a dead address', () async {
      var fired = 0;
      final client = _clientWith(
        (_) async => http.Response('<html>sign in</html>', 200),
      );
      client.onTransportFailure = () => fired++;

      await expectLater(
        client.tracks(1, 10),
        throwsA(isA<MusicFreeException>()),
      );
      expect(fired, 1);
    });

    test('a normal API reply never triggers a failover sweep', () async {
      var fired = 0;
      final client = _clientWith(
        (_) async => http.Response(
          jsonEncode({'songs': [], 'total': 0}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      client.onTransportFailure = () => fired++;

      final page = await client.tracks(1, 10);
      expect(page.items, isEmpty);
      expect(fired, 0);
    });
  });
}
