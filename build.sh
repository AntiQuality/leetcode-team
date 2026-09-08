#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Never publish a binary with a knowingly unusable GitHub login.
python3 - <<'CHECK'
import json, re, sys
from pathlib import Path
config=json.loads(Path('Resources/github-app.json').read_text())
if not re.fullmatch(r'Iv[0-9A-Za-z_.-]{5,100}',config.get('clientID','')) or not re.fullmatch(r'[a-z0-9-]{1,100}',config.get('slug','')):
    sys.exit('Build stopped: maintainer GitHub App registration is missing. No release was produced.')
CHECK
APP="$PWD/LeetCode-Team.app"
CACHE="${TMPDIR:-/tmp}/LeetCode-Team-build-cache"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"
swiftc Sources/main.swift Sources/StudyPlanProgress.swift Sources/GitHubTeam.swift Sources/GitHubAppSession.swift Sources/WorkspaceChrome.swift Sources/SidebarHover.swift -o "$APP/Contents/MacOS/LeetCode-Team" -framework Cocoa -framework WebKit -module-cache-path "$CACHE" -target "$(uname -m)-apple-macosx12.0" -O
cp Resources/* "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon-Bright-v3.icns"
rm -f "$APP/Contents/Resources/github-login.command"
rm -f "$APP/Contents/Resources/server.py"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LeetCode-Team</string><key>CFBundleIdentifier</key><string>app.leetsquad.mac</string><key>CFBundleName</key><string>LeetCode-Team</string><key>CFBundleDisplayName</key><string>LeetCode-Team</string><key>CFBundleIconFile</key><string>AppIcon-Bright-v3.icns</string><key>CFBundleVersion</key><string>17</string><key>CFBundleShortVersionString</key><string>0.3.6</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>12.0</string><key>NSHighResolutionCapable</key><true/><key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
