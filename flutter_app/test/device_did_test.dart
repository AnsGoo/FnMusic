import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicfly/data/device_did.dart';

void main() {
  test('didFromSeed is deterministic and platform-agnostic', () {
    final first = didFromSeed('android:abc123');
    final second = didFromSeed('android:abc123');
    expect(first, second);
    expect(didFromSeed('ios:xyz'), isNot(first));
  });

  test('didFromSeed matches the official client did shape', () {
    final did = didFromSeed('macos:UUID-GUID');
    final parts = did.split('-');
    expect(parts.length, 3, reason: did);
    expect(parts[0].length, 64, reason: did);
    expect(parts[1].length, 15, reason: did);
    expect(parts[2].length, 15, reason: did);
    // Lowercase base32 alphabet only (the generator lowercases the chunks).
    final pattern = RegExp(r'^[a-z2-7]+$');
    for (final part in parts) {
      expect(pattern.hasMatch(part), isTrue, reason: did);
    }
  });

  test('loadOrCreateFnDid caches the value across calls', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await loadOrCreateFnDid();
    final second = await loadOrCreateFnDid();
    expect(first, isNotEmpty);
    expect(second, first);
  });

  test('loadOrCreateFnDid prefers an already persisted did', () async {
    SharedPreferences.setMockInitialValues({'musicfly.fn.did': 'old-did'});
    expect(await loadOrCreateFnDid(), 'old-did');
  });
}
