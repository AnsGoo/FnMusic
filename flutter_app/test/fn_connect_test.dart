/// Fn Connect unit tests: parameter parsing, the broker signature, candidate
/// construction and relay-host classification. Network calls are not covered.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfly/data/fn_connect.dart';

void main() {
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
      expect(candidates.map((c) => c.address.host).toList(), [
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
  });
}
