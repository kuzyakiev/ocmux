#!/bin/zsh
# Replace the installed /Applications/ocmux.app with the latest tagged build,
# re-apply the ocmux name + orange icon, and relaunch it.
#
#   ./install-app.sh [tag]        # default tag: ocmux-verify
#
# WARNING: this QUITS the running ocmux. Every terminal inside it goes away
# (tmux sessions on remotes survive; local shells do not). Run it from a
# terminal that is NOT inside ocmux (Terminal.app, or the real cmux).
#
# Source is the raw Xcode product `cmux DEV.app`, not the `cmux DEV <tag>.app`
# copy reload.sh makes: that copy has LSEnvironment pinned to the tag's debug
# socket / localhost backend, which the everyday install must not carry.
emulate -L zsh
set -eu

tag=${1:-ocmux-verify}
bundle_id=com.cmuxterm.app.debug.${tag//-/.}
here=${0:A:h}
src=$HOME/Library/Developer/Xcode/DerivedData/cmux-$tag/Build/Products/Debug/cmux\ DEV.app
dst=/Applications/ocmux.app
log=/tmp/cmux-reload-$tag.log

[[ -d $src ]] || { print -u2 "no build at: $src"; exit 1 }
# reload.sh's exit code lies; only trust the log.
if [[ -f $log ]] && ! grep -q '\*\* BUILD SUCCEEDED \*\*' $log; then
  print -u2 "last build for $tag did not succeed (see $log); refusing to install"
  exit 1
fi
if [[ $(defaults read "$src/Contents/Info" CFBundleIdentifier) != $bundle_id ]]; then
  print -u2 "unexpected bundle id in $src (want $bundle_id)"; exit 1
fi

print "quitting $bundle_id ..."
osascript -e "tell application id \"$bundle_id\" to quit" 2>/dev/null || true
for i in {1..60}; do
  pgrep -f "$dst/Contents/MacOS/" >/dev/null || break
  sleep 0.5
done
if pgrep -f "$dst/Contents/MacOS/" >/dev/null; then
  print -u2 "ocmux did not exit after 30s (a quit-confirmation dialog?); aborting, nothing replaced"
  exit 1
fi

print "installing $src -> $dst"
rm -rf "$dst"
ditto "$src" "$dst"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ocmux" "$dst/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ocmux" "$dst/Contents/Info.plist"

# Icon + ad-hoc re-sign + LaunchServices/Dock refresh.
"$here/install-icon.sh" "$dst"

open "$dst"
print "ocmux installed from $tag ($(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$src/Contents/MacOS/cmux DEV")) and relaunched"
