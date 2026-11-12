#!/usr/bin/env bash
# 一键：构建鸿蒙 HAP → 安装到模拟器 → 拉起应用 → 还原构建对 Dart 依赖的临时改动。
#
# 用法：
#   ./scripts/deploy-ohos-emulator.sh                      # debug 构建 + 安装 + 启动
#   MODE=release ./scripts/deploy-ohos-emulator.sh        # release 构建
#   ./scripts/deploy-ohos-emulator.sh --no-build          # 用现有 HAP 直接安装（秒级）
#   ./scripts/deploy-ohos-emulator.sh --fast              # 快速迭代：保持鸿蒙依赖、增量构建（约 30s）
#   ./scripts/deploy-ohos-emulator.sh --restore           # 切回 macOS/Android 调试前还原依赖
#   ./scripts/deploy-ohos-emulator.sh -t 127.0.0.1:5555  # 指定设备
#   ./scripts/deploy-ohos-emulator.sh --check             # 只体检环境，不构建不安装
#   ./scripts/deploy-ohos-emulator.sh --help
#
# 快速模式说明：
#   完整部署每次都要「切到鸿蒙插件依赖 → pub get → 构建 → 还原 → 再 pub get」，
#   这会冲掉 hvigor 的增量缓存；而 flutter build hap 每次重生成 flutter.har，
#   又会让所有依赖它的 ArkTS 模块全量重编（实测 154s）。
#   --fast 保持鸿蒙依赖不动，且当 Dart 产物已是最新的（只改了 .ets / 资源）时
#   直接调 hvigor 增量打包，约 25–40s；若检测到 lib/ 或 pubspec.yaml 有更新，
#   才回退到 flutter build hap --no-pub 重编 Dart。代价是工作区停留在鸿蒙依赖
#   状态，切回 VS Code 调试其他平台前必须执行一次 --restore。
#
# 环境变量：
#   MODE=debug|release              构建模式，默认 debug
#   HDC_TARGET=host:port           指定设备，默认取 hdc list targets 的第一个
#   AUTO_START_EMULATOR=1|0        无在线设备时是否自动拉起模拟器，默认 1
#   EMULATOR_NAME="Mate 90 Pro"    自动拉起时的模拟器名
#   MF_EMULATOR_BIN=/path/Emulator 模拟器可执行文件（默认 DevEco Studio 内置路径）
#   NO_RESTORE=1                   保留构建产生的 pubspec_overrides.yaml 等改动
#
# 说明：
#   - unsigned HAP 只有模拟器能装（模拟器镜像不校验签名）；真机需在 DevEco 配签名。
#   - build-ohos.sh 会临时生成 pubspec_overrides.yaml 并改写 pubspec.lock、
#     macos/Flutter/GeneratedPluginRegistrant.swift。本脚本先做快照，结束（含失败 /
#     Ctrl-C）时按原样还原，再用官方 Flutter 跑 pub get 重置 .dart_tool，
#     这样 VS Code 里继续调试 macOS / Android 不会被鸿蒙插件 overrides 污染。
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$(pwd)"

MODE="${MODE:-debug}"
HDC_TARGET="${HDC_TARGET:-}"
AUTO_START_EMULATOR="${AUTO_START_EMULATOR:-1}"
EMULATOR_NAME="${EMULATOR_NAME:-Mate 90 Pro}"
MF_EMULATOR_BIN="${MF_EMULATOR_BIN:-/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator}"
NO_RESTORE="${NO_RESTORE:-0}"
NO_BUILD=0
NO_LAUNCH=0
CHECK_ONLY=0
FAST=0
RESTORE_ONLY=0
# 完整部署时把「进入鸿蒙状态之前」的依赖文件存在这里，供 --fast 之后 --restore。
# 放在 .dart_tool 下（本来就被 gitignore），不会污染工作区。
PERSIST_DIR=".dart_tool/mf-ohos-restore"

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

