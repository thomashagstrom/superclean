#!/usr/bin/env bash
# Builds a throwaway project tree and checks what superclean removes and,
# just as important, what it refuses to touch. Run with `npm test`.
set -euo pipefail

BIN="$(cd "$(dirname "$0")/.." && pwd)/bin/superclean.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0

check() { # check <description> <test-command...>
  local desc="$1"; shift
  if "$@"; then echo "  ok    $desc"; else echo "  FAIL  $desc"; FAILS=$((FAILS + 1)); fi
}
gone()   { [ ! -e "$T/$1" ]; }
kept()   { [ -e "$T/$1" ]; }

# Expo app: everything generated goes.
mkdir -p "$T"/expo/{node_modules/react-native/ios,ios/Pods,android/app/build,build,.next/cache,.git/build}
touch "$T/expo/package.json" "$T/expo/app.json"
# Next app, with a source folder that happens to be called build.
mkdir -p "$T"/web/{node_modules,.next/cache,src/build}
touch "$T/web/package.json" "$T/web/src/build/keep.ts"
# Traps: no package.json, and a bare React Native project (not Expo managed).
mkdir -p "$T"/lib/build/node_modules "$T/bare/ios" "$T/bare/android" "$T/sp ace/node_modules"
touch "$T/lib/build/keep.ts" "$T/bare/package.json" "$T/bare/ios/keep.swift"

echo "dry run"
bash "$BIN" "$T" >/dev/null
check "deletes nothing"            kept expo/node_modules
check "deletes nothing (ios)"      kept expo/ios

echo "--yes"
bash "$BIN" "$T" --yes >/dev/null
check "expo node_modules removed"  gone expo/node_modules
check "expo ios removed"           gone expo/ios
check "expo android removed"       gone expo/android
check "expo build removed"         gone expo/build
check "expo .next removed"         gone expo/.next
check "web node_modules removed"   gone web/node_modules
check "web .next removed"          gone web/.next
check "path with a space handled"  gone "sp ace/node_modules"
check "node_modules inside an unguarded build/ still removed" gone lib/build/node_modules
check "src/build kept"             kept web/src/build/keep.ts
check "build without package.json kept" kept lib/build/keep.ts
check "bare RN ios kept"           kept bare/ios/keep.swift
check "bare RN android kept"       kept bare/android
check ".git never entered"         kept expo/.git/build

echo "rerun and bad input"
check "rerun is a no-op"           bash "$BIN" "$T" --yes
check "unknown flag rejected"      bash -c "! bash '$BIN' --bogus 2>/dev/null"
check "missing path rejected"      bash -c "! bash '$BIN' /no/such/dir 2>/dev/null"

echo "docker"
STUB="$T/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "stub docker $*" >> "%s/calls"\n' "$T" > "$STUB/docker"; chmod +x "$STUB/docker"
PATH="$STUB:$PATH" bash "$BIN" "$T" --docker >/dev/null
check "--docker alone never prunes" bash -c "! grep -q prune '$T/calls'"
PATH="$STUB:$PATH" bash "$BIN" "$T" --docker-all --yes >/dev/null
check "--docker-all --yes prunes all" grep -q 'system prune --force --all' "$T/calls"
check "volumes never pruned"       bash -c "! grep -q volume '$T/calls'"

echo
if [ "$FAILS" -gt 0 ]; then echo "$FAILS check(s) failed"; exit 1; fi
echo "all checks passed"
