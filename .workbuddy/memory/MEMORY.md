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

## 遗留事项

- 应用图标仍是旧图形，需 1024×1024 新图。
- 仓库目录名仍是 `FnMusic`（用户未要求改）。
- 本地库有 4 首残缺片段 + 3 个孤儿文件未清理（用户未确认）；8 组重复记录待去重。
- 「漠河舞厅 (摇滚版)」文件实际是 m4a 但扩展名 .mp3，直传后会播不出，需重命名 + rescan。
