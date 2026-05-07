#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacHub"
BUNDLE_ID="com.local.MacHub"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_BUNDLE="/Applications/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCES="$APP_CONTENTS/Resources"
ICONSET="$DIST_DIR/MacHub.iconset"
ICON_FILE="$RESOURCES/MacHub.icns"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ALLOW_ADHOC_FALLBACK="${ALLOW_ADHOC_FALLBACK:-0}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(/usr/bin/security find-identity -p codesigning -v 2>/dev/null | /usr/bin/awk -F '"' '/Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

build_icon() {
  local svg="$ROOT_DIR/Assets/MacHubIcon.svg"
  local png1024="$DIST_DIR/MacHubIcon-1024.png"

  if [[ ! -f "$svg" ]]; then
    return
  fi

  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  /usr/bin/qlmanage -t -s 1024 -o "$DIST_DIR" "$svg" >/dev/null 2>&1 || true
  if [[ -f "$DIST_DIR/MacHubIcon.svg.png" ]]; then
    mv "$DIST_DIR/MacHubIcon.svg.png" "$png1024"
  fi

  if [[ ! -f "$png1024" ]]; then
    return
  fi

  /usr/bin/sips -z 16 16 "$png1024" --out "$ICONSET/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$png1024" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$png1024" --out "$ICONSET/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$png1024" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$png1024" --out "$ICONSET/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$png1024" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$png1024" --out "$ICONSET/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$png1024" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$png1024" --out "$ICONSET/icon_512x512.png" >/dev/null
  cp "$png1024" "$ICONSET/icon_512x512@2x.png"
  /usr/bin/iconutil -c icns "$ICONSET" -o "$ICON_FILE"
}

build_icon

sign_app() {
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - "$APP_BUNDLE"
    return
  fi

  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE" &
  local sign_pid=$!
  for _ in {1..30}; do
    if ! /bin/kill -0 "$sign_pid" >/dev/null 2>&1; then
      wait "$sign_pid"
      return
    fi
    sleep 1
  done

  /bin/kill "$sign_pid" >/dev/null 2>&1 || true
  wait "$sign_pid" >/dev/null 2>&1 || true
  if [[ "$ALLOW_ADHOC_FALLBACK" != "1" ]]; then
    echo "error: signing with '$SIGN_IDENTITY' timed out." >&2
    echo "Unlock the signing key in Keychain Access, or run with SIGN_IDENTITY=- only for throwaway local builds." >&2
    return 1
  fi
  echo "warning: signing with '$SIGN_IDENTITY' timed out; falling back to ad-hoc signing." >&2
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
}

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>MacHub</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

sign_app

open_app() {
  install_app
  /usr/bin/open "$INSTALL_BUNDLE"
}

install_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$INSTALL_BUNDLE"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"
}

case "$MODE" in
  --stage|stage)
    ;;
  --install|install)
    install_app
    ;;
  --install-run|install-run)
    install_app
    /usr/bin/open "$INSTALL_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--stage|--install|--install-run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
