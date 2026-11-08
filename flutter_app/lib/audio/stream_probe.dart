/// Diagnoses why a stream URL will not play.
///
/// Music Free (and Subsonic servers in general) answer an unplayable request
/// with HTTP 200 and an XML `<error message="…">` body instead of a 4xx, so
/// the audio engine can only report "cannot open". Asking the server for the
/// first kilobyte gives the real reason back in words the listener understands.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/fn_connect.dart';
import '../data/http_defaults.dart';

/// Human readable problem with [streamUrl], or null when the reply looked
/// like audio — meaning the failure was local rather than server-side.
Future<String?> probeStream(String streamUrl) async {
  final client = HttpClient()..findProxy = proxyFor;
  try {
    final request = await client
        .getUrl(Uri.parse(streamUrl))
        .timeout(const Duration(seconds: 8));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
    final relayHeaders = fnRelayHeadersFor(streamUrl);
    if (relayHeaders != null) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        relayHeaders.entries.first.value,
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 8));
    final mime = response.headers.contentType?.mimeType ?? '';
    if (mime.isEmpty ||
        mime.startsWith('audio/') ||
        mime == 'application/octet-stream') {
      return null;
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 4), onTimeout: () => '');
    final message = RegExp(r'message="([^"]*)"').firstMatch(body)?.group(1);
    return explainServerMessage(message);
  } on SocketException catch (error) {
    return '连不上音乐服务：${error.message}';
  } on TimeoutException {
    return '音乐服务没有响应，请检查地址与网络';
  } catch (error) {
    return '无法读取音频流：$error';
  } finally {
    client.close(force: true);
  }
}

/// Maps a Subsonic error string onto a sentence about what to do next.
String explainServerMessage(String? message) {
  if (message == null || message.isEmpty) return '服务端没有返回音频数据';
  final lower = message.toLowerCase();
  if (lower.contains('not found')) {
    return '这首歌的文件在服务端找不到了（媒体源可能离线）';
  }
  if (lower.contains('transcod')) {
    return '服务端转码失败，可能缺少编码器';
  }
  if (lower.contains('folder') || lower.contains('unreachable')) {
    return '媒体源连不上，请检查挂载或网络';
  }
  return '服务端无法提供这首歌：$message';
}