while [ "$#" -gt 0 ]; do
  arg="$1"; shift
  case "$arg" in
    -t|--target)
      HDC_TARGET="${1:-}"
      if [ "$#" -gt 0 ]; then shift; fi
      ;;
    -t=*|--target=*) HDC_TARGET="${arg#*=}" ;;
    --no-build) NO_BUILD=1 ;;
    --fast) FAST=1 ;;
    --restore) RESTORE_ONLY=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --no-start-emulator) AUTO_START_EMULATOR=0 ;;
    --no-restore) NO_RESTORE=1 ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    debug) MODE=debug ;;
    release) MODE=release ;;
    *) printf '[!] 未知参数：%s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

# stdout 被 head/tail 截断时 printf 会 EPIPE 失败；不能让它触发 errexit 中断清理。
note()  { printf '[·] %s\n' "$*" || true; }
ok()    { printf '[✓] %s\n' "$*" || true; }
warn()  { printf '[!] %s\n' "$*" >&2 || true; }
fail()  { printf '\n[✗] %s\n' "$*" >&2 || true; exit 1; }

# ---- 工具定位 ----
HDC="$(command -v hdc || true)"
if [ -z "$HDC" ]; then
  for c in /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc \
           "$HOME/Library/OpenHarmony/Sdk/default/openharmony/toolchains/hdc"; do
    [ -x "$c" ] && { HDC="$c"; break; }
  done
fi
[ -n "$HDC" ] || fail "找不到 hdc，请把 DevEco Studio 的 toolchains 目录加进 PATH"

json_string() { # <file> <key>
  [ -f "$1" ] || return 0
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1
}
BUNDLE="$(json_string ohos/AppScope/app.json5 bundleName)"
BUNDLE="${BUNDLE:-com.seasonyuu.musicfly}"
ABILITY="$(json_string ohos/entry/src/main/module.json5 mainElement)"
ABILITY="${ABILITY:-EntryAbility}"

first_target() {
  "$HDC" list targets 2>/dev/null | awk 'NF && $1 !~ /^\[/ && $0 !~ /Empty/ {print $1; exit}'
}
find_hap() { find ohos/entry/build -maxdepth 6 -name "*.hap" -type f 2>/dev/null | head -1; }

# ---- 依赖快照（必须在任何构建动作之前）----
SNAPSHOT_DIR=""
_CLEANED=0
NEEDS_CLEANUP=0   # 只有真正跑过构建才需要还原依赖
SIDE_EFFECT_FILES=(
  "pubspec_overrides.yaml"
  "pubspec.lock"
  "macos/Flutter/GeneratedPluginRegistrant.swift"
)

# 上一次构建被强杀（超时 / 关终端）时可能留下带生成标记的 overrides。
# 它不入库、git status 看不见，却会让 macOS 调试一直加载鸿蒙插件，先自愈清掉。
purge_stale_overrides() {
  local f="pubspec_overrides.yaml"
  if [ -f "$f" ] && grep -q '由 scripts/build-ohos.sh 生成' "$f" 2>/dev/null; then
    note "清理上次中断残留的 $f"
    rm -f "$f" || warn "清理 $f 失败，请手动删除"
  fi
  if grep -q 'atomgit.com\|openharmony-sig' pubspec.lock 2>/dev/null; then
    warn "pubspec.lock 里已有鸿蒙 git 依赖，疑似上次中断未还原；"
    warn "如 macOS 调试报插件错误，请执行：git restore flutter_app/pubspec.lock"
  fi
}

snapshot_workspace() {
  SNAPSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mf-ohos-deploy.XXXXXX")"
  : > "$SNAPSHOT_DIR/manifest"
  local rel
  for rel in "${SIDE_EFFECT_FILES[@]}"; do
    if [ -e "$rel" ]; then
      mkdir -p "$SNAPSHOT_DIR/$(dirname "$rel")"
      cp -p "$rel" "$SNAPSHOT_DIR/$rel"
      printf 'had %s\n' "$rel" >> "$SNAPSHOT_DIR/manifest"
    else
      printf 'new %s\n' "$rel" >> "$SNAPSHOT_DIR/manifest"
    fi
  done
  # 用于判断本轮是否真的产出了新 HAP
  touch "$SNAPSHOT_DIR/stamp"
  NEEDS_CLEANUP=1
  persist_snapshot
}

