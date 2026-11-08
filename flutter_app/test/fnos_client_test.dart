/// fnOS WebSocket client crypto tests — the pieces that must interoperate
/// byte-for-byte with the server (PEM parsing, AES-CBC/PKCS7). The live WS
/// handshake is not covered here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfly/data/fnos_client.dart';

// A 2048-bit RSA public key in SPKI PEM form (same shape the fnOS handshake
// returns in `pub`).
const _spkiPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAhITklsLjPECMMBhby5Li
XCsgH41sZIDxRsY+u16iK6cz343rDqz5OsBvtZMdKM+xfCE9q7A1JRcJVE2YiNWI
0abCDMn/tCuwUm8+7f+tn19QWZewD5ao/2cw9avz23VKfMllaeV4uGhMJJ+BUVAj
cniX4+By14FF+AdlgtCNwf/MsOXCm20/Yo3Ydp9veqa4k3CAEpwP/b7w1qRcEAnS
XRxkhs6xeVKXygx7o2oU7tXlNBMbrineplQ9rYSFe7zfWwWTO/fAQn4JLC9ZFS4M
gb62zamj9HpmowEZekAv1lDiAC7yrniou++HIIqbGX6/dollnTKGW8OukcMNJWlR
dwIDAQAB
-----END PUBLIC KEY-----''';

Uint8List _hex(String value) => Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);

void main() {
  group('parseSpkiPublicKey', () {
    test('extracts modulus and exponent from a SPKI PEM', () {
      final key = parseSpkiPublicKey(_spkiPem);
      expect(key.modulus, isNotNull);
      expect(key.exponent, BigInt.from(65537));
      // 2048-bit key → modulus at least 2000 bits.
      expect(key.modulus!.bitLength, greaterThanOrEqualTo(2000));
    });

    test('tolerates CRLF line endings', () {
      final crlf = _spkiPem.replaceAll('\n', '\r\n');
      final key = parseSpkiPublicKey(crlf);
      expect(key.exponent, BigInt.from(65537));
    });
  });

  group('pkcs7 padding', () {
    test('pads to the block size and unpads losslessly', () {
      for (final length in [0, 1, 15, 16, 17, 31, 32]) {
        final data = Uint8List.fromList(
          List.generate(length, (i) => i & 0xff),
        );
        final padded = pkcs7Pad(data, 16);
        expect(padded.length % 16, 0);
        expect(pkcs7Unpad(padded), data);
      }
    });

    test('always appends a full block for aligned input', () {
      final padded = pkcs7Pad(Uint8List.fromList(utf8.encode('a' * 16)), 16);
      expect(padded.length, 32);
    });
  });

  group('aesCbcBlock', () {
    test('decrypt(encrypt(x)) round-trips', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final iv = Uint8List.fromList(List.filled(16, 0x42));
      final plain = Uint8List.fromList(utf8.encode('{"user":"admin"}'));
      final cipher = aesCbcBlock(key, iv, pkcs7Pad(plain, 16), true);
      final back = pkcs7Unpad(aesCbcBlock(key, iv, cipher, false));
      expect(back, plain);
    });

    test('matches the cross-verified AES-256-CBC vector', () {
      // Verified against both openssl and pycryptodome.
      final key = _hex(
        '603deb1015ca71be2b73aef0857d7781'
        '1f352c073b6108d72d9810a33224ca5f',
      );
      final iv = _hex('000102030405060708090a0b0c0d0e0f');
      final plain = _hex('6bc1bee22e409f96e93d7e117393172a');
      final cipher = aesCbcBlock(key, iv, plain, true);
      expect(cipher, _hex('d22a2368d880f24ff38d9dcb982b028d'));
    });
  });

  group('FnOsClient', () {
    test('a fresh instance exists and is not signed in', () {
      final client = FnOsClient();
      expect(client, isNotNull);
      expect(
        () => client.exchangeEntryToken(),
        throwsA(isA<FnOsException>()),
      );
    });
  });
}
