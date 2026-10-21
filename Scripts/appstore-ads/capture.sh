#!/bin/bash
# AGY Remote App Store 营销截图抓取脚本（逐语言 × 逐场景）
# 用法: bash Scripts/appstore-ads/capture.sh <iphone|ipad> [lang ...]
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
KIND="${1:-iphone}"; shift || true
case "$KIND" in
  iphone) DEV=E9375546-4811-435D-93CB-346B8E1A38AD; SCENES=(chat approval diffs models) ;;
  ipad)   DEV=D8D75776-992B-4353-9054-826F7655CD6B; SCENES=(chat approval diffs models) ;;
  *) echo "device must be iphone|ipad"; exit 1 ;;
esac
[ -n "${ONLY:-}" ] && SCENES=($ONLY)
LANGS=("$@"); [ ${#LANGS[@]} -eq 0 ] && LANGS=(zh-Hans zh-Hant en ja ko fr de es ru pt it ar)
DD="${DERIVED_DATA:-/tmp/agy-ads-dd}"
APP="$DD/Build/Products/Debug-iphonesimulator/AntigravityRemote.app"
if [ -z "${SKIP_BUILD:-}" ]; then
  xcodebuild -project "ios-app/AntigravityRemote.xcodeproj" -scheme "AntigravityRemote" \
    -destination "platform=iOS Simulator,id=$DEV" -derivedDataPath "$DD" build >/dev/null
fi
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl bootstatus "$DEV" -b >/dev/null
xcrun simctl status_bar "$DEV" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --operatorName ""
xcrun simctl ui "$DEV" appearance light
xcrun simctl install "$DEV" "$APP"
# 预热一次确保 dyld 缓存已加载
xcrun simctl launch "$DEV" com.liling.AntigravityRemote -AGYDemoMode YES -AGYMarketingScene chat >/dev/null 2>&1 || true
sleep 3.5
locale_of() { case "$1" in zh-Hans) echo zh_CN;; zh-Hant) echo zh_TW;; en) echo en_US;; ja) echo ja_JP;; ko) echo ko_KR;;
  fr) echo fr_FR;; de) echo de_DE;; es) echo es_ES;; ru) echo ru_RU;; pt) echo pt_BR;; it) echo it_IT;; ar) echo ar_SA;; esac; }
for L in "${LANGS[@]}"; do
  OUT="$ROOT/Scripts/appstore-ads/raw/$KIND/$L"; mkdir -p "$OUT"
  for S in "${SCENES[@]}"; do
    xcrun simctl terminate "$DEV" com.liling.AntigravityRemote 2>/dev/null || true
    xcrun simctl launch "$DEV" com.liling.AntigravityRemote \
      -AGYDemoMode YES -AGYMarketingScene "$S" \
      -app_selected_language_v1 "$L" -AppleLanguages "($L)" -AppleLocale "$(locale_of "$L")" >/dev/null
    sleep 3.0
    xcrun simctl io "$DEV" screenshot "$OUT/$S.png" >/dev/null 2>&1
    echo "$KIND $L $S"
  done
done