# 把「鸿蒙状态之前」的原始文件另存一份，--fast 之后可用 --restore 找回。
persist_snapshot() {
  local dir="$PERSIST_DIR" state rel
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$SNAPSHOT_DIR/manifest" "$dir/manifest"
  while read -r state rel; do
    [ "$state" = "had" ] || continue
    mkdir -p "$dir/$(dirname "$rel")"
    cp -p "$SNAPSHOT_DIR/$rel" "$dir/$rel" || warn "未能保存快照 $rel"
  done < "$SNAPSHOT_DIR/manifest"
}

restore_from_dir() {
  local dir="$1" state rel
  [ -f "$dir/manifest" ] || return 0
  while read -r state rel; do
    [ -n "${rel:-}" ] || continue
    case "$state" in
      had)
        mkdir -p "$(dirname "$rel")"
        cp -p "$dir/$rel" "$rel" || warn "未能还原 $rel"
        ;;
      new)
        rm -f "$rel" || warn "未能删除临时生成的 $rel"
        ;;
    esac
  done < "$dir/manifest"
}

restore_files() {
  [ -n "$SNAPSHOT_DIR" ] && [ -f "$SNAPSHOT_DIR/manifest" ] || return 0
  restore_from_dir "$SNAPSHOT_DIR"
}

# 切回 macOS / Android 调试：还原依赖文件并用官方 Flutter 重置 .dart_tool。
restore_only() {
  if [ ! -f "$PERSIST_DIR/manifest" ]; then
    # 兼容「脚本升级前就停在鸿蒙状态」的情况：这两个文件本来就是 pub 自动生成的，
    # 用仓库 HEAD 版本当基准即可。
    warn "没有持久化快照，改用 git HEAD 版本还原（pub 自动生成的文件）"
    mkdir -p "$PERSIST_DIR/macos/Flutter"
    : > "$PERSIST_DIR/manifest"
    for rel in pubspec.lock macos/Flutter/GeneratedPluginRegistrant.swift; do
      if git -C .. show "HEAD:flutter_app/$rel" > "$PERSIST_DIR/$rel" 2>/dev/null; then
        printf 'had %s\n' "$rel" >> "$PERSIST_DIR/manifest"
      fi
    done
    printf 'new pubspec_overrides.yaml\n' >> "$PERSIST_DIR/manifest"
    [ "$(wc -l < "$PERSIST_DIR/manifest" | tr -d ' ')" -gt 1 ] \
      || fail "git HEAD 里也找不到依赖文件，请手动执行 git restore flutter_app/pubspec.lock"
  fi
  note "从快照还原依赖文件"
  restore_from_dir "$PERSIST_DIR"
  run_official_pub_get || true
  # pub get 也可能重写 lock / plugin registrant，再按快照盖回原样
  restore_from_dir "$PERSIST_DIR"
  rm -rf "$PERSIST_DIR"
  ok "依赖已还原到 macOS / Android 状态，可以继续用 VS Code 调试"
}

run_official_pub_get() {
  local fbin="" c ver
  for c in "$HOME/development/flutter/bin/flutter" "$HOME/flutter/bin/flutter"; do
    if [ -x "$c" ]; then
      ver="$("$c" --version 2>/dev/null | head -1 || true)"
      printf '%s' "$ver" | grep -q 'ohos' && continue
      fbin="$c"; break
    fi
  done
  if [ -z "$fbin" ] && command -v flutter >/dev/null 2>&1; then
    ver="$(flutter --version 2>/dev/null | head -1 || true)"
    printf '%s' "$ver" | grep -q 'ohos' || fbin="$(command -v flutter)"
  fi
  if [ -z "$fbin" ]; then
    warn "没找到官方 Flutter SDK，跳过 pub get；调试其他平台前请手动跑一次 flutter pub get"
    return 0
  fi
  note "用官方 Flutter 重置依赖：flutter pub get"
  local log="${TMPDIR:-/tmp}/mf-ohos-deploy-pubget.log"
  if ! env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY \
       NO_PROXY=127.0.0.1,localhost "$fbin" pub get >"$log" 2>&1; then
    warn "pub get 失败（日志：${log}），请手动执行一次 flutter pub get"
    tail -n 12 "$log" >&2 || true
  fi
}

