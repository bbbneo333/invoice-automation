#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

# Prefer the full Xcode toolchain when it is installed. The standalone Command
# Line Tools can lag behind the active macOS SDK and fail to compile manifests.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swift build -c release

# Resolve dependencies during the build. The app loads this private copy and
# never needs Bundler or a user's installed gems at runtime.
RUBYZIP_DIR="$(ruby -r ../src/backend_dependencies -e 'puts Gem.loaded_specs.fetch("rubyzip").full_gem_path')"

APP_DIR="build/InvoiceTimer.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$RESOURCES_DIR/Backend"
REPOSITORY_DIR="$(cd .. && pwd)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$BACKEND_DIR/runtime/chromium"

cp ".build/release/InvoiceTimer" "$MACOS_DIR/InvoiceTimer"

cp -R "$REPOSITORY_DIR/src" "$BACKEND_DIR/src"
mkdir -p "$BACKEND_DIR/vendor"
cp -R "$RUBYZIP_DIR" "$BACKEND_DIR/vendor/rubyzip"
cp -R "$REPOSITORY_DIR/templates" "$BACKEND_DIR/templates"
cp -R "$REPOSITORY_DIR/node_modules" "$BACKEND_DIR/node_modules"

NODE_BIN="$(node -p 'process.execPath')"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if (( NODE_MAJOR < 20 )); then
  echo "Node.js 20 or newer is required to bundle the renderer" >&2
  exit 1
fi
cp "$NODE_BIN" "$BACKEND_DIR/runtime/node"

PLAYWRIGHT_REVISION="$(node -e 'const data=require(process.argv[1]); process.stdout.write(data.browsers.find(item => item.name === "chromium-headless-shell").revision)' "$REPOSITORY_DIR/node_modules/playwright-core/browsers.json")"
PLAYWRIGHT_ROOT="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}"
CHROMIUM_DIR="$PLAYWRIGHT_ROOT/chromium_headless_shell-$PLAYWRIGHT_REVISION"
CHROMIUM_BIN="$(find "$CHROMIUM_DIR" -type f -name chrome-headless-shell -perm -111 -print -quit)"
if [[ -z "$CHROMIUM_BIN" ]]; then
  echo "Bundled Chromium is missing. Run: npm run setup:renderer" >&2
  exit 1
fi
cp -R "$(dirname "$CHROMIUM_BIN")/." "$BACKEND_DIR/runtime/chromium/"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>InvoiceTimer</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.invoiceautomation.InvoiceTimer</string>
  <key>CFBundleName</key>
  <string>InvoiceTimer</string>
  <key>CFBundleDisplayName</key>
  <string>InvoiceTimer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
