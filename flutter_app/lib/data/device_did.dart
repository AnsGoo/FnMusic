/// Stable fnOS device ID (`did`) for the Fn Connect trusted-device flow.
///
/// The NAS keys trusted-device status (2FA skip) on the `did` sent with every
/// login, so it must survive app reinstalls — a value stored only in
/// SharedPreferences would be wiped on uninstall and every reinstall would
/// look like a brand-new device, re-triggering the 2FA challenge.
///
/// Strategy:
/// 1. A did already persisted in SharedPreferences wins (existing installs
///    keep their identity).
/// 2. Otherwise the did is **derived deterministically** from a real hardware
///    identifier: ANDROID_ID (Android), `identifierForVendor` (iOS) or the
///    IOPlatformUUID (macOS). The seed is hashed into the official
///    three-chunk base32 shape, so the same device always produces the same
///    did even after a full wipe of app data.
/// 3. When no hardware identifier is available (unsupported platform, plugin
///    missing — e.g. the ohos build today), fall back to a random did that is
///    persisted for the lifetime of the installation.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

import 'fnos_client.dart' show generateFnDid;

const String _fnDidKey = 'musicfly.fn.did';

/// Returns the device ID to use for fnOS sign-ins: the cached one, else one
/// derived from the hardware identifier, else a persisted random one.
Future<String> loadOrCreateFnDid() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(_fnDidKey);
  if (cached != null && cached.isNotEmpty) return cached;

  final seed = await _hardwareSeed();
  final did = seed == null ? generateFnDid() : didFromSeed(seed);
  await prefs.setString(_fnDidKey, did);
  return did;
}

/// A stable per-device string, or null when the platform cannot provide one.
Future<String?> _hardwareSeed() async {
  try {
    if (Platform.isAndroid) {
      // device_info_plus 9.x dropped androidId; ANDROID_ID comes straight
      // from the platform channel in MainActivity (see the Kotlin comment).
      final id = await const MethodChannel('musicfly/device')
          .invokeMethod<String>('androidId');
      if (id != null && id.isNotEmpty) return 'android:$id';
      return null;
    }
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final id = (await plugin.iosInfo).identifierForVendor;
      if (id != null && id.isNotEmpty) return 'ios:$id';
    } else if (Platform.isMacOS) {
      final guid = (await plugin.macOsInfo).systemGUID;
      if (guid != null && guid.isNotEmpty) return 'macos:$guid';
    }
    // ohos: the adapted device_info_plus does not expose a hardware ID yet —
    // fall through to the persisted-random fallback.
  } catch (_) {
    // Missing plugin (e.g. flutter test) or platform lookup failure — fall
    // back instead of blocking the sign-in flow.
  }
  return null;
}

/// Derives a did in the official client's shape (`<chunk>-<15>-<15>`, three
/// lowercase base32 chunks) purely from [seed], so re-derivation is stable.
String didFromSeed(String seed) {
  return '${_hashChunk('$seed/1', 64)}-${_hashChunk('$seed/2', 15)}-'
      '${_hashChunk('$seed/3', 15)}';
}

String _hashChunk(String input, int length) {
  // Two digests concatenated → 104 base32 chars, enough for any chunk size.
  final digest = crypto.sha256.convert(utf8.encode(input)).bytes;
  final second = crypto.sha256.convert(
    Uint8List.fromList([...digest, ...utf8.encode(input)]),
  ).bytes;
  return _base32([...digest, ...second]).toLowerCase().substring(0, length);
}

/// RFC 4648 base32 without padding.
String _base32(List<int> bytes) {
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
  if (bits > 0) out.write(alphabet[(value << (5 - bits)) & 31]);
  return out.toString();
}
