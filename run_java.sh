#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./run_java.sh [options] <MainClass> [args...]

Options:
  --install-missing  Offer to download portable tools into .tools/ (default)
  --yes              Non-interactive: auto-accept installs
  --native-access X  For Java 24+: set X to 'ALL-UNNAMED' (recommended) or a module name (module-path only)
  -h, --help         Show this help
EOF
}

INSTALL_MISSING=true
YES=false
NATIVE_ACCESS_TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-missing) INSTALL_MISSING=true ;;
    --yes) YES=true ;;
    --native-access)
      NATIVE_ACCESS_TARGET="${2:-}"
      if [[ -z "$NATIVE_ACCESS_TARGET" ]]; then
        echo "ERROR: --native-access requires a value: ALL-UNNAMED or com.fazecast.jSerialComm" >&2
        exit 2
      fi
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

MAIN_CLASS="${1:-}"
shift || true

if [[ -z "$MAIN_CLASS" ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_ARGS=(--emit --quiet)
if [[ "$INSTALL_MISSING" == true ]]; then
  ENV_ARGS+=(--install-missing)
fi
if [[ "$YES" == true ]]; then
  ENV_ARGS+=(--yes)
fi

if [[ ! -f "$SCRIPT_DIR/scripts/env.sh" ]]; then
  echo "[run_java] ERROR: Missing required helper: $SCRIPT_DIR/scripts/env.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
eval "$("$SCRIPT_DIR/scripts/env.sh" "${ENV_ARGS[@]}")"

echo "[run_java] Using JAVA_HOME: $JAVA_HOME (javac $JAVA_MAJOR)"
echo "[run_java] Using Maven: $MVN_BIN"
echo

mkdir -p "$SCRIPT_DIR/target"

echo "[run_java] Resolving dependencies..."
"$MVN_BIN" -q dependency:resolve

echo "[run_java] Compiling..."
"$MVN_BIN" -q compile

echo "[run_java] Building classpath..."
CLASSPATH_FILE="$SCRIPT_DIR/target/classpath.txt"
"$MVN_BIN" -q -Dmdep.outputFile="$CLASSPATH_FILE" dependency:build-classpath

CP="$SCRIPT_DIR/target/classes:$(cat "$CLASSPATH_FILE")"

JAVA_ARGS=()
if [[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]] && (( JAVA_MAJOR >= 24 )); then
  # Java 24+ restricts native access; jSerialComm needs explicit enablement.
  # Default: allow native access from all classpath code (unnamed module).
  if [[ -z "$NATIVE_ACCESS_TARGET" ]]; then
    NATIVE_ACCESS_TARGET="ALL-UNNAMED"
  fi
  if [[ "$NATIVE_ACCESS_TARGET" != "ALL-UNNAMED" ]]; then
    echo "[run_java] Note: this runner uses the classpath (-cp); module-name targets may warn 'Unknown module'."
  fi
  JAVA_ARGS+=("--enable-native-access=${NATIVE_ACCESS_TARGET}")
  echo "[run_java] Native access enabled for: ${NATIVE_ACCESS_TARGET}"
fi

NATIVE_DIR="$SCRIPT_DIR/native-libs"
if [[ -d "$NATIVE_DIR" ]] && find "$NATIVE_DIR" -maxdepth 1 -type f \( -name '*.jnilib' -o -name '*.dylib' -o -name '*.so' -o -name '*.dll' \) | grep -q .; then
  JAVA_ARGS+=("-DjSerialComm.library.path=$NATIVE_DIR")
  echo "[run_java] Using jSerialComm native library from: $NATIVE_DIR"
else
  # Fallback: keep tmp extraction under project folder (helps on some locked-down systems)
  TMP_LOCAL="$SCRIPT_DIR/temp"
  mkdir -p "$TMP_LOCAL"
  JAVA_ARGS+=("-Djava.io.tmpdir=$TMP_LOCAL")
  echo "[run_java] Using temp dir for native extraction: $TMP_LOCAL"
fi

echo "[run_java] Running $MAIN_CLASS..."
echo
"$JAVA_BIN" "${JAVA_ARGS[@]}" -cp "$CP" "$MAIN_CLASS" "$@"
