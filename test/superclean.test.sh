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
check "unknown flag rejected"      bash -c "! bash '$BIN' '$T' --bogus 2>/dev/null"
check "missing path rejected"      bash -c "! bash '$BIN' /no/such/dir 2>/dev/null"

echo "target path is required"
mkdir -p "$T/cwd/node_modules"; touch "$T/cwd/package.json"
check "no arguments rejected"      bash -c "cd '$T/cwd' && ! bash '$BIN' 2>/dev/null"
check "--yes without a path rejected" bash -c "cd '$T/cwd' && ! bash '$BIN' --yes 2>/dev/null"
check "…and deleted nothing"       kept cwd/node_modules
check "flag before the path rejected" bash -c "! bash '$BIN' --yes '$T/cwd' 2>/dev/null"
check "…and deleted nothing (flag first)" kept cwd/node_modules
check "second path rejected"       bash -c "! bash '$BIN' '$T/cwd' '$T/web' 2>/dev/null"
check "--help works without a path" bash -c "bash '$BIN' --help >/dev/null"
# npm sets INIT_CWD (where you ran npm); a plain shell doesn't. Control it explicitly.
mkdir -p "$T/rel1/node_modules" "$T/rel2/node_modules"; touch "$T/rel1/package.json" "$T/rel2/package.json"
check "relative path resolves from cwd"  bash -c "cd '$T' && env -u INIT_CWD bash '$BIN' rel1 --yes >/dev/null"
check "…and deleted it"            gone rel1/node_modules
check "relative path resolves from npm's INIT_CWD" bash -c "cd / && INIT_CWD='$T' bash '$BIN' rel2 --yes >/dev/null"
check "…and deleted it (INIT_CWD)" gone rel2/node_modules
check "'.' works as an explicit path" bash -c "cd '$T/cwd' && env -u INIT_CWD bash '$BIN' . >/dev/null"

echo "docker"
STUB="$T/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "stub docker $*" >> "%s/calls"\n' "$T" > "$STUB/docker"; chmod +x "$STUB/docker"
PATH="$STUB:$PATH" bash "$BIN" "$T" --docker >/dev/null
check "--docker alone never prunes" bash -c "! grep -q prune '$T/calls'"
PATH="$STUB:$PATH" bash "$BIN" "$T" --docker-all --yes >/dev/null
check "--docker-all --yes prunes all" grep -q 'system prune --force --all' "$T/calls"
check "volumes never pruned"       bash -c "! grep -q volume '$T/calls'"

# Every documented npm script, run exactly as the README shows them. npm appends the
# path after the script, so this guards against the path ending up behind a flag.
echo "npm scripts (as documented in the README)"
REPO="$(cd "$(dirname "$BIN")/.." && pwd)"
mk() { rm -rf "$T/n"; mkdir -p "$T/n/app/node_modules" "$T/n/sp ace/node_modules"; touch "$T/n/app/package.json" "$T/n/sp ace/package.json"; : > "$T/calls"; }
npmrun() { (cd "$REPO" && PATH="$STUB:$PATH" npm run -s "$@" 2>&1); }
mk; check "clean: dry run"            bash -c "$(declare -f npmrun); STUB='$STUB' REPO='$REPO' npmrun clean -- '$T/n' >/dev/null"
check "…deleted nothing"             kept n/app/node_modules
check "clean:yes: deletes"           bash -c "$(declare -f npmrun); STUB='$STUB' REPO='$REPO' npmrun clean:yes -- '$T/n' >/dev/null"
check "…node_modules gone"           gone n/app/node_modules
mk; check "clean:docker: runs, no prune" bash -c "$(declare -f npmrun); STUB='$STUB' REPO='$REPO' npmrun clean:docker -- '$T/n' >/dev/null"
check "…deleted nothing"             kept n/app/node_modules
check "…did not prune"               bash -c "! grep -q prune '$T/calls'"
mk; check "clean:all: runs"          bash -c "$(declare -f npmrun); STUB='$STUB' REPO='$REPO' npmrun clean:all -- '$T/n' >/dev/null"
check "…node_modules gone"           gone n/app/node_modules
check "…pruned docker"               grep -q 'system prune --force' "$T/calls"
check "…never pruned volumes"        bash -c "! grep -q volume '$T/calls'"
mk; check "path with a space works"  bash -c "$(declare -f npmrun); STUB='$STUB' REPO='$REPO' npmrun clean:yes -- '$T/n/sp ace' >/dev/null"
check "…deleted it"                  gone "n/sp ace/node_modules"
mk
for s in clean clean:yes clean:docker clean:all; do
  check "$s with no path refuses"    bash -c "$(declare -f npmrun); STUB='$STUB' REPO='$REPO'; ! npmrun $s >/dev/null"
done
check "…and deleted nothing"         kept n/app/node_modules
check "…and did not call docker"     bash -c "! grep -q . '$T/calls'"
check "empty path refused"           bash -c "! bash '$BIN' '' 2>/dev/null"

echo
if [ "$FAILS" -gt 0 ]; then echo "$FAILS check(s) failed"; exit 1; fi
echo "all checks passed"
