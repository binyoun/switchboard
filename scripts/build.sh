#!/bin/sh
# Builds Switchboard with swiftc alone, so Xcode is not needed (Command Line Tools are enough).
# Output: .build/manual/sb
set -e
cd "$(dirname "$0")/.."
B=.build/manual
mkdir -p "$B"

swiftc -O -parse-as-library -emit-library -static -emit-module \
  -module-name SwitchboardCore -emit-module-path "$B/SwitchboardCore.swiftmodule" \
  -o "$B/libSwitchboardCore.a" Sources/SwitchboardCore/*.swift

swiftc -O -I "$B" -L "$B" -lSwitchboardCore -o "$B/sb" Sources/sb/main.swift

if [ "$1" = "test" ]; then
  swiftc -I "$B" -L "$B" -lSwitchboardCore -o "$B/selftest" Tests/selftest.swift
  "$B/selftest"
else
  echo "Built $B/sb"
fi
