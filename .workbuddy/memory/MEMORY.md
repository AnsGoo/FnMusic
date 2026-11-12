# MusicFly（乐记）项目约定

## 工作流偏好

- **不要每次改动后打包 DMG/APK**。用户在 VS Code 里用 launch 调试，支持热更新（hot reload）。改完代码验证手段：`flutter analyze` + `flutter test`（绕代理：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY NO_PROXY=127.0.0.1,localhost ~/development/flutter/bin/flutter test`）。只在用户明确要安装包时才跑 `scripts/package_macos.sh`、`scripts/package_windows.sh` 或 `flutter build apk`。
- Flutter SDK：macOS 在 `~/development/flutter`；Windows（当前机器）在 `D:\flutter`，不在 PATH 上，VS 2022 C++ 工具链已装。
- 后端在隔壁 `~/Documents/code/music-free/backend`（Go/Gin，localhost:14533，admin/admin），服务端由用户自己启动，不要代启。
- 验证视觉用临时 golden 渲染（Arial Unicode 字体 + RepaintBoundary.toImage），核对后删除测试文件；沙箱无 screencapture 权限。

## 关键技术事实

- Subsonic 认证必须 token（md5(password+salt)），`p=` 会被后端拒（code 50）。
- 流播放：只有 wma/ape 等系统解不了的格式才走 `format=mp3` 转码（chunked、无 Range、无时长），其余直传（206 + Content-Length）；直传才有进度条拖动与真实时长。
- `just_audio` 的 `durationStream` 可能发 0，`player.dart` 已加 guard 忽略 ≤0，防止覆盖元数据时长。
- `cached_network_image` 不走自定义 http client → 已用全局 `HttpOverrides`（私有地址 DIRECT）解决。
- 沙箱内 `flutter test` 会因 HTTP_PROXY 报 "Invalid WebSocket upgrade request"，必须绕代理跑。
- Windows 构建依赖 windows/CMakeLists.txt 里的全局 `/utf-8` 和 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`（修 just_audio_windows：中文代码页 C4819→error、MSVC 14.51 的 experimental/coroutine STL1011），删了必挂。
- Android 构建：device_info_plus 9.1.2 的 compileSdk 写死 33，靠 android/build.gradle.kts 里 subprojects + afterEvaluate 反射抬到 36 才能过 AGP 9 的检查；该块必须排在 `evaluationDependsOn(":app")` 之前。`kotlin.incremental=false` 是为了绕开 Windows 上 Kotlin 增量缓存关不掉的报错。
- 锁屏/后台播放（三端机制不同，不要混）：
  - Android/iOS：`audio_service` + AndroidManifest 的 `com.ryanheise.audioservice.AudioService`（foregroundServiceType=mediaPlayback）+ `MediaButtonReceiver` + `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_MEDIA_PLAYBACK`/`WAKE_LOCK` 权限，缺任一项锁屏就停。代码在 `lib/audio/media_session.dart`，main() 里 `MfMediaSession.start()` 先于 runApp。
  - `audio_service` 与本项目都有 `PlaybackState` → media_session.dart 里 `import 'player.dart' as mf;` 隔开，别改回去。
  - 鸿蒙：module.json5 必须同时有 ability 的 `backgroundModes: ["audioPlayback"]` 和 `ohos.permission.KEEP_BACKGROUND_RUNNING`，再由 EntryAbility 通过 channel `com.seasonyuu.musicfly/background_audio` 起 `backgroundTaskManager` 长时任务（Dart 侧 `lib/audio/background_task.dart`，只在真的 playing 后申请，系统会校验 AVSession 状态）。孤立的 backgroundModes 或孤立的 startBackgroundRunning 都无效。
  - 鸿蒙媒体面板/AVSession 由 just_audio 的 ohos 分支在 ArkTS 侧创建，audio_service 在鸿蒙上没有实现，不要试图在那儿调。
  - 鸿蒙锁屏封面链路：`lib/audio/system_artwork.dart` 带 `fnRelayHeadersFor` 下载字节 → `player.dart` 的 `setMetadata` 通道 `artwork` 字段 → vendor `MediaAvPlayer.ets` 解码 PixelMap → `AVMetadata.mediaImage`。直接把 getCoverArt URL 交给系统 AVSessionService 会因缺网关 `Authorization: trim`/relay `Cookie` 而 401，锁屏无封面；`mediaImage` 传 undefined 会让整次 setAVMetadata 报 401，空串才是合法兜底。
  - Android 13+ 必须请求 `POST_NOTIFICATIONS`（manifest 声明 + 首次播放时经 channel `musicfly/notification` 请求，见 MainActivity.kt）：前台服务通知本身豁免，但暂停后服务退出前台、通知降级为普通通知，没权限就消失 —— 表现为「暂停后锁屏控制器没了，点不回去」。
  - 通知小图标必须是单色 vector（`res/drawable/ic_stat_music.xml`）并显式配 `androidNotificationIcon`，否则默认的彩色启动图标会被渲染成白方块。
  - iOS 后台播放除了 `UIBackgroundModes: audio`，还必须在启动时把 AVAudioSession 配成 playback（`lib/audio/system_audio.dart` 用 audio_session 的 `AudioSessionConfiguration.music()`），否则切后台即静音、锁屏不出 Now Playing。
  - 鸿蒙构建会把 `audio_session` override 到 pub.dev 0.2.4（无 ohos 实现），所以 `configureSystemAudio()` 必须 try/catch，鸿蒙上必然抛 MissingPluginException。

