/// fnOS WebSocket client — the protocol the Feiniu web/app clients speak.
///
/// Used by the FnConnect flow: sign in to the NAS (username/password, with an
/// optional TOTP code when the account has two-step verification), then
/// exchange the session for a gateway `entry-token` and list the installed
/// apps' relay domains. Every request to an app subdomain under
/// `<app>.<fnId>.fnos.net` must carry that entry-token as a cookie, otherwise
/// the relay gateway answers 403.
///
/// Protocol (reverse engineered from the fnOS web client / pyfnos):
///
/// 1. `wss://<host>/websocket?type=main`; first message
///    `{reqid, req: "util.crypto.getRSAPub"}` → `{pub: <PEM>, si: <id>}`.
/// 2. Login payload (username/password/…) is AES-256-CBC encrypted with a
///    fresh random key; the key itself is RSA-PKCS1 encrypted. Sent as
///    `{req: "encrypted", iv, rsa, aes}` (all base64). `req: "user.login"`.
/// 3. Accounts with 2FA answer with `{isBindTwofaSecret: true, accessToken}` —
///    re-encrypt `{req: "user.2fa.loginVerify", code, accessToken, …}` with a
///    *fresh* AES key; the final `secret` is encrypted with that newest key.
/// 4. Signed requests: prefix the JSON body with
///    `base64(HMAC-SHA256(secretBytes, body))` and send it as one message.
///
/// The connection is short-lived here (sign in → exchange → list → close), so
/// no heartbeat is implemented.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/asymmetric/api.dart' as pc_asym;
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FnOsException implements Exception {
  FnOsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The account requires a TOTP code; [accessToken] from the challenge must be
/// passed back through [FnOsClient.submitTwoFa].
class FnOsTwoFaRequired implements Exception {
  FnOsTwoFaRequired(this.accessToken);

  final String accessToken;

  @override
  String toString() => '需要两步验证码';
}

/// One installed app that exposes a relay subdomain.
class FnOsAppEntry {
  const FnOsAppEntry({
    required this.appId,
    required this.title,
    required this.fnDomain,
    required this.running,
  });

  final String appId;
  final String title;

  /// Relay subdomain label (`1panel` in `1panel.<fnId>.fnos.net`); empty when
  /// the app has no web entry.
  final String fnDomain;

  final bool running;
}

String _randomHex(int chars) {
  final r = Random.secure();
  return List.generate(chars, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// Mirrors pyfnos `_generate_reqid`: 13-digit ms timestamp + 12 random chars.
String _generateReqid() =>
    '${DateTime.now().millisecondsSinceEpoch}${_randomHex(12)}';

/// Mirrors pyfnos `_generate_did`: three base32 chunks joined by dashes.
String _generateDid() {
  String chunk(String seed, int len) {
    final bytes = Uint8List.fromList(utf8.encode(seed));
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var bits = 0;
    var value = 0;
    final out = StringBuffer();
    for (final byte in bytes) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        out.write(alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    var text = out.toString();
    if (text.length > len) text = text.substring(0, len);
    return text.toLowerCase();
  }

  final now = DateTime.now().millisecondsSinceEpoch.toString();
  final r = Random.secure();
  return '${chunk(now, 64)}-'
      '${chunk(r.nextDouble().toString(), 15)}-'
      '${chunk(r.nextDouble().toString(), 15)}';
}

/// RSA PKCS1 v1.5 public key parsed from a SPKI PEM (`BEGIN PUBLIC KEY`).
///
/// Minimal DER walk: outer SEQUENCE → algorithm SEQUENCE (skipped) →
/// BIT STRING → inner SEQUENCE { INTEGER modulus, INTEGER exponent }.
pc_asym.RSAPublicKey parseSpkiPublicKey(String pem) {
  final body = pem
      .split(RegExp(r'\r?\n'))
      .where((line) => !line.contains('-----'))
      .join()
      .trim();
  final der = Uint8List.fromList(base64.decode(body));
  var offset = 0;

  int readLength() {
    final first = der[offset++];
    if (first < 0x80) return first;
    final count = first & 0x7f;
    var len = 0;
    for (var i = 0; i < count; i++) {
      len = (len << 8) | der[offset++];
    }
    return len;
  }

  // Returns the value range of the next TLV; [expectedTag] 0 means any.
  (int, int) readTlv(int expectedTag) {
    final tag = der[offset++];
    if (expectedTag != 0 && tag != expectedTag) {
      throw FormatException('DER 标签不匹配: $tag');
    }
    final length = readLength();
    final start = offset;
    offset += length;
    return (start, offset);
  }

  if (der[offset++] != 0x30) throw const FormatException('bad DER');
  readLength();
  readTlv(0x30); // algorithm identifier — skipped
  final (bitStart, bitEnd) = readTlv(0x03); // BIT STRING
  // First byte of a BIT STRING value is the count of unused bits (0 here).
  var inner = bitStart + 1;
  if (der[inner] != 0x30) throw const FormatException('bad DER');
  final parsed = _parseRsaKeyDer(der.sublist(inner, bitEnd));
  return parsed;
}

pc_asym.RSAPublicKey _parseRsaKeyDer(Uint8List der) {
  var offset = 0;
  int readLength() {
    final first = der[offset++];
    if (first < 0x80) return first;
    final count = first & 0x7f;
    var len = 0;
    for (var i = 0; i < count; i++) {
      len = (len << 8) | der[offset++];
    }
    return len;
  }

  BigInt readInteger() {
    if (der[offset++] != 0x02) throw const FormatException('bad DER');
    final length = readLength();
    var value = BigInt.zero;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | BigInt.from(der[offset + i]);
    }
    offset += length;
    return value;
  }

  if (der[offset++] != 0x30) throw const FormatException('bad DER');
  readLength();
  final modulus = readInteger();
  final exponent = readInteger();
  return pc_asym.RSAPublicKey(modulus, exponent);
}

Uint8List pkcs7Pad(Uint8List data, int blockSize) {
  final padLen = blockSize - (data.length % blockSize);
  return Uint8List.fromList([...data, ...List.filled(padLen, padLen)]);
}

Uint8List pkcs7Unpad(Uint8List data) {
  final padLen = data.last;
  if (padLen <= 0 || padLen > data.length) throw FnOsException('解密失败');
  return data.sublist(0, data.length - padLen);
}

Uint8List aesCbcBlock(Uint8List key, Uint8List iv, Uint8List input, bool encrypt) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(key), iv));
  // CBC chaining state lives inside the cipher, so walk the input block by
  // block — process() on the whole buffer only advanced a single block here.
  final out = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 16) {
    final block = cipher.process(
      Uint8List.sublistView(input, offset, offset + 16),
    );
    out.setRange(offset, offset + 16, block);
  }
  return out;
}