cleanup() {
  local rc="${1:-0}"
  [ "$_CLEANED" = "1" ] && return 0
  _CLEANED=1
  if [ "$NEEDS_CLEANUP" = "0" ]; then
    : # 没跑过构建（--help / --check / --no-build / 早退），依赖从未被改动
  elif [ "$NO_RESTORE" = "1" ]; then
    note "按要求保留构建产生的依赖改动（NO_RESTORE=1）"
  else
    restore_files
    run_official_pub_get || true
    # pub get 本身也可能重写 lock / plugin registrant，再按快照盖回原样
    restore_files
  fi
  if [ -n "$SNAPSHOT_DIR" ] && [ -d "$SNAPSHOT_DIR" ]; then
    rm -rf "$SNAPSHOT_DIR"
  fi
  if [ "${rc:-0}" -ne 0 ]; then
    warn "部署未完成（exit ${rc}），工作区已尽量还原"
  fi
  # 不要 return 0：EXIT trap 的返回值会成为脚本最终退出码，抹掉真实失败状态。
  return "${rc:-0}"
}
trap 'cleanup $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- 环境体检 ----
if [ "$CHECK_ONLY" = "1" ]; then
  note "hdc：$HDC"
  note "Flutter（鸿蒙分支）：$(grep -E '^flutter\.sdk=' ohos/local.properties 2>/dev/null | cut -d= -f2- || echo 未配置)"
  note "包名 / Ability：$BUNDLE / $ABILITY"
  note "在线设备：$(first_target || echo 无)"
  note "模拟器可执行文件：$([ -x "$MF_EMULATOR_BIN" ] && echo 存在 || echo 未找到) $MF_EMULATOR_BIN"
  note "现有 HAP：$(find_hap || echo 无)"
  exit 0
fi

if [ "$RESTORE_ONLY" = "1" ]; then
  restore_only
  exit 0
fi

[ -f scripts/build-ohos.sh ] || fail "缺少 scripts/build-ohos.sh"
[ -d ohos ] || fail "缺少 ohos/ 目录"

if [ "$FAST" = "1" ]; then
  # 快速模式的前提：工作区已经停在鸿蒙依赖状态，且 .dart_tool 解析到 vendor 插件。
  [ -f pubspec_overrides.yaml ] || fail "--fast 需要鸿蒙依赖状态，请先完整部署一次（不带 --fast）"
  grep -Eq 'atomgit\.com|gitcode\.com/openharmony|gitee\.com/openharmony' pubspec.lock \
    || fail "pubspec.lock 不是鸿蒙依赖状态，请先完整部署一次"
  [ -f "$PERSIST_DIR/manifest" ] \
    || warn "没有持久化快照，之后无法用 --restore 自动还原；建议先完整部署一次"
  note "快速模式：保持鸿蒙依赖，跳过 pub get 与收尾还原（hvigor 增量缓存生效）"
fi

# ---- 1. 确保模拟器在线 ----
TARGET="$HDC_TARGET"
if [ -z "$TARGET" ]; then
  TARGET="$(first_target || true)"
fi
if [ -z "$TARGET" ]; then
  if [ "$AUTO_START_EMULATOR" != "1" ]; then
    fail "没有在线设备。请启动 DevEco 模拟器，或用 -t <host:port> 指定目标"
  fi
  [ -x "$MF_EMULATOR_BIN" ] || fail "模拟器不可执行：${MF_EMULATOR_BIN}（可用 MF_EMULATOR_BIN 指定）"
  note "没有在线设备，正在启动模拟器「${EMULATOR_NAME}」……"
  "$HDC" start >/dev/null 2>&1 || true
  nohup "$MF_EMULATOR_BIN" -hvd "$EMULATOR_NAME" \
    >"${TMPDIR:-/tmp}/mf-ohos-emulator.log" 2>&1 &
  i=0
  while [ -z "$TARGET" ] && [ "$i" -lt 60 ]; do
    sleep 2
    i=$((i + 1))
    TARGET="$(first_target || true)"
  done
fi
[ -n "$TARGET" ] || fail "等待 120 秒后设备仍未上线（日志：${TMPDIR:-/tmp}/mf-ohos-emulator.log）"
if ! "$HDC" -t "$TARGET" shell "echo __MF_OK__" 2>/dev/null | grep -q '__MF_OK__'; then
  fail "设备 $TARGET 无法执行 shell，请检查 hdc 连接"
