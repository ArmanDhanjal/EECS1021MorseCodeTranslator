#!/usr/bin/env bash
# Build jSerialComm native library for the current host and install it into:
#   <Lab02>/native-libs/
#
# Source is downloaded from:
#   https://github.com/Fazecast/jSerialComm/tarball/<ref>
#
# Notes:
# - This builds ONLY for the current host (no cross-compilation).
# - Building the full multi-platform jSerialComm distribution is more involved.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh [options]

Options:
  --ref <ref>          Git ref for tarball (default: master)
  --out-dir <dir>      Output directory for built native library
                       (default: ../../native-libs)
  --keep-work          Keep the temporary build directory (prints its path)
  -h, --help           Show this help
EOF
}

REF="master"
OUT_DIR=""
KEEP_WORK=false
WORK_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      REF="${2:-}"
      shift
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift
      ;;
    --keep-work) KEEP_WORK=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[jSerialComm build] ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB02_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${OUT_DIR:-"$LAB02_ROOT/native-libs"}"

log() { printf '[jSerialComm build] %s\n' "$*" >&2; }
die() { printf '[jSerialComm build] ERROR: %s\n' "$*" >&2; exit 1; }

backup_then_copy() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    cp -f "$dest" "$dest.bak" 2>/dev/null || true
  fi
  cp -f "$src" "$dest"
}

detect_java_home() {
  # Prefer Lab02 toolchain detection if available (keeps consistency with the project).
  if [[ -f "$LAB02_ROOT/scripts/env.sh" ]]; then
    # shellcheck disable=SC1091
    eval "$("$LAB02_ROOT/scripts/env.sh" --emit --quiet)"
  fi

  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/javac" ]]; then
    echo "$JAVA_HOME"
    return 0
  fi

  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    local mac_home
    mac_home="$(/usr/libexec/java_home 2>/dev/null || true)"
    if [[ -n "$mac_home" && -x "$mac_home/bin/javac" ]]; then
      echo "$mac_home"
      return 0
    fi
  fi

  if command -v javac >/dev/null 2>&1; then
    local javac_path
    javac_path="$(command -v javac)"
    echo "$(cd "$(dirname "$javac_path")/.." && pwd)"
    return 0
  fi

  return 1
}

main() {
  local os
  os="$(uname -s)"
  case "$os" in
    Darwin|Linux) ;;
    *) die "Unsupported OS for this script: $os" ;;
  esac

  local java_home
  java_home="$(detect_java_home)" || die "JAVA_HOME could not be detected. Install a JDK first."
  [[ -d "$java_home/include" ]] || die "Invalid JAVA_HOME (missing include/): $java_home"

  local cc
  if command -v clang >/dev/null 2>&1; then
    cc="clang"
  elif command -v gcc >/dev/null 2>&1; then
    cc="gcc"
  else
    die "No C compiler found (need clang or gcc)."
  fi

  WORK_DIR="$(mktemp -d)"
  if [[ "$KEEP_WORK" == false ]]; then
    trap 'rm -rf "${WORK_DIR}"' EXIT
  fi

  local url="https://github.com/Fazecast/jSerialComm/tarball/${REF}"
  log "Downloading: $url"
  curl -fsSL -L -o "$WORK_DIR/jSerialComm.tar.gz" "$url"

  log "Extracting..."
  tar -xzf "$WORK_DIR/jSerialComm.tar.gz" -C "$WORK_DIR"
  local src_root
  src_root="$(find "$WORK_DIR" -maxdepth 1 -type d -name 'Fazecast-jSerialComm-*' -print -quit)"
  [[ -n "$src_root" && -d "$src_root" ]] || die "Could not find extracted source root."

  local c_dir="$src_root/src/main/c/Posix"
  [[ -d "$c_dir" ]] || die "Expected native sources not found: $c_dir"

  local build_dir="$WORK_DIR/build"
  mkdir -p "$build_dir"

  local include_os
  case "$os" in
    Darwin) include_os="darwin" ;;
    Linux) include_os="linux" ;;
  esac

  local cflags=(-I"$java_home/include" -I"$java_home/include/$include_os" -fPIC -O2 -Wall)

  log "Compiling (JAVA_HOME=$java_home, CC=$cc, OS=$os)..."
  "$cc" "${cflags[@]}" -c "$c_dir/SerialPort_Posix.c" -o "$build_dir/SerialPort_Posix.o"
  "$cc" "${cflags[@]}" -c "$c_dir/PosixHelperFunctions.c" -o "$build_dir/PosixHelperFunctions.o"

  if [[ "$os" == "Darwin" ]]; then
    "$cc" -dynamiclib \
      -o "$build_dir/libjSerialComm.jnilib" \
      "$build_dir/SerialPort_Posix.o" \
      "$build_dir/PosixHelperFunctions.o" \
      -framework Cocoa -framework IOKit

    log "Installing to: $OUT_DIR"
    backup_then_copy "$build_dir/libjSerialComm.jnilib" "$OUT_DIR/libjSerialComm.jnilib"
    # Convenience copy for scripts/tools that look for .dylib
    backup_then_copy "$build_dir/libjSerialComm.jnilib" "$OUT_DIR/libjSerialComm.dylib"
  else
    "$cc" -shared \
      -o "$build_dir/libjSerialComm.so" \
      "$build_dir/SerialPort_Posix.o" \
      "$build_dir/PosixHelperFunctions.o"

    log "Installing to: $OUT_DIR"
    backup_then_copy "$build_dir/libjSerialComm.so" "$OUT_DIR/libjSerialComm.so"
  fi

  log "Done."
  if [[ "$KEEP_WORK" == true ]]; then
    log "Kept work dir: $WORK_DIR"
  fi
}

main