class FnOsClient {
  FnOsClient();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  String? _publicKeyPem;
  String? _sessionId;
  Uint8List? _aesKey;
  Uint8List? _iv;
  String? _secretB64;
  String? _accessToken;
  String? _did;

  static const _connectTimeout = Duration(seconds: 12);
  static const _replyTimeout = Duration(seconds: 10);

  /// Connects and performs the RSA handshake.
  Future<void> connect(String wsUrl) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await channel.ready.timeout(_connectTimeout);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object e) => _failPending('连接已断开：$e'),
        onDone: () => _failPending('连接已关闭'),
      );
      final pub = await _sendPlain({
        'reqid': _generateReqid(),
        'req': 'util.crypto.getRSAPub',
      });
      _publicKeyPem = pub['pub'] as String?;
      _sessionId = pub['si']?.toString();
      if (_publicKeyPem == null || _sessionId == null) {
        throw FnOsException('fnOS 握手失败：未获取到公钥');
      }
    } on FnOsException {
      rethrow;
    } on TimeoutException {
      await close();
      throw FnOsException('连接 fnOS 超时');
    } catch (e) {
      await close();
      throw FnOsException('无法连接 fnOS：$e');
    }
  }

  void _failPending(String message) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(FnOsException(message));
      }
    }
    _pending.clear();
  }

  /// Sign-in. Throws [FnOsTwoFaRequired] when the account has 2FA; call
  /// [submitTwoFa] with the code and [FnOsException] on bad credentials.
  Future<void> login(String username, String password) async {
    final response = await _sendEncrypted({
      'reqid': _generateReqid(),
      'user': username,
      'password': password,
      'stay': true,
      'deviceType': 'Browser',
      'deviceName': 'MusicFly',
      'did': _did = _generateDid(),
      'req': 'user.login',
      'si': _sessionId,
    });
    if (response['result'] == 'fail') {
      final msg = (response['errmsg'] ?? response['msg'] ?? '').toString();
      throw FnOsException(
        msg.isEmpty ? 'fnOS 登录失败' : 'fnOS 登录失败：$msg',
      );
    }
    if (response['isBindTwofaSecret'] == true &&
        response['accessToken'] != null &&
        !response.containsKey('token')) {
      _accessToken = response['accessToken'].toString();
      throw FnOsTwoFaRequired(_accessToken!);
    }
    _completeLogin(response);
  }

  /// Completes a 2FA challenge started by [login].
  Future<void> submitTwoFa(String code, {bool trustDevice = true}) async {
    final accessToken = _accessToken;
    if (accessToken == null) throw FnOsException('没有待验证的登录');
    final trimmed = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      throw FnOsException('两步验证码必须是 6 位数字');
    }
    final response = await _sendEncrypted({
      'reqid': _generateReqid(),
      'code': trimmed,
      'isTrustedDevice': trustDevice,
      'accessToken': accessToken,
      'stay': 1,
      'deviceName': 'MusicFly',
      'deviceType': 'Browser',
      'did': _did ??= _generateDid(),
      'req': 'user.2fa.loginVerify',
      'si': _sessionId,
    });
    if (response['result'] == 'fail') {
      final msg = (response['errmsg'] ?? response['msg'] ?? '').toString();
      throw FnOsException(
        msg.isEmpty ? '两步验证失败' : '两步验证失败：$msg',
      );
    }
    _completeLogin(response);
  }

  void _completeLogin(Map<String, dynamic> response) {
    final secret = response['secret'];
    if (response['result'] != 'succ' || secret == null) {
      throw FnOsException('fnOS 登录响应异常');
    }
    final decrypted = _decryptWithLastKey(secret.toString());
    _secretB64 = base64.encode(decrypted);
  }

  /// Exchanges the session for the relay gateway's `entry-token`.
  Future<String> exchangeEntryToken() async {
    final response = await _sendSigned(
      'appcgi.sac.entry.v1.exchangeEntryToken',
      {'data': {'token': ''}},
    );
    final token = (response['data'] as Map<String, dynamic>?)?['token'];
    if (token is! String || token.isEmpty) {
      throw FnOsException('未能获取中继访问令牌');
    }
    return token;
  }

  /// Lists installed apps that expose a relay subdomain.
  Future<List<FnOsAppEntry>> listAppEntries() async {
    final response = await _sendSigned('appcgi.sac.entry.v1.appStoreList', {});
    final list = (response['data'] as Map<String, dynamic>?)?['list'];
    if (list is! List) return const [];
    return [
      for (final raw in list)
        if (raw is Map<String, dynamic>)
          FnOsAppEntry(
            appId: raw['appID']?.toString() ?? '',
            title: raw['title']?.toString() ?? '',
            fnDomain: ((raw['uri'] as Map<String, dynamic>?)?['fnDomain'])
                    ?.toString() ??
                '',
            running: raw['status']?.toString() == 'running',
          ),
    ];
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _failPending('连接已关闭');
  }

  // ---- messaging ----

  Future<Map<String, dynamic>> _sendPlain(Map<String, dynamic> message) =>
      _request(message);

  Future<Map<String, dynamic>> _sendEncrypted(Map<String, dynamic> payload) {
    final key = _secureRandomBytes(32);
    final iv = _secureRandomBytes(16);
    _aesKey = key;
    _iv = iv;
    // The encrypted envelope carries no reqid — the server decrypts the
    // payload and echoes the inner reqid back.
    final envelope = jsonEncode(_encryptPayload(payload, key, iv));
    return _requestRaw(envelope, reqid: payload['reqid']?.toString());
  }

  Map<String, dynamic> _encryptPayload(
    Map<String, dynamic> payload,
    Uint8List key,
    Uint8List iv,
  ) {
    final json = jsonEncode(payload);
    final encrypted = aesCbcBlock(
      key,
      iv,
      pkcs7Pad(Uint8List.fromList(utf8.encode(json)), 16),
      true,
    );
    final rsa = _rsaEncrypt(key);
    return {
      'req': 'encrypted',
      'iv': base64.encode(iv),
      'rsa': base64.encode(rsa),
      'aes': base64.encode(encrypted),
    };
  }

  Uint8List _rsaEncrypt(Uint8List data) {
    final key = parseSpkiPublicKey(_publicKeyPem!);
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, pc.PublicKeyParameter<pc_asym.RSAPublicKey>(key));
    return cipher.process(data);
  }

  Future<Map<String, dynamic>> _sendSigned(
    String method,
    Map<String, dynamic> payload,
  ) {
    final secret = _secretB64;
    if (secret == null) throw FnOsException('尚未登录');
    final reqid = _generateReqid();
    final body = {
      ...payload,
      'req': method,
      'reqid': reqid,
    };
    final json = jsonEncode(body);
    final keyBytes = base64.decode(secret);
    final mac = crypto.Hmac(crypto.sha256, keyBytes)
        .convert(utf8.encode(json))
        .bytes;
    final signed = base64.encode(mac) + json;
    return _requestRaw(signed, reqid: reqid);
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> message) =>
      _requestRaw(
        jsonEncode(message),
        reqid: message['reqid']?.toString(),
      );

  Future<Map<String, dynamic>> _requestRaw(
    String body, {
    required String? reqid,
  }) {
    if (reqid == null || reqid.isEmpty) {
      throw FnOsException('请求缺少 reqid');
    }
    final completer = Completer<Map<String, dynamic>>();
    _pending[reqid] = completer;
    _channel!.sink.add(body);
    return completer.future.timeout(_replyTimeout, onTimeout: () {
      _pending.remove(reqid);
      throw FnOsException('fnOS 响应超时');
    });
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final reqid = data['reqid']?.toString();
    if (reqid == null) return;
    final completer = _pending.remove(reqid);
    if (completer != null && !completer.isCompleted) {
      completer.complete(data);
    }
  }

  Uint8List _decryptWithLastKey(String b64) {
    final key = _aesKey;
    final iv = _iv;
    if (key == null || iv == null) throw FnOsException('缺少解密密钥');
    final decrypted = aesCbcBlock(key, iv, base64.decode(b64), false);
    return pkcs7Unpad(decrypted);
  }

  Uint8List _secureRandomBytes(int length) {
    final r = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => r.nextInt(256)),
    );
  }
}
