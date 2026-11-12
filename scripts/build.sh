#!/bin/sh
# Builds Switchboard with swiftc alone, so Xcode is not needed (Command Line Tools are enough).
#
#   scripts/build.sh          .build/manual/sb and .build/Switchboard.app
#   scripts/build.sh test     also builds and runs the self-checks
#   scripts/build.sh install  also copies the app to ~/Applications and sb to /usr/local/bin
set -e
cd "$(dirname "$0")/.."
B=.build/manual
APP=.build/Switchboard.app
mkdir -p "$B"

swiftc -O -parse-as-library -emit-library -static -emit-module \
  -module-name SwitchboardCore -emit-module-path "$B/SwitchboardCore.swiftmodule" \
  -o "$B/libSwitchboardCore.a" Sources/SwitchboardCore/*.swift

swiftc -O -I "$B" -L "$B" -lSwitchboardCore -o "$B/sb" Sources/sb/main.swift

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp App/Info.plist "$APP/Contents/Info.plist"
swiftc -O -I "$B" -L "$B" -lSwitchboardCore -module-name Switchboard \
  -o "$APP/Contents/MacOS/Switchboard" Sources/Switchboard/*.swift
codesign --force --sign - "$APP" 2>/dev/null   # ad-hoc signature so macOS will run it

case "$1" in
  test)
    swiftc -I "$B" -L "$B" -lSwitchboardCore -o "$B/selftest" Tests/selftest.swift
    "$B/selftest"
    ;;
  install)
    mkdir -p ~/Applications
    pkill -x Switchboard 2>/dev/null || true
    rm -rf ~/Applications/Switchboard.app
    cp -R "$APP" ~/Applications/
    # Tell Launch Services about the new copy so it can be chosen as the default browser.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -f ~/Applications/Switchboard.app
    if [ -w /usr/local/bin ]; then cp "$B/sb" /usr/local/bin/sb; echo "Installed sb to /usr/local/bin"; fi
    echo "Installed ~/Applications/Switchboard.app"
    open ~/Applications/Switchboard.app
    ;;
  *)
    echo "Built $B/sb and $APP"
    ;;
esac
