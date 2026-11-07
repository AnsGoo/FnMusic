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

## 授权

MusicFly 原创代码和文档采用 [Apache License 2.0](LICENSE)，适用范围见[授权范围说明](LICENSE-SCOPE.md)。
项目非官方客户端，与 Music Free、Navidrome 均无关联。
