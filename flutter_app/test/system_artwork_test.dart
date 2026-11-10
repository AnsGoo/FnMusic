/// The lock-screen cover must be fetched with the same private headers the
/// in-app CoverImage uses. The system AVSession service cannot supply them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:musicfly/audio/system_artwork.dart';
import 'package:musicfly/data/fn_connect.dart';

void main() {
  const relayUrl = 'https://music-demo.5ddd.com/rest/getCoverArt?id=x';
  const gatewayUrl = 'https://nas.example.com/app/music/rest/getCoverArt?id=x';

  http.Response image([List<int> bytes = const [1, 2, 3]]) => http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/jpeg'},
      );

  setUp(() {
    fnRelayEntryToken = null;
    fnGatewayToken = null;
  });

  tearDown(() {
    fnRelayEntryToken = null;
    fnGatewayToken = null;
  });

  test('relay links carry the entry-token cookie', () async {
    fnRelayEntryToken = 'entry-42';
    http.Request? captured;
    final loader = SystemArtworkLoader(
      client: MockClient((request) async {
        captured = request;
        return image();
      }),
    );
    addTearDown(loader.dispose);

    expect(await loader.load(relayUrl), orderedEquals(<int>[1, 2, 3]));
    expect(captured!.headers['Cookie'], 'mode=relay; entry-token=entry-42');
  });

  test('unified-gateway links carry the trim token', () async {
    fnGatewayToken = 'gw-42';
    http.Request? captured;
    final loader = SystemArtworkLoader(
      client: MockClient((request) async {
        captured = request;
        return image();
      }),
    );
    addTearDown(loader.dispose);

    expect(await loader.load(gatewayUrl), isNotNull);
    expect(captured!.headers['Authorization'], 'trim gw-42');
  });

  test('a successful fetch is cached', () async {
    var requests = 0;
    final loader = SystemArtworkLoader(
      client: MockClient((_) async {
        requests++;
        return image();
      }),
    );
    addTearDown(loader.dispose);

    expect(await loader.load('https://lan.local/cover?id=1'), isNotNull);
    expect(await loader.load('https://lan.local/cover?id=1'), isNotNull);
    expect(requests, 1);
  });

  test('concurrent loads share one request', () async {
    var requests = 0;
    final loader = SystemArtworkLoader(
      client: MockClient((_) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return image();
      }),
    );
    addTearDown(loader.dispose);

    final both = await Future.wait([
      loader.load('https://lan.local/cover?id=2'),
      loader.load('https://lan.local/cover?id=2'),
    ]);
    expect(both.first, isNotNull);
    expect(both.last, isNotNull);
    expect(requests, 1);
  });

  test('rejects unusable responses instead of throwing', () async {
    final cases = <http.Response>[
      http.Response('forbidden', 401),
      http.Response.bytes(const [1, 2], 200,
          headers: {'content-type': 'text/html'}),
      http.Response.bytes(const [], 200,
          headers: {'content-type': 'image/jpeg'}),
    ];
    for (final response in cases) {
      final loader = SystemArtworkLoader(
        client: MockClient((_) async => response),
      );
      expect(await loader.load('https://lan.local/cover'), isNull);
      loader.dispose();
    }
  });

  test('refuses oversized bodies', () async {
    final loader = SystemArtworkLoader(
      maxBytes: 4,
      client: MockClient((_) async => image([1, 2, 3, 4, 5])),
    );
    addTearDown(loader.dispose);

    expect(await loader.load('https://lan.local/cover'), isNull);
  });

  test('network failures are swallowed after one retry', () async {
    var requests = 0;
    final loader = SystemArtworkLoader(
      client: MockClient((_) async {
        requests++;
        throw const HttpExceptionStub();
      }),
    );
    addTearDown(loader.dispose);

    expect(await loader.load('https://lan.local/cover'), isNull);
    expect(requests, 2);
  });

  test('null, empty and malformed URLs never hit the network', () async {
    var requests = 0;
    final loader = SystemArtworkLoader(
      client: MockClient((_) async {
        requests++;
        return image();
      }),
    );
    addTearDown(loader.dispose);

    expect(await loader.load(null), isNull);
    expect(await loader.load(''), isNull);
    expect(await loader.load('not a url'), isNull);
    expect(requests, 0);
  });
}

/// Keeps the mock from depending on dart:io's SocketException (web-safe tests).
class HttpExceptionStub implements Exception {
  const HttpExceptionStub();
}