fi
ok "设备在线：${TARGET}（${BUNDLE} / ${ABILITY}）"

# ---- 2. 打包 ----
BUILD_LOG="${TMPDIR:-/tmp}/mf-ohos-deploy-build.log"
HAP=""
if [ "$NO_BUILD" = "1" ]; then
  HAP="$(find_hap || true)"
  [ -n "$HAP" ] || fail "--no-build 但没有找到任何 .hap，请先完整构建一次"
  note "跳过构建，使用现有产物：$HAP"
elif [ "$FAST" = "1" ]; then
  FAST_STAMP="${TMPDIR:-/tmp}/mf-ohos-fast.stamp"
  : > "$FAST_STAMP"
  KERNEL="ohos/entry/src/main/resources/rawfile/flutter_assets/kernel_blob.bin"
  DART_STALE=0
  if [ "$MODE" != "debug" ] || [ ! -f "$KERNEL" ]; then
    DART_STALE=1
  elif [ -n "$(find lib -name '*.dart' -newer "$KERNEL" 2>/dev/null | head -1)" ] \
    || [ pubspec.yaml -nt "$KERNEL" ]; then
    DART_STALE=1
  fi
  if [ "$DART_STALE" = "0" ]; then
    # 只改了 .ets / 资源：flutter.har 不用重生成，hvigor 增量能保住。
    HVIGORW="$(command -v hvigorw || true)"
    for c in "$HOME/Documents/command-line-tools/bin/hvigorw" \
             "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw"; do
      [ -n "$HVIGORW" ] && break
      [ -x "$c" ] && HVIGORW="$c"
    done
    [ -n "$HVIGORW" ] || fail "找不到 hvigorw，请把 DevEco 的 hvigor/bin 加进 PATH"
    note "Dart 产物已是最新：直接 hvigor 增量打包（跳过 Dart 编译与 pub get）"
    set +e
    ( cd ohos && "$HVIGORW" assembleHap -p product=default -p buildMode="$MODE" ) 2>&1 | tee "$BUILD_LOG"
    BUILD_RC="${PIPESTATUS[0]}"
    set -e
    [ "$BUILD_RC" -eq 0 ] || {
      tail -n 40 "$BUILD_LOG" >&2 || true
      fail "hvigor 构建失败（exit ${BUILD_RC}），详见 ${BUILD_LOG}"
    }
  else
    OHOS_FLUTTER="$(grep -E '^flutter\.sdk=' ohos/local.properties | cut -d= -f2-)/bin/flutter"
    [ -x "$OHOS_FLUTTER" ] || fail "找不到鸿蒙版 Flutter：${OHOS_FLUTTER}"
    note "检测到 Dart / pubspec 变化：flutter build hap --${MODE} --no-pub（需重编 Dart，较慢）"
    set +e
    PATH="$(dirname "$OHOS_FLUTTER"):$PATH" "$OHOS_FLUTTER" build hap "--${MODE}" \
      --target-platform ohos-arm64 --no-pub 2>&1 | tee "$BUILD_LOG"
    BUILD_RC="${PIPESTATUS[0]}"
    set -e
    FRESH_HAP="$(find ohos/entry/build -maxdepth 6 -name '*.hap' -type f \
      -newer "$FAST_STAMP" 2>/dev/null | head -1 || true)"
    if [ "$BUILD_RC" -ne 0 ]; then
      if [ -n "$FRESH_HAP" ] && grep -q 'BUILD SUCCESSFUL' ohos/.hvigor/outputs/build-logs/build.log 2>/dev/null; then
        note "flutter 在末尾签名检查处退出（unsigned 包已产出），继续安装"
      else
        tail -n 40 "$BUILD_LOG" >&2 || true
        fail "快速构建失败（exit ${BUILD_RC}），详见 ${BUILD_LOG}"
      fi
    fi
  fi
  FRESH_HAP="$(find ohos/entry/build -maxdepth 6 -name '*.hap' -type f \
    -newer "$FAST_STAMP" 2>/dev/null | head -1 || true)"
  HAP="$FRESH_HAP"
  if [ -z "$HAP" ]; then
    HAP="$(find_hap || true)"
    [ -n "$HAP" ] || fail "构建结束但找不到 .hap 产物"
    warn "HAP 时间戳未更新（hvigor 全部 up-to-date），仍继续安装：$HAP"
  fi
  ok "产物：${HAP}（$(du -h "$HAP" | cut -f1)）"
