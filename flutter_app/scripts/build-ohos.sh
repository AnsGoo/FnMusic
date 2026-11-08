#!/usr/bin/env bash
# 构建鸿蒙 HAP。需要鸿蒙版 Flutter（flutter_flutter 的 oh-* 分支）+ DevEco Studio
# 的 SDK / hvigor / ohpm / JDK 17，官方 Flutter 编不出 HAP。
#
# 用法：
#   ./scripts/build-ohos.sh              # release（未配签名则产出 unsigned 包）
#   MODE=debug ./scripts/build-ohos.sh   # debug，可直接装到模拟器
#   ./scripts/build-ohos.sh --check      # 只体检环境，不出包
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${MODE:-release}"
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    release) MODE=release ;;
    debug) MODE=debug ;;
  esac
done

fail() {
  printf '\n[✗] %s\n' "$1" >&2
  exit 1
}

note() { printf '[·] %s\n' "$1"; }

# ---- 1. Flutter 必须是鸿蒙分支 ----
# PATH 里没有的话，退回 ohos/local.properties 里记的 flutter.sdk（少一次来回折腾）
if ! command -v flutter >/dev/null 2>&1; then
  SDK_FROM_PROP="$(grep -E '^flutter\.sdk=' ohos/local.properties 2>/dev/null | cut -d= -f2-)"
  if [ -n "${SDK_FROM_PROP:-}" ] && [ -x "$SDK_FROM_PROP/bin/flutter" ]; then
    export PATH="$SDK_FROM_PROP/bin:$PATH"
    note "PATH 里没有 flutter，改用 local.properties 记录的 $SDK_FROM_PROP"
  fi
fi
command -v flutter >/dev/null 2>&1 || fail "找不到 flutter，请把鸿蒙版 flutter_flutter 的 bin 加进 PATH"
FLUTTER_BIN="$(command -v flutter)"
# head 关管道会让 flutter 吃 SIGPIPE（141），set -o pipefail 下会直接把脚本干掉，
# 所以必须 || true。CI 上 IO 慢、输出被截断的时机不同，本地不炸不代表 CI 不炸。
FLUTTER_VER="$(flutter --version 2>/dev/null | head -1 || true)"
# 鸿蒙分支的版本字符串是 "Flutter 3.47.7+ohos-0.0.1-pre"，注意是 +ohos 不是 -ohos
if ! printf '%s' "$FLUTTER_VER" | grep -q 'ohos'; then
  cat <<EOF

[!] 当前 flutter 不是鸿蒙分支：
      $FLUTTER_BIN
      $(flutter --version 2>/dev/null | head -1)

    官方 Flutter 没有 ohos target，必须改用：
      git clone -b oh-3.47.7-preview https://gitcode.com/openharmony-tpc/flutter_flutter.git
      export PATH="\$HOME/flutter_flutter/bin:\$PATH"

EOF
  [ "$CHECK_ONLY" = "1" ] || exit 1
fi

# ---- 2. DevEco SDK / JDK / hvigor ----
HWSDK="$(grep -E '^hwsdk\.dir=' ohos/local.properties 2>/dev/null | cut -d= -f2-)"
if [ -n "${HWSDK:-}" ]; then
  note "OpenHarmony SDK：$HWSDK"
else
  [ -n "${DEVECO_SDK_HOME:-}" ] || note "DEVECO_SDK_HOME 未设置，local.properties 里也没有 hwsdk.dir"
fi
command -v ohpm >/dev/null 2>&1 || note "PATH 里没有 ohpm（通常随 DevEco Studio 安装）"
command -v hvigorw >/dev/null 2>&1 || note "PATH 里没有 hvigorw"
command -v java >/dev/null 2>&1 || fail "没有 JDK，hvigor 打包和签名必须 JDK 17"
java -version 2>&1 | sed -n '1p'

if [ ! -d ohos ]; then
  fail "缺少 ohos/ 目录：请先用鸿蒙版 flutter 执行 flutter create --platforms ohos ."
fi

# ---- 2.5 flutter-hvigor-plugin：hvigorfile.ts 的第一行 import ----
# flutter 不会替你建这个链接。缺它时构建在 200ms 内失败，报
# "Cannot find module 'flutter-hvigor-plugin'"；手工补上链接后立刻跳到下一个错误。
FLUTTER_SDK="${FLUTTER_SDK:-$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)}"
PLUGIN_SRC="$FLUTTER_SDK/packages/flutter_tools/hvigor"
PLUGIN_LINK="ohos/node_modules/flutter-hvigor-plugin"
if [ -d "$PLUGIN_SRC" ]; then
  if [ ! -e "$PLUGIN_LINK" ]; then
    note "补建 $PLUGIN_LINK → $PLUGIN_SRC"
    mkdir -p ohos/node_modules
    ln -sfn "$PLUGIN_SRC" "$PLUGIN_LINK"
  fi
else
  note "flutter SDK 里找不到 packages/flutter_tools/hvigor：$PLUGIN_SRC"
fi

if [ "$CHECK_ONLY" = "1" ]; then
  note "环境体检结束（未出包）"
  note "构建日志：ohos/.hvigor/outputs/build-logs/build.log"
  flutter doctor -v 2>/dev/null | sed -n '1,40p' || true
  exit 0
fi

