/// Covers the diagnosis path that turns "cannot open" into a real reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:musicfly/audio/stream_probe.dart';

void main() {
  setUpAll(() {
    // `flutter_test` answers every request with a fake 400; the probe needs a
    // socket, even a loopback one.
    HttpOverrides.global = null;
  });

  group('explainServerMessage', () {
    test('names a missing media file', () {
      expect(
        explainServerMessage('Media file not found'),
        contains('文件在服务端找不到了'),
      );
    });

    test('passes unfamiliar reasons through', () {
      expect(explainServerMessage('Playlist is private'), contains('Playlist'));
    });

    test('handles an empty message', () {
      expect(explainServerMessage(null), contains('没有返回音频数据'));
    });
  });

  group('probeStream', () {
    late HttpServer server;

    Future<String> serve(void Function(HttpRequest) handler) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(handler);
      return 'http://127.0.0.1:${server.port}/rest/stream?id=x';
    }

    tearDown(() async {
      await server.close(force: true);
    });

    test('accepts an audio reply', () async {
      final url = await serve((request) {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.add(List<int>.filled(64, 0));
        request.response.close();
      });

      expect(await probeStream(url), isNull);
    });

    test('explains the XML error document servers answer with', () async {
      final url = await serve((request) {
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        );
        request.response.write(
          '<subsonic-response status="failed"><error code="70" '
          'message="Media file not found"></error></subsonic-response>',
        );
        request.response.close();
      });

      expect(await probeStream(url), contains('媒体源可能离线'));
    });

    test('reports an unreachable server instead of throwing', () async {
      final url = await serve((request) {
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
        );
        request.response.write('<subsonic-response status="failed"/>');
        request.response.close();
      });
      await server.close(force: true);

      final problem = await probeStream(url);
      expect(problem, isNotNull);
    });
  });
}