- FNID 登录的 LAN/WAN 故障切换：session.addresses 必须保存飞牛返回的**全部**候选链路（含当前网络下不可达的外网/网关/中继），不能只存当次 `reachable`；网关/中继地址需要 fnOS token，登录页「外网自动切换（可选）」可预热；已加载的播放流不会随地址切换重连。
- 连接恢复状态机（2026-11-12 重构，`lib/state/app_model.dart` + `lib/data/musicfree_client.dart`）：2 分钟常规探测 + 全离线时 3/5/10/20/30s 退避循环探测；连续 3 轮全不可达 → `reloginRequired` 把用户带到登录页（后台仍探测，网络恢复自动清除并回到首页）。`onTransportFailure` / `onAuthFailure` 是 `Future<bool> Function()` **可等待**回调，client 在探测/静默重登成功后**重放一次请求**（`_get` 的 URI 必须在闭包内构造，否则重放仍打到旧地址）。`ServerInfo.authRequired` 区分「链路通但凭据失效」与「链路不通」——一天后 JWT 过期被 ping 误判成全地址不可达、而 `_recoverFnConnect` 只刷 fnOS token 不换 Music Free token，是老版本一直连不上、只能手动重登的根因。`_reloginSilently()` 只对 `/app/` 网关链路用 `gatewayLogin(anonymous: true)` 免密换新 token；普通登录没存 app 密码，只能回登录页。`_post` 一律 `retryable: false`，登录失败不触发故障切换。
- **用户约定：FNID 地址池是内部实现，绝不暴露给用户**。`MusicFreeSession.fnConnect` 标记区分两种登录；FNID 在设置页只显示一条只读「当前连接」，不显示备用地址、不能增删改（`AppModel.addressesManaged` 拦截），只有普通登录才允许手动备用地址。旧会话靠 `looksLikeFnAddressPool()` 推断（`/app/` 网关链路 + 裸 IP 直连混合）。探测/切换仍走完整 `allAddresses`。

## 遗留事项

- 鸿蒙图标已换成 Music Free SVG 版（`ohos/*/media/{app_icon,icon}.png`，源 SVG 在 `~/Documents/code/music-free/frontend/public/logo.svg`）；iOS/Android/macOS 平台图标仍是默认图。
- 仓库目录名仍是 `FnMusic`（用户未要求改）。
- 本地库有 4 首残缺片段 + 3 个孤儿文件未清理（用户未确认）；8 组重复记录待去重。
- 「漠河舞厅 (摇滚版)」文件实际是 m4a 但扩展名 .mp3，直传后会播不出，需重命名 + rescan。