# ---- 2.8 鸿蒙插件 overrides ----
# ohos fork（sqflite/just_audio/shared_preferences/path_provider）只该在鸿蒙
# 构建时生效：sqflite fork 还在用官方 SDK 已删除的 v1 embedding
# （PluginRegistry.Registrar），写进 pubspec.yaml 会把 Android/iOS/macOS
# 构建全部搞挂。pubspec_overrides.yaml 是 pub 原生机制，自动叠加在
# pubspec.yaml 之上；此文件不入库，各端 CI 只在跑本脚本时才会生成它。
cat > pubspec_overrides.yaml <<'EOF'
# 由 scripts/build-ohos.sh 生成，勿手改。见 pubspec.yaml 中鸿蒙适配注释。
dependency_overrides:
  # ohos 版 just_audio 连带的 git 版 audio_session 引用 TargetPlatform.ohos
  # （仅鸿蒙 fork 有该枚举），官方 SDK 编不过。pub.dev 0.2.4 不做平台枚举
  # 判断；鸿蒙上仅损失 AVSession 系统媒体面板集成，播放不受影响。
  audio_session: 0.2.4
  just_audio:
    git:
      url: https://gitcode.com/CPF-Flutter/fluttertpc_just_audio.git
      path: just_audio
      ref: 0.10.5-ohos-1.0.0
  shared_preferences:
    git:
      url: https://atomgit.com/openharmony-tpc/flutter_packages.git
      path: packages/shared_preferences/shared_preferences
      ref: master
  path_provider:
    git:
      url: https://atomgit.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider
      ref: master
  sqflite:
    git:
      url: https://gitcode.com/openharmony-sig/flutter_sqflite.git
      path: sqflite
EOF
note "已生成 pubspec_overrides.yaml（鸿蒙插件 overrides，仅本次构建生效）"

# ---- 3. 出包 ----
# app.signingConfigs 是否非空。flutter build hap 在 hvigor 打包完之后还会查这一项，
# 空数组就 throwToolExit —— 此时 HAP 其实已经躺在 outputs 里了（unsigned）。
has_signing_config() {
  awk '
    /"signingConfigs"/ {
      rest = $0
      sub(/.*"signingConfigs"[[:space:]]*:[[:space:]]*\[/, "", rest)
      if (rest !~ /\]/) { inblock = 1; next }
      if (rest ~ /^[[:space:]]*\],?[[:space:]]*$/) { next }
      found = 1; next
    }
    inblock {
      if ($0 ~ /^[[:space:]]*\]/) { inblock = 0; next }
      if ($0 ~ /[^[:space:],]/) { found = 1 }
    }
    END { exit(found ? 0 : 1) }
  ' ohos/build-profile.json5 2>/dev/null
}

last_build_line() {
  grep -E "BUILD (FAILED|SUCCESSFUL) in" ohos/.hvigor/outputs/build-logs/build.log 2>/dev/null | tail -1
}

find_hap() {
  find ohos/entry/build -maxdepth 6 -name "*.hap" 2>/dev/null | head -1
}

dump_hvigor_errors() {
  local log="ohos/.hvigor/outputs/build-logs/build.log"
  if [ -f "$log" ]; then
    grep -E "ERROR|Error Message|BUILD FAILED" "$log" 2>/dev/null | tail -n 40 || true
    echo "----- 末尾 80 行 -----"
    tail -n 80 "$log" || true
  fi
}

build_failed() {
  echo
  local hap last
  hap="$(find_hap)"
  last="$(last_build_line)"
  # hvigor 说成功、产物也在 → flutter 只是死在后面的签名检查，不是编译失败。
  if [ -n "$hap" ] && printf '%s' "$last" | grep -q "BUILD SUCCESSFUL"; then
    note "打包本身成功：${last#*] }"
    note "HAP 已产出：$hap"
    note "flutter 是在打包之后的签名检查处退出的 —— 当前 app.signingConfigs 为空，只有 unsigned 包，装不了机"
    note "补签名：DevEco Studio 打开 ohos/ → File > Project Structure > Signing Configs"
    note "        勾选 Automatically generate signature（需登录华为账号），之后重跑本脚本即可出签名包"
    exit 0
  fi
  # 真失败：真报错在 hvigor 的 debug 日志里，flutter 只会吐 exit code 255。
  note "构建失败，正在从 hvigor 日志里提取真正的报错……"
  dump_hvigor_errors
  exit 1
}

if ! has_signing_config; then
  note "app.signingConfigs 为空：本轮只能产出 unsigned HAP（编译打包照常跑）"
fi

flutter pub get
if [ "$MODE" = "debug" ]; then
  flutter build hap --debug --target-platform ohos-arm64 || build_failed
else
  flutter build hap --release --target-platform ohos-arm64 || build_failed
fi

echo
HAP="$(find_hap)"
if [ -n "$HAP" ]; then
  note "产物：${HAP}（$(du -h "$HAP" | cut -f1)）"
  case "$HAP" in
    *unsigned*)
      # 模拟器的系统镜像不校验签名，能直接装；真机必须签名。
      note "unsigned 包：模拟器可以直接装，真机需要先在 DevEco 里配签名。" ;;
    *) note "已签名，真机/模拟器都能装。" ;;
  esac
else
  note "产物：没有找到 .hap（构建没走到打包阶段）"
  exit 1
fi
