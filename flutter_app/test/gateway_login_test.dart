/// fnOS unified-gateway passwordless sign-in: the client calls
/// /auth/gateway-login (or /auth/gateway-bind on first use) on gateway app
/// paths, carrying the fnOS session token. Direct / relay links never use it.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:musicfly/data/fn_connect.dart';
import 'package:musicfly/data/musicfree_client.dart';

const _gatewayUrl = 'https://nas.example.com/app/musicfree/';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

MusicFreeClient _clientWith(MockClientHandler handler) =>
    MusicFreeClient(httpClient: MockClient(handler));

void main() {
  setUp(() => fnGatewayToken = 'fnos-tok');
  tearDown(() => fnGatewayToken = null);

  group('isFnGatewayPath', () {
    test('matches unified-gateway app paths only', () {
      expect(
        isFnGatewayPath('https://nas.example.com/app/musicfree/'),
        isTrue,
      );
      expect(
        isFnGatewayPath('https://192.168.1.10:5667/app/musicfree/rest/ping'),
        isTrue,
      );
      expect(isFnGatewayPath('http://192.168.1.10:14533/'), isFalse);
      expect(
        isFnGatewayPath('https://musicfree.myid.fnos.net/rest/ping'),
        isFalse,
      );
      expect(isFnGatewayPath('not a url'), isFalse);
    });
  });

  test('gatewayLogin posts with the fnOS session header and returns a session',
      () async {
    http.Request? captured;
    final client = _clientWith((request) async {
      captured = request;
      return _json({
        'token': 'jwt-1',
        'username': 'admin',
        'subsonicToken': 'stream-token',
      });
    });

    final session = await client.gatewayLogin(_gatewayUrl);

    expect(session.token, 'jwt-1');
    expect(session.username, 'admin');
    expect(session.subsonicToken, 'stream-token');
    expect(session.baseUrl.path, '/app/musicfree/');
    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(
      captured!.url.path,
      '/app/musicfree/rest/api/v1/auth/gateway-login',
    );
    expect(captured!.headers['Authorization'], 'trim fnos-tok');
    expect(captured!.headers.containsKey('X-ND-Authorization'), isFalse);
    expect(jsonDecode(captured!.body), isEmpty);
  });

  test('gatewayLogin signals a missing NAS binding', () async {
    final client = _clientWith((request) async {
      return _json({
        'error': 'NAS 账号尚未绑定 Music Free 账号',
        'needBind': true,
        'nasUsername': 'haiven',
      }, 404);
    });

    await expectLater(
      client.gatewayLogin(_gatewayUrl),
      throwsA(
        isA<GatewayBindRequiredException>().having(
          (error) => error.message,
          'message',
          contains('绑定'),
        ),
      ),
    );
  });

  test('gatewayBind verifies the app credentials once', () async {
    http.Request? captured;
    final client = _clientWith((request) async {
      captured = request;
      return _json({
        'token': 'jwt-2',
        'username': 'admin',
        'subsonicToken': 'stream-token',
      });
    });

    final session = await client.gatewayBind(_gatewayUrl, 'admin', 'secret');

    expect(session.token, 'jwt-2');
    expect(
      captured!.url.path,
      '/app/musicfree/rest/api/v1/auth/gateway-bind',
    );
    expect(captured!.headers['Authorization'], 'trim fnos-tok');
    expect(jsonDecode(captured!.body), {
      'username': 'admin',
      'password': 'secret',
    });
  });

  test('an older backend without gateway-login raises a fall-back error',
      () async {
    final client = _clientWith((request) async {
      return http.Response('404 page not found', 404);
    });

    await expectLater(
      client.gatewayLogin(_gatewayUrl),
      throwsA(isA<MusicFreeException>()),
    );
  });

  test('plain password login still works unchanged', () async {
    http.Request? captured;
    final client = _clientWith((request) async {
      captured = request;
      return _json({'token': 'jwt-3', 'username': 'admin'});
    });

    final session = await client.login(
      'http://192.168.1.10:14533',
      'admin',
      'secret',
    );

    expect(session.token, 'jwt-3');
    expect(session.username, 'admin');
    expect(captured!.url.path, '/rest/api/v1/auth/login');
    expect(captured!.headers.containsKey('Authorization'), isFalse);
  });
}
