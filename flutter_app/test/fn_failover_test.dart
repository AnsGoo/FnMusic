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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicfly/audio/player.dart';
import 'package:musicfly/data/fn_connect.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';
import 'package:musicfly/state/app_model.dart';

final _lan = Uri.parse('http://192.168.1.10:14533/');
final _wan = Uri.parse('https://1.2.3.4:14533/');

class _SilentPlayer extends MfPlayer {}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

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
      client.onTransportFailure = () async {
        fired++;
        return false;
      };

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
      client.onTransportFailure = () async {
        fired++;
        return false;
      };

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
      client.onTransportFailure = () async {
        fired++;
        return false;
      };

      final page = await client.tracks(1, 10);
      expect(page.items, isEmpty);
      expect(fired, 0);
    });
  });

  group('request replay after recovery', () {
    test('replays once on the endpoint the host switched to', () async {
      final seen = <Uri>[];
      var attempt = 0;
      final client = _clientWith((request) async {
        seen.add(request.url);
        if (attempt++ == 0) throw http.ClientException('LAN gone');
        return _json({'songs': [], 'total': 0});
      });
      client.onTransportFailure = () async {
        client.useAddress(_wan);
        return true;
      };

      final page = await client.tracks(1, 10);

      expect(page.items, isEmpty);
      expect(seen.length, 2);
      expect(seen.first.host, _lan.host);
      expect(seen.last.host, _wan.host);
    });

    test('gives up after one replay when every address stays down', () async {
      var fired = 0;
      var attempts = 0;
      final client = _clientWith((_) async {
        attempts++;
        throw http.ClientException('offline');
      });
      client.onTransportFailure = () async {
        fired++;
        return false;
      };

      await expectLater(
        client.tracks(1, 10),
        throwsA(isA<TransportException>()),
      );
      expect(fired, 1);
      expect(attempts, 1);
    });
  });

  group('expired credentials are not unreachable addresses', () {
    test('401 asks the host to renew the session, then replays', () async {
      var attempts = 0;
      var authCallbacks = 0;
      var transportCallbacks = 0;
      final client = _clientWith((_) async {
        if (attempts++ == 0) return _json({'error': 'expired'}, 401);
        return _json({'songs': [], 'total': 0});
      });
      client.onAuthFailure = () async {
        authCallbacks++;
        // Stands in for the host installing a freshly minted session.
        client.restore(_session());
        return true;
      };
      client.onTransportFailure = () async {
        transportCallbacks++;
        return false;
      };

      final page = await client.tracks(1, 10);

      expect(page.items, isEmpty);
      expect(authCallbacks, 1);
      expect(transportCallbacks, 0);
    });

    test('a failed renewal surfaces AuthException without an address sweep',
        () async {
      final client = _clientWith(
        (_) async => _json({'error': 'expired'}, 401),
      );
      client.onAuthFailure = () async => false;
      var swept = 0;
      client.onTransportFailure = () async {
        swept++;
        return false;
      };

      await expectLater(client.tracks(1, 10), throwsA(isA<AuthException>()));
      expect(swept, 0);
    });

    test('pingAddress marks a 401 as authRequired', () async {
      final client = _clientWith(
        (_) async => _json({'error': 'expired'}, 401),
      );
      final info = await client.pingAddress(_lan);
      expect(info.online, isFalse);
      expect(info.authRequired, isTrue);
    });

    test('pingAddress marks Subsonic code 40 as authRequired', () async {
      final client = _clientWith(
        (_) async => _json({
          'subsonic-response': {
            'status': 'failed',
            'error': {'code': 40, 'message': 'Wrong username or password'},
          },
        }),
      );
      final info = await client.pingAddress(_lan);
      expect(info.online, isFalse);
      expect(info.authRequired, isTrue);
    });

    test('a socket failure stays a reachability problem', () async {
      final client = _clientWith(
        (_) async => throw http.ClientException('offline'),
      );
      final info = await client.pingAddress(_lan);
      expect(info.online, isFalse);
      expect(info.authRequired, isFalse);
    });

    test('a sign-in 401 keeps the backend message', () async {
      final client = MusicFreeClient(
        httpClient: MockClient(
          (_) async => _json({'error': '账号或密码错误'}, 401),
        ),
      );

      await expectLater(
        client.login('http://192.168.1.10:14533', 'admin', 'bad'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            '账号或密码错误',
          ),
        ),
      );
    });

    test('a silent gateway re-login does not present the expired JWT',
        () async {
      Map<String, String> headers = {};
      final client = _clientWith((request) async {
        headers = request.headers;
        return _json({'token': 'fresh-jwt', 'username': 'admin'});
      });
      fnGatewayToken = 'fnos-token';
      addTearDown(() => fnGatewayToken = null);

      final fresh = await client.gatewayLogin(
        'https://myid.fnos.net/app/musicfree/',
        anonymous: true,
      );

      expect(fresh.token, 'fresh-jwt');
      expect(headers['Authorization'], 'trim fnos-token');
      expect(headers['X-ND-Authorization'], isNull);
      expect(headers['Authorization'], isNot(contains('jwt')));
    });
  });

  group('offline loop and re-login fallback', () {
    test('keeps probing, then opens the sign-in gate, and auto-recovers',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var online = false;
      SharedPreferences.setMockInitialValues({
        'musicfly.session.v1': jsonEncode(_session().toJson()),
      });
      final client = MusicFreeClient(
        httpClient: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          if (request.url.path.endsWith('ping.view')) {
            return _json({
              'subsonic-response': {'status': 'ok', 'version': '1.16.1'},
            });
          }
          return _json({'songs': [], 'total': 0});
        }),
      );
      final model = AppModel(client: client, player: _SilentPlayer());
      addTearDown(model.dispose);

      await model.restoreSession();
      for (var i = 0; i < 3; i++) {
        await model.probeAddressesNow();
      }
      expect(model.reloginRequired, isTrue);
      expect(model.reloginReason, contains('不可达'));

      // The background loop keeps sweeping: a network recovery clears the
      // gate without asking the user to sign in again.
      online = true;
      await model.probeAddressesNow();
      expect(model.reloginRequired, isFalse);
    });
  });
}

MusicFreeSession _session() => MusicFreeSession(
  baseUrl: _lan,
  token: 'jwt',
  username: 'admin',
  clientSalt: 'salt',
  addresses: [_lan, _wan],
);
