# MusicFly · 乐记

一个 Music Free 客户端，用 Flutter 编写，面向 macOS、Windows、Android 和 iOS。
连接自己的 Music Free 服务端（兼容 Navidrome / Subsonic），浏览曲库、专辑、艺术家和歌单，播放音乐并显示歌词。

- 英文名 **MusicFly**：包名、可执行文件、安装包与仓库标识都用这个名字。
- 中文名 **乐记**：界面里显示的名字。

## 功能

- **连接自己的服务端**：填地址、账号、密码即可登录，会话保存在本地，下次打开直接进库。
- **浏览**：歌曲 / 专辑 / 艺术家 / 歌单 / 收藏五个分区，列表滚动到底自动翻页，每行带专辑封面。
- **搜索**：按关键词搜索歌曲，结果可直接进队列。
- **播放**：队列上下首、拖动进度、音量，播放结束自动续下一首；坏源自动跳过并说明原因。
- **后台播放**：锁屏、切后台、拔耳机继续播。Android 走 `audio_service` 的前台服务 + MediaSession（通知栏/锁屏/蓝牙按键可控制，含封面；Android 13+ 首次播放会请求通知权限，拒绝的话暂停后锁屏控制器会消失）；iOS 需 `UIBackgroundModes: audio`；鸿蒙声明 `audioPlayback` 长时任务，媒体面板由 just_audio ohos 分支的 AVSession 提供，锁屏封面由 App 带网关鉴权头下载字节、原生解码成 PixelMap 后下发（系统服务自己去取封面 URL 会 401）。
- **歌词**：读取服务端内嵌歌词，LRC 逐行高亮并跟随播放位置。

## 目录

```
flutter_app/     Flutter 工程（应用本体）
  lib/data       模型、Music Free HTTP 客户端、会话持久化
  lib/audio      just_audio 封装，不含队列逻辑
  lib/state      AppModel：导航、列表、队列、歌词
  lib/ui         主题、控件、各页面
scripts/         打包脚本
dist/            产物（DMG 等）
```

## 构建与运行

```sh
cd flutter_app
flutter pub get
flutter run -d macos          # 或 windows
flutter test                  # 单元测试
```

VS Code 里打开仓库根目录，在运行面板选 **MusicFly (Windows)** 后 F5 即可调试 Windows 桌面版（`debug` 模式，支持热重载）。本机 Flutter SDK 不在 PATH 时，SDK 路径由 `.vscode/settings.json` 的 `dart.flutterSdkPath` 指定，该文件只在本机生效、不入库。

## 连接与地址自动切换

**普通登录**可在「设置 → 服务器」里添加多个备用地址（可删除、手动探测）；App 每 2 分钟探测一次并优选延迟最低的地址（局域网与外网同时可达时走局域网），请求失败时会立即重新探测。

**FNID 登录**会把飞牛解析出的**全部**链路（内网 IP、公网 IPv4/IPv6、统一网关、中继域名）保存为**内部故障切换池**，即使某条链路在当前网络下不可达也不丢弃：在家走内网，离开内网后自动切到公网 / 网关 / 中继。这些地址由飞牛提供、由应用自行切换，因此设置页只显示当前连接的一条只读地址，不显示备用地址，也不允许增删。统一网关与中继链路需要飞牛会话令牌，可在 FNID 第一步展开「外网自动切换（可选）」填一次飞牛账号预先获取；不填时依赖已缓存的令牌或公网直连地址。

连接真实服务端的集成测试需要提供地址：

```sh
MUSICFLY_TEST_SERVER=http://192.168.1.10:4533 \
MUSICFLY_TEST_USER=admin MUSICFLY_TEST_PASSWORD=admin \
flutter test test/live_backend_test.dart
```

## 打包 macOS

```sh
./scripts/package_macos.sh
```

生成 `dist/MusicFly-<version>-macos.dmg`。应用为 ad-hoc 签名，拷贝到其他机器后首次打开需右键 → 打开。

## 打包 Windows

```sh
./scripts/package_windows.sh
```

生成两个产物：

- `dist/MusicFly-<version>-windows-x64-setup.exe` —— 安装包，双击安装（装到当前用户目录，不需要管理员权限），带开始菜单项、可选桌面快捷方式和卸载程序，界面中英文可选。
- `dist/MusicFly-<version>-windows-x64.zip` —— 免安装版，解压后运行 `MusicFly/musicfly.exe`。

版本号默认取自 `pubspec.yaml`，可用 `VERSION=x.y.z` 覆盖；`NO_ZIP=1` 只出安装包，`NO_INSTALLER=1` 只出 zip。需要在装有 Visual Studio（含「使用 C++ 的桌面开发」工作负载）和 [Inno Setup 6](https://jrsoftware.org/isdl.php) 第 6.3 版以上（`winget install JRSoftware.InnoSetup`）的机器上构建，安装包定义在 `scripts/musicfly.iss`。

Release 流水线（`.github/workflows/release.yml`）的 `windows` job 会在 Windows runner 上跑同一个脚本，推送 `v*` 标签或发布 Release 后，这两个文件会作为资产挂到对应 Release。

## 授权

MusicFly 原创代码和文档采用 [Apache License 2.0](LICENSE)，适用范围见[授权范围说明](LICENSE-SCOPE.md)。
项目非官方客户端，与 Music Free、Navidrome 均无关联。
