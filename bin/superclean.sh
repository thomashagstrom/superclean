#!/usr/bin/env bash
# superclean — reclaim disk space from regenerable JS/Expo artifacts and Docker.
#
# Requires a target directory as the FIRST argument and removes, under it:
#   node_modules  — always
#   .next         — Next.js build output/cache; only next to a package.json
#   build         — only next to a package.json
#   ios, android  — Expo managed prebuild output; only next to app.json /
#                   app.config.{js,ts,mjs,cjs} (i.e. inside an Expo project)
# Each is guarded so real source folders are never touched, and .git is skipped.
#
# Nested matches (e.g. android/build, ios/Pods/...) are skipped once a parent
# is already slated for removal, so sizes aren't double-counted.
#
# Docker (opt-in with --docker): stopped containers, unused networks, dangling
# images and build cache. --docker-all also removes every image no container
# uses. Volumes are NEVER touched — they hold data (databases, caches).
#
# Always a dry run unless you pass --yes. Written for macOS's stock bash 3.2
# and BSD tools; no dependencies.
set -euo pipefail

DELETE=false
DOCKER=false
DOCKER_ALL=false

usage() {
  echo "Usage: superclean <path> [--yes] [--docker | --docker-all]"
  echo "  <path>        directory to scan (required, must be the first argument)"
  echo "  (no flags)    dry run — list directories to clean and total size"
  echo "  --yes / -y    actually delete them"
  echo "  --docker      also prune stopped containers, unused networks,"
  echo "                dangling images and build cache (never volumes)"
  echo "  --docker-all  like --docker, but removes all unused images too"
}

fail() {
  echo "superclean: $1" >&2
  echo >&2
  usage >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  fail "a target path is required, e.g. superclean ~/Source"
fi

if [ -z "$1" ]; then
  fail "the target path is empty (did you forget to pass one after \`--\`?)"
fi

case "$1" in
  --help|-h) usage; exit 0 ;;
  -*) fail "the target path must be the first argument (got option: $1)" ;;
esac

# Under `npm run`, the cwd is the package dir; INIT_CWD is where you ran npm,
# which is what a relative path like `.` should be resolved against.
if [ ! -d "${INIT_CWD:-$PWD}/$1" ] && [ ! -d "$1" ]; then
  fail "not a directory: $1"
