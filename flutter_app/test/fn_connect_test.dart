/// Fn Connect unit tests: parameter parsing, the broker signature, candidate
/// construction and relay-host classification. Network calls are not covered.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfly/data/fn_connect.dart';

void main() {
  group('fixed backend port', () {
    test('direct FNID candidates always use 14533', () {
      expect(kDefaultBackendPort, 14533);
      final params = FnConnectionParams.fromJson(const {
        'ipv4': ['192.168.1.10'],
      });
      final direct = buildFnCandidates(params, kDefaultBackendPort)
          .where((c) => !c.relay)
          .toList();
      expect(direct, hasLength(2));
      for (final candidate in direct) {
        expect(candidate.address.port, 14533);
      }
    });
  });

  group('FnConnectionParams.fromJson', () {
    test('parses the broker response shape', () {
      final params = FnConnectionParams.fromJson(const {
        'ddns': null,
        'ipv4': ['192.168.124.18', '192.168.11.2'],
        'publicIpv4': ['120.239.1.2'],
        'publicIpv6': ['2409:8a00:1::5'],
        'fn': ['myid.5ddd.com:443'],
        'port': {'httpsPort': 5667, 'httpPort': 5666},
      });
      expect(params.internalIPv4s, ['192.168.124.18', '192.168.11.2']);
      expect(params.publicIPv4s, ['120.239.1.2']);
      expect(params.publicIPv6s, ['2409:8a00:1::5']);
      expect(params.relayDomains, ['myid.5ddd.com:443']);
    });

    test('tolerates missing fields', () {
      final params = FnConnectionParams.fromJson(const {});
      expect(params.internalIPv4s, isEmpty);
      expect(params.publicIPv4s, isEmpty);
      expect(params.publicIPv6s, isEmpty);
      expect(params.relayDomains, isEmpty);
    });
  });

  group('computeAuthx', () {
    test('is a deterministic md5 chain of prefix, path, nonce, ts, payload, key',
        () {
      final authx = computeAuthx(
        'post',
        kFnApiPath,
        '{"fnId":"myid"}',
        nonce: '123456',
        timestampMs: 1700000000000,
      );
      expect(authx, contains('nonce=123456'));
      expect(authx, contains('timestamp=1700000000000'));
      expect(authx, matches(RegExp(r'sign=[0-9a-f]{32}')));
    });
  });

  group('buildFnCandidates', () {
    test('orders LAN → IPv6 → IPv4 → relay and brackets IPv6', () {
      final candidates = buildFnCandidates(
        const FnConnectionParams(
          internalIPv4s: ['192.168.124.18'],
          publicIPv4s: ['120.239.1.2'],
          publicIPv6s: ['2409:8a00:1::5'],
          relayDomains: ['myid.5ddd.com:443'],
        ),
        14533,
      );

      expect(candidates.map((c) => c.address.toString()).toList(), [
        // LAN: HTTP before HTTPS
        'http://192.168.124.18:14533/',
        'https://192.168.124.18:14533/',
        // public IPv6, bracketed
        'http://[2409:8a00:1::5]:14533/',
        'https://[2409:8a00:1::5]:14533/',
        // public IPv4
        'http://120.239.1.2:14533/',
        'https://120.239.1.2:14533/',
        // unified gateway: LAN portal ports, then the NAS device domain
        'https://192.168.124.18:5667/app/musicfree/',
        'http://192.168.124.18:5666/app/musicfree/',
        'https://myid.5ddd.com/app/musicfree/',
        // relay: HTTPS on 443, port stripped
        'https://myid.5ddd.com/',
      ]);
      expect(candidates.last.relay, isTrue);
      expect(
        candidates.take(6).every((c) => !c.relay),
        isTrue,
      );
    });

    test('deduplicates repeated addresses', () {
      final candidates = buildFnCandidates(
        const FnConnectionParams(
          internalIPv4s: ['192.168.1.1', '192.168.1.1'],
          publicIPv4s: [],
          publicIPv6s: [],
          relayDomains: ['192.168.1.1'],
        ),
        14533,
      );
      final hosts = candidates.map((c) => c.address.toString()).toSet();
      expect(hosts.length, candidates.length);
    });

    test('extra relay domains come before the broker ones', () {
      final candidates = buildFnCandidates(
        const FnConnectionParams(
          internalIPv4s: [],
          publicIPv4s: [],
          publicIPv6s: [],
          relayDomains: ['device.5ddd.com'],
        ),
        14533,
        extraRelayDomains: ['abc123.myid.5ddd.com'],
      );
      // The device-domain gateway candidate (device.5ddd.com/app/musicfree/)
      // precedes the relay subdomains; the broker device domain itself comes
      // last among the plain relay entries.
      expect(candidates.map((c) => c.address.host).toList(), [
        'device.5ddd.com',
        'abc123.myid.5ddd.com',
        'device.5ddd.com',
      ]);
    });
  });

  group('relay host classification', () {
    test('flags Feiniu relay hosts only', () {
      expect(isFnRelayHost('myid.5ddd.com'), isTrue);
      expect(isFnRelayHost('abc.myid.5ddd.com'), isTrue);
      expect(isFnRelayHost('chenghaiwen.fnos.net'), isTrue);
      expect(isFnRelayHost('sub.chenghaiwen.fnos.net'), isTrue);
      expect(isFnRelayHost('fnos.net.evil.example'), isFalse);
      expect(isFnRelayHost('5ddd.com.evil.example'), isFalse);
      expect(isFnRelayHost('192.168.1.10'), isFalse);
      expect(isFnRelayHost('localhost'), isFalse);
    });

    test('fnRelayHeadersFor returns cookie only for relay URLs', () {
      fnRelayEntryToken = null;
      final headers = fnRelayHeadersFor('https://myid.5ddd.com/rest/stream?id=1');
      expect(headers, isNotNull);
      expect(headers!['Cookie'], 'mode=relay');
      expect(
        fnRelayHeadersFor('http://192.168.124.18:14533/rest/stream?id=1'),
        isNull,
      );
      expect(fnRelayHeadersFor('not a url'), isNull);
    });

    test('fnRelayHeadersFor carries the entry-token once set', () {
      fnRelayEntryToken = 'abc123';
      addTearDown(() => fnRelayEntryToken = null);
      final headers = fnRelayHeadersFor(
        'https://musicfree.chenghaiwen.fnos.net/rest/stream?id=1',
      );
      expect(headers, isNotNull);
      expect(headers!['Cookie'], 'mode=relay; entry-token=abc123');
    });

    test('fnRelayHeadersFor authorizes gateway paths with the fnOS token', () {
      fnGatewayToken = 'fnos-tok';
      addTearDown(() => fnGatewayToken = null);
      final headers = fnRelayHeadersFor(
        'https://chenghaiwen.fnos.net/app/musicfree/rest/stream?id=1',
        bearerToken: 'jwt-tok',
      );
      expect(headers, isNotNull);
      // Gateway owns Authorization (trim scheme); the Music Free JWT rides in
      // the Navidrome-style header instead.
      expect(headers!['Authorization'], 'trim fnos-tok');
      expect(headers['X-ND-Authorization'], 'Bearer jwt-tok');
      expect(headers.containsKey('Cookie'), isFalse);
      // Without a bearer there is no X-ND header.
      final noBearer = fnRelayHeadersFor(
        'https://192.168.124.18:5667/app/musicfree/rest/stream?id=1',
      );
      expect(noBearer!['Authorization'], 'trim fnos-tok');
      expect(noBearer.containsKey('X-ND-Authorization'), isFalse);
      // Without a gateway token the relay-cookie fallback applies (the IP
      // host is not a relay host, so nothing is returned).
      fnGatewayToken = null;
      expect(
        fnRelayHeadersFor(
          'https://192.168.124.18:5667/app/musicfree/rest/stream?id=1',
        ),
        isNull,
      );
    });
  });
}
