
import { FlutterAbility, FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/// 与 lib/audio/background_task.dart 里的 channel 名保持一致。
const BACKGROUND_AUDIO_CHANNEL = 'com.seasonyuu.musicfly/background_audio';

/// 鸿蒙的后台播放要两件事配合：module.json5 里声明 backgroundModes:
/// ["audioPlayback"]，运行时再用 backgroundTaskManager 起一个「长时任务」。
/// 只声明不申请，切后台后进程照样被冻结；只申请不声明，申请会被静默拒绝。
///
/// 系统媒体面板（锁屏封面、上一首/下一首）不在这里做 —— just_audio 的 ohos
/// 分支已经在播放器初始化时创建并激活了 AVSession。
export default class EntryAbility extends FlutterAbility {
  private channel: MethodChannel | null = null;
  private longTaskRunning: boolean = false;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)

    this.channel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), BACKGROUND_AUDIO_CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'start') {
          this.startLongTask()
            .then(() => result.success(true))
            .catch((err: BusinessError) => {
              // 没声明 backgroundModes / 没授权时这里会失败，日志里要能看见。
              console.error(`[MusicFly] startBackgroundRunning failed: ${err.code} ${err.message}`);
              result.error(`${err.code}`, err.message, null);
            });
        } else if (call.method === 'stop') {
          this.stopLongTask()
            .then(() => result.success(true))
            .catch((err: BusinessError) => {
              console.error(`[MusicFly] stopBackgroundRunning failed: ${err.code} ${err.message}`);
              result.success(false);
            });
        } else {
          result.notImplemented();
        }
      }
    });
  }

  private async startLongTask(): Promise<void> {
    if (this.longTaskRunning) {
      return;
    }
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: this.context.abilityInfo.bundleName,
          abilityName: this.context.abilityInfo.name
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent: WantAgent = await wantAgent.getWantAgent(info);
    await backgroundTaskManager.startBackgroundRunning(
      this.context,
      backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
      agent
    );
    this.longTaskRunning = true;
    console.info('[MusicFly] audio long task started');
  }

  private async stopLongTask(): Promise<void> {
    if (!this.longTaskRunning) {
      return;
    }
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    this.longTaskRunning = false;
  }

  onDestroy(): void {
    this.stopLongTask();
    super.onDestroy();
  }
}