fi
case "$1" in
  /*) ROOT_DIR="$(cd "$1" && pwd)" ;;
  *)  ROOT_DIR="$(cd "${INIT_CWD:-$PWD}" && cd "$1" && pwd)" ;;
esac
shift

for arg in "$@"; do
  case "$arg" in
    --yes|-y) DELETE=true ;;
    --docker) DOCKER=true ;;
    --docker-all) DOCKER=true; DOCKER_ALL=true ;;
    --help|-h) usage; exit 0 ;;
    -*) fail "unknown option: $arg" ;;
    *)  fail "unexpected argument: $arg (only one target path is allowed, and it must come first)" ;;
  esac
done

is_expo_project() {
  local p="$1"
  [ -f "$p/app.json" ] || [ -f "$p/app.config.js" ] || [ -f "$p/app.config.ts" ] \
    || [ -f "$p/app.config.mjs" ] || [ -f "$p/app.config.cjs" ]
}

# Decide whether a candidate directory is safe to delete.
should_delete() {
  local dir="$1"
  local name parent
  name="$(basename "$dir")"
  parent="$(dirname "$dir")"
  case "$name" in
    node_modules) return 0 ;;
    .next|build)  [ -f "$parent/package.json" ] ;;
    ios|android)  [ -f "$parent/package.json" ] && is_expo_project "$parent" ;;
    *)            return 1 ;;
  esac
}

RC=0

clean_dirs() {
  echo "Scanning for node_modules, .next, build, ios, android under: $ROOT_DIR"
  echo

  # Only node_modules and .git are pruned in find; other candidates are filtered
  # below so a rejected build/ dir is still searched for node_modules inside it.
  # find walks pre-order, so a parent always appears before its children.
  local DIRS=() dir kept skip
  while IFS= read -r -d '' dir; do
    skip=false
    for kept in ${DIRS[@]+"${DIRS[@]}"}; do
      case "$dir" in "$kept"/*) skip=true; break ;; esac
    done
    [ "$skip" = true ] && continue
    if should_delete "$dir"; then
      DIRS+=("$dir")
    fi
  done < <(find "$ROOT_DIR" \
    \( -type d -name .git -prune \) -o \
    \( -type d -name node_modules -prune -print0 \) -o \
    \( -type d \( -name .next -o -name build -o -name ios -o -name android \) -print0 \))

  if [ "${#DIRS[@]}" -eq 0 ]; then
    echo "Nothing to clean."
    return 0
  fi

  local total_kb=0 size_h size_k total_h
  echo "Found ${#DIRS[@]} director$( [ "${#DIRS[@]}" -eq 1 ] && echo y || echo ies ):"
  echo

  for dir in "${DIRS[@]}"; do
    size_h=$(du -sh "$dir" 2>/dev/null | cut -f1 || true)
    size_k=$(du -sk "$dir" 2>/dev/null | cut -f1 || true)
    total_kb=$((total_kb + ${size_k:-0}))
    printf "  %-8s %s\n" "${size_h:-?}" "$dir"
  done

  total_h=$(echo "$total_kb" | awk '{
    kb=$1
    if (kb >= 1048576) printf "%.2f GB", kb/1048576
    else if (kb >= 1024) printf "%.2f MB", kb/1024
    else printf "%d KB", kb
  }')

  echo
  echo "Total reclaimable: $total_h"
  echo

  if [ "$DELETE" = false ]; then
    echo "Dry run only — nothing deleted. Re-run with --yes to remove these directories."
    return 0
  fi

  echo "Deleting..."
  local failed=0
  for dir in "${DIRS[@]}"; do
    if rm -rf "$dir"; then
      echo "  removed $dir"
    else
      echo "  FAILED  $dir" >&2
      failed=$((failed + 1))
    fi
  done

  echo
  if [ "$failed" -gt 0 ]; then
    echo "Done with $failed failure(s). Freed up to $total_h."
    RC=1
    return 0
  fi
  echo "Done. Freed approximately $total_h."
}

# Run a command, killing it after N seconds. macOS ships no `timeout`, and a
# Docker Desktop whose engine is stopped or wedged makes the CLI hang forever.
with_timeout() {
  local secs="$1" pid watcher rc=0
  shift
  "$@" &
  pid=$!
  # The watcher's output goes to /dev/null so a leftover `sleep` can't hold a
  # pipe open (e.g. `superclean | less`) after the script ends.
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watcher=$!
  wait "$pid" || rc=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  return "$rc"
}

clean_docker() {
  echo "Docker"
  echo

  if ! command -v docker >/dev/null 2>&1; then
    echo "  docker is not installed — skipping."
    return 0
  fi
  if ! with_timeout 15 docker info >/dev/null 2>&1; then
    echo "  The Docker engine isn't responding. Start Docker Desktop (or wait for it" >&2
    echo "  to finish starting) and re-run. Skipping Docker." >&2
    RC=1
    return 0
  fi

  with_timeout 60 docker system df || echo "  (could not read Docker disk usage)"
  echo

  local prune=(docker system prune --force)
  local what="stopped containers, unused networks, dangling images and build cache"
  if [ "$DOCKER_ALL" = true ]; then
    prune+=(--all)
    what="stopped containers, unused networks, all unused images and all build cache"
  fi

  if [ "$DELETE" = false ]; then
    echo "Dry run only — would remove $what"
    echo "(volumes are kept). See the RECLAIMABLE column above. Re-run with --yes to prune."
    return 0
  fi

  echo "Pruning $what (volumes are kept)..."
  # No timeout here: a big prune can legitimately take minutes.
  if ! "${prune[@]}"; then
    echo "  docker system prune failed." >&2
    RC=1
  fi
}

clean_dirs
if [ "$DOCKER" = true ]; then
  echo
  clean_docker
fi
exit "$RC"
