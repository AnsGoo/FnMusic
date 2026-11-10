/// FNID owns its address pool; only an ordinary login may show and edit
/// backup addresses in settings.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicfly/audio/player.dart';
import 'package:musicfly/data/models.dart';
import 'package:musicfly/data/musicfree_client.dart';
import 'package:musicfly/state/app_model.dart';

class _SilentPlayer extends MfPlayer {}

final _gateway = Uri.parse('https://myid.fnos.net/app/musicfree/');
final _lan = Uri.parse('http://192.168.1.10:14533/');
final _wan = Uri.parse('https://1.2.3.4:14533/');

MusicFreeClient _client() => MusicFreeClient(
  httpClient: MockClient(
    (_) async => http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    ),
  ),
);

/// Restores [session] from the mock preference store so AppModel's private
/// `_session` is populated without going through a real network login.
Future<AppModel> _restored(MusicFreeSession session) async {
  SharedPreferences.setMockInitialValues({
    'musicfly.session.v1': jsonEncode(session.toJson()),
  });
  final model = AppModel(client: _client(), player: _SilentPlayer());
  addTearDown(model.dispose);
  await model.restoreSession();
  return model;
}

MusicFreeSession _fnSession({bool fnConnect = true}) => MusicFreeSession(
  baseUrl: _gateway,
  token: 't',
  username: 'admin',
  clientSalt: 'salt',
  addresses: [_gateway, _lan, _wan],
  fnConnect: fnConnect,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FNID exposes one read-only endpoint and rejects user edits', () async {
    final model = await _restored(_fnSession());

    expect(model.addressesManaged, isTrue);
    expect(model.serverAddresses, [_gateway]);
    // The full pool is still there for the internal failover prober.
    expect(model.session!.allAddresses, [_gateway, _lan, _wan]);

    expect(await model.addServerAddress('http://10.0.0.5:14533'), isFalse);
    await model.removeServerAddress(_wan);
    await model.useServerAddress(_lan);
    expect(model.session!.allAddresses, [_gateway, _lan, _wan]);
    expect(model.serverAddresses, [_gateway]);
  });

  test('a legacy FNID session without the flag is still managed', () async {
    SharedPreferences.setMockInitialValues({
      'musicfly.session.v1': jsonEncode({
        'baseUrl': _gateway.toString(),
        'token': 't',
        'username': 'admin',
        'clientSalt': 'salt',
        'addresses': [_lan.toString(), _wan.toString()],
      }),
    });
    final model = AppModel(client: _client(), player: _SilentPlayer());
    addTearDown(model.dispose);
    await model.restoreSession();

    expect(model.addressesManaged, isTrue);
    expect(model.serverAddresses, [_gateway]);
    expect(await model.addServerAddress('http://10.0.0.5:14533'), isFalse);
  });

  test('an ordinary login keeps its editable backup addresses', () async {
    final model = await _restored(
      MusicFreeSession(
        baseUrl: _lan,
        token: 't',
        username: 'admin',
        clientSalt: 'salt',
        addresses: [_lan, _wan],
      ),
    );

    expect(model.addressesManaged, isFalse);
    expect(model.serverAddresses, [_lan, _wan]);
    expect(await model.addServerAddress('http://10.0.0.5:14533'), isTrue);
    expect(model.serverAddresses, [
      _lan,
      _wan,
      Uri.parse('http://10.0.0.5:14533'),
    ]);
  });
}
