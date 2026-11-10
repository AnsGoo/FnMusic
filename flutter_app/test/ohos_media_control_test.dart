/// 鸿蒙锁屏 / 媒体面板的切歌命令转发：ohos 插件把 AVSession 的 next / previous
/// 经 MethodChannel 送回 Dart，必须落到 AppModel 的队列方法上。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:musicfly/audio/ohos_media_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 模拟 ArkTS 侧 MethodChannel.invokeMethod 发来的一条命令。
  Future<void> send(String method) async {
    await messenger.handlePlatformMessage(
      MfOhosMediaControl.channelName,
      codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
    // handler 是 async 的，让事件循环把 Future 跑完。
    await Future<void>.delayed(Duration.zero);
  }

  test('next / previous are forwarded to the queue', () async {
    var next = 0;
    var previous = 0;
    MfOhosMediaControl.bind(
      onNext: () async => next++,
      onPrevious: () async => previous++,
    );

    await send('next');
    await send('previous');
    await send('next');

    expect(next, 2);
    expect(previous, 1);
  });

  test('unknown commands are ignored', () async {
    var next = 0;
    var previous = 0;
    MfOhosMediaControl.bind(
      onNext: () async => next++,
      onPrevious: () async => previous++,
    );

    await send('stop');

    expect(next, 0);
    expect(previous, 0);
  });
}
