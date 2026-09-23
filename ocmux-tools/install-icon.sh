#!/bin/zsh
# Give the installed ocmux.app a distinct icon so it is not confused with cmux
# in the Dock: same mark, hue-rotated 160 degrees (blue chevron -> orange).
#
#   ./install-icon.sh [/Applications/ocmux.app]
#
# Regenerate the .icns from a different app build with:
#   iconutil -c iconset <app>/Contents/Resources/AppIcon-Debug.icns -o orig.iconset
#   swiftc -O -o recolor recolor-icon.swift
#   ./recolor orig.iconset/<each>.png out.iconset/<each>.png 160 1.1
#   iconutil -c icns out.iconset -o AppIcon-ocmux.icns
emulate -L zsh
set -eu
app=${1:-/Applications/ocmux.app}
here=${0:A:h}

[[ -d $app ]] || { print -u2 "no such app: $app"; exit 1 }
[[ -f $here/AppIcon-ocmux.icns ]] || { print -u2 "missing $here/AppIcon-ocmux.icns"; exit 1 }

osascript -e 'tell application "ocmux" to quit' 2>/dev/null || true
pkill -f "$app" 2>/dev/null || true

cp "$here/AppIcon-ocmux.icns" "$app/Contents/Resources/AppIcon-Debug.icns"
codesign --force --deep --sign - "$app"
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" 2>/dev/null || true
killall Dock 2>/dev/null || true
print "installed ocmux icon into $app"
