/// Remembers the Music Free session between launches.
///
/// The stored token is a bearer token, never the account password.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class SessionStore {
  static const _key = 'musicfly.session.v1';

  /// Written by builds that shipped before the MusicFly rename; read once so an
  /// upgrade does not force a fresh sign-in where the preferences survived.
  static const _legacyKey = 'fnmusic.session.v1';

  Future<MusicFreeSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? prefs.getString(_legacyKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return MusicFreeSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(MusicFreeSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
    await prefs.remove(_legacyKey);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_legacyKey);
  }
}