else
  purge_stale_overrides
  snapshot_workspace
  note "开始 $MODE 构建（约 1–2 分钟），实时日志：$BUILD_LOG"
  set +e
  MODE="$MODE" ./scripts/build-ohos.sh 2>&1 | tee "$BUILD_LOG"
  BUILD_RC="${PIPESTATUS[0]}"
  set -e
  if [ "$BUILD_RC" -ne 0 ]; then
    printf '\n----- 构建日志末尾 60 行 -----\n' >&2
    tail -n 60 "$BUILD_LOG" >&2 || true
    fail "构建失败（exit ${BUILD_RC}），详见 $BUILD_LOG"
  fi
  # build-ohos.sh 在没有签名配置时会以 0 退出，但 unsigned HAP 已经产出
  FRESH_HAP="$(find ohos/entry/build -maxdepth 6 -name '*.hap' -type f \
    -newer "$SNAPSHOT_DIR/stamp" 2>/dev/null | head -1 || true)"
  HAP="$FRESH_HAP"
  if [ -z "$HAP" ]; then
    HAP="$(find_hap || true)"
    [ -n "$HAP" ] || fail "构建结束但找不到 .hap 产物"
    warn "HAP 时间戳未更新（hvigor 增量构建可能复用了旧包），仍继续安装：$HAP"
  fi
  ok "产物：$(cd "$(dirname "$HAP")" && pwd)/$(basename "$HAP")（$(du -h "$HAP" | cut -f1)）"
  case "$HAP" in
    *unsigned*) note "unsigned 包：模拟器可直接装，真机需先在 DevEco 里配签名" ;;
  esac
fi

# ---- 3. 安装 ----
note "安装到 $TARGET ……"
INSTALL_OUT="$("$HDC" -t "$TARGET" install -r "$APP_DIR/$HAP" 2>&1)" || {
  printf '%s\n' "$INSTALL_OUT" >&2
  fail "hdc install 失败"
}
printf '%s\n' "$INSTALL_OUT" | tail -n 5
printf '%s' "$INSTALL_OUT" | grep -qi 'success' || fail "hdc install 未返回成功：$INSTALL_OUT"
ok "安装完成"
case "$HAP" in
  *unsigned*) note "构建脚本里那句「装不了机」只针对真机；模拟器不校验签名，上面已装好" ;;
esac

# ---- 4. 拉起应用 ----
if [ "$NO_LAUNCH" = "1" ]; then
  note "按 --no-launch 跳过启动"
else
  "$HDC" -t "$TARGET" shell "aa force-stop $BUNDLE" >/dev/null 2>&1 || true
  START_OUT="$("$HDC" -t "$TARGET" shell "aa start -a $ABILITY -b $BUNDLE" 2>&1 || true)"
  printf '%s\n' "$START_OUT" | tail -n 3
  printf '%s' "$START_OUT" | grep -qi 'success' || warn "启动命令未返回 success，请检查 Ability 名或应用日志"
  sleep 1
  PID="$("$HDC" -t "$TARGET" shell "pidof $BUNDLE" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}' || true)"
  if [ -n "$PID" ]; then
    ok "应用已运行，pid=$PID"
  else
    warn "未查到应用进程，可能仍在启动；可用 hdc -t $TARGET shell \"pidof $BUNDLE\" 复查"
  fi
fi

printf '\n'
ok "全部完成：$BUNDLE 已部署到 $TARGET"
note "需要时手动拉起：hdc -t $TARGET shell \"aa start -a $ABILITY -b $BUNDLE\""
if [ "$FAST" = "1" ]; then
  note "工作区仍在鸿蒙依赖状态；切回 VS Code 调试其他平台前执行：./scripts/deploy-ohos-emulator.sh --restore"
fi
