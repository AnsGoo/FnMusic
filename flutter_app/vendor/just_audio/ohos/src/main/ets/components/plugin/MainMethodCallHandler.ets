/**
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * */

import {
  BinaryMessenger,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { AudioPlayer } from './AudioPlayer'
import { MfMediaCommandForwarder, MF_MEDIA_COMMAND_KEY, mfApplySystemMetadata } from './MediaAvPlayer'

const TAG = 'MediaAvPlayer';

export class MainMethodCallHandler implements MethodCallHandler {
  private applicationContext: Context;
  private messenger: BinaryMessenger;
  private players: Map<string, AudioPlayer> = new Map<string, AudioPlayer>();
  /// 反向通道：把鸿蒙 AVSession 的切歌命令从原生送回 Dart（队列在 AppModel）。
  private controlChannel: MethodChannel;

  constructor(applicationContext: Context,
    messenger: BinaryMessenger) {
    this.applicationContext = applicationContext;
    this.messenger = messenger;
    this.controlChannel = new MethodChannel(messenger, 'com.seasonyuu.musicfly/media_control');
    this.registerForwarder();
  }

  /// AppStorage 是进程级全局：模块级变量在 ArkTS 打包后会被拆成多份，只有它
  /// 能让 MainMethodCallHandler 与 MediaAvPlayer 看到同一个转发器。
  /// 每次 init 都刷新一次 —— disposeAllPlayers 之后若 messenger 换了，旧的
  /// forwarder 仍会把命令发到已失效的通道，锁屏按钮就永久失灵。
  private registerForwarder(): void {
    AppStorage.setOrCreate(MF_MEDIA_COMMAND_KEY, new MfMediaCommandForwarder(
      (command: string): boolean => {
        console.info(TAG, `forward media control '${command}' to Dart`);
        // invokeMethod 在这个 SDK 里是 void + 可选 callback，直接发即可。
        this.controlChannel.invokeMethod(command, new Map<String, Object>());
        // App 侧一定注册了 handler；返回 true 阻止原生再用只有 1 首的
        // songList 去切歌（那会重播当前曲或什么都不做）。
        return true;
      }
    ));
    console.info(TAG, 'media control forwarder registered');
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'init':
        let id: string = call.argument("id");
        if (this.players.has(id)) {
          result.error("Platform player " + id + " already exists", null, null);
          break;
        }
        if (this.applicationContext && this.messenger) {
          // 通道可能随引擎重建而更换，重新把转发器指向当前 messenger。
          this.registerForwarder();
          this.players.set(id, new AudioPlayer(this.messenger, id));
        }
        result.success(null);
        break;
      case 'disposePlayer':
        let playerId: string = call.argument("id");
        let player: AudioPlayer | undefined = this.players.get(playerId);
        if (player != null) {
          player.dispose();
          this.players.delete(playerId);
        }
        result.success(new Map<String, Object>());
        break;
      case 'disposeAllPlayers':
        this.dispose();
        result.success(new Map<String, Object>());
        break;
      // 锁屏面板元数据由 App 主动下发：标准 just_audio 协议不携带歌名/封面，
      // 而 AVMetadataExtractor 对网络流基本抽不到东西。转发给当前唯一的
      // 播放器（MusicFly 全程只有一个 AudioPlayer 实例）。
      case 'setMetadata': {
        // App 已经带鉴权头把封面下载好，字节直接交过来；不同鸿蒙版本的
        // StandardMessageCodec 会把它解成 Uint8Array 或 ArrayBuffer，都要接住。
        const rawArtwork: Object | undefined = call.argument("artwork");
        const artwork = this.artworkBytes(rawArtwork);
        // 只写当前活跃实例。遍历 players 时若命中已释放的旧实例，元数据会写
        // 进旧 AVSession —— 锁屏就一直停在那一首（B），而 App 内已经放到 A。
        const applied = mfApplySystemMetadata(
          call.argument("title"),
          call.argument("artist"),
          call.argument("artUri"),
          call.argument("durationMs"),
          artwork,
          call.argument("trackId"),
        );
        if (!applied) {
          this.players.forEach(player => {
            player.setSessionMetadata(
              call.argument("title"),
              call.argument("artist"),
              call.argument("artUri"),
              call.argument("durationMs"),
              artwork,
              call.argument("trackId"),
            );
          });
        }
        console.info(TAG, `setMetadata from Dart: title=${call.argument("title")}, artworkBytes=${artwork ? artwork.length : 0}, applied=${applied}`);
        result.success(new Map<String, Object>());
        break;
      }
      default:
        result.notImplemented();
        break;
    }

  }

  private artworkBytes(value: Object | undefined): Uint8Array | undefined {
    if (value instanceof Uint8Array) {
      return value;
    }
    if (value instanceof ArrayBuffer) {
      return new Uint8Array(value);
    }
    return undefined;
  }

  dispose() {
    // 不清 AppStorage：引擎热重启时新构造的 forwarder 会覆盖它，清掉反而
    // 可能让仍在运行的 AVSession 回调失去转发能力。
    console.info(TAG, 'media control forwarder disposed');
    this.players.forEach(player => {
      player.dispose();
    });
    this.players.clear();
  }
}