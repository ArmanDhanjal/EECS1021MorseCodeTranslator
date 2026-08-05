#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/env.sh [options]

Detects (and optionally installs) toolchain dependencies for Lab02 and can emit
environment exports for other scripts to eval.

Options:
  --emit                 Print 'export ...' lines (for eval)
  --install-missing      Offer to download portable tools into .tools/ (default)
  --yes                  Non-interactive: auto-accept installs
  --require-arduino-cli  Fail (or install) if arduino-cli is missing
  --quiet                Suppress informational output (still prints exports with --emit)
  -h, --help             Show this help

Environment:
  LAB02_TOOLS_DIR            Override tools directory (default: <Lab02>/.tools)
  LAB02_REQUIRED_JAVA_MAJOR  Override required Java major (default: max(25, pom.xml))
  LAB02_MAVEN_VERSION        Override Maven version (default: 3.9.6)
EOF
}

EMIT=false
INSTALL_MISSING=true
YES=false
REQUIRE_ARDUINO_CLI=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --emit) EMIT=true ;;
    --install-missing) INSTALL_MISSING=true ;;
    --yes) YES=true ;;
    --require-arduino-cli) REQUIRE_ARDUINO_CLI=true ;;
    --quiet) QUIET=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB02_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="${LAB02_TOOLS_DIR:-"$LAB02_ROOT/.tools"}"
DOWNLOADS_DIR="$TOOLS_DIR/downloads"

log() {
  if [[ "$QUIET" == true ]]; then
    return 0
  fi
  printf '[env] %s\n' "$*" >&2
}

die() {
  printf '[env] ERROR: %s\n' "$*" >&2
  exit 1
}

prompt_yes_no() {
  local prompt="$1"
  if [[ "$YES" == true ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N]: " reply
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

ensure_dirs() {
  mkdir -p "$TOOLS_DIR" "$DOWNLOADS_DIR"
}

detect_os() {
  local uname_s
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin) echo "mac" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) die "Unsupported OS: $uname_s" ;;
  esac
}

detect_arch() {
  local uname_m
  uname_m="$(uname -m)"
  case "$uname_m" in
    x86_64|amd64) echo "x64" ;;
    arm64|aarch64) echo "aarch64" ;;
    *) die "Unsupported architecture: $uname_m" ;;
  esac
}

required_java_major_from_pom() {
  local pom="$LAB02_ROOT/pom.xml"
  if [[ ! -f "$pom" ]]; then
    echo ""
    return 0
  fi

  local major=""
  major="$(grep -oE '<maven\\.compiler\\.(release|source)>[0-9]+' "$pom" | head -n 1 | grep -oE '[0-9]+' || true)"
  if [[ -z "$major" ]]; then
    major="$(grep -oE '<maven\\.compiler\\.target>[0-9]+' "$pom" | head -n 1 | grep -oE '[0-9]+' || true)"
  fi
  echo "$major"
}

parse_javac_major() {
  local out="$1"
  # Examples:
  #   "javac 25"
  #   "javac 1.8.0_392"
  local ver
  ver="$(echo "$out" | awk '{print $2}' | tr -d '\r' || true)"
  if [[ "$ver" == 1.* ]]; then
    echo "${ver#1.}" | cut -d. -f1
  else
    echo "$ver" | cut -d. -f1
  fi
}

is_executable() {
  local path="$1"
  [[ -n "$path" && -f "$path" && -x "$path" ]]
}

find_java_from_home() {
  local home="$1"
  if [[ -z "$home" ]]; then
    return 1
  fi
  if is_executable "$home/bin/javac" && is_executable "$home/bin/java"; then
    echo "$home"
    return 0
  fi
  # macOS JDK bundle layout
  if is_executable "$home/Contents/Home/bin/javac" && is_executable "$home/Contents/Home/bin/java"; then
    echo "$home/Contents/Home"
    return 0
  fi
  return 1
}

find_java_home() {
  local candidate=""

  # 1) JAVA_HOME (if valid)
  if [[ -n "${JAVA_HOME:-}" ]]; then
    candidate="$(find_java_from_home "$JAVA_HOME" || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  # 2) Project-local tools (.tools/jdk)
  if [[ -f "$TOOLS_DIR/jdk/.java_home" ]]; then
    candidate="$(cat "$TOOLS_DIR/jdk/.java_home" 2>/dev/null || true)"
    candidate="$(find_java_from_home "$candidate" || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  if [[ -d "$TOOLS_DIR/jdk" ]]; then
    # macOS
    candidate="$(find "$TOOLS_DIR/jdk" -maxdepth 4 -type f -name javac -path "*/Contents/Home/bin/javac" -print -quit 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      echo "$(cd "$(dirname "$candidate")/.." && pwd)"
      return 0
    fi
    # linux/windows style
    candidate="$(find "$TOOLS_DIR/jdk" -maxdepth 3 -type f -name javac -path "*/bin/javac" -print -quit 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      echo "$(cd "$(dirname "$candidate")/.." && pwd)"
      return 0
    fi
  fi

  # 3) macOS: use /usr/libexec/java_home (more reliable than /usr/bin/javac wrapper)
  if [[ "$(detect_os)" == "mac" ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
    candidate="$(/usr/libexec/java_home 2>/dev/null || true)"
    candidate="$(find_java_from_home "$candidate" || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  # 4) System javac
  if command -v javac >/dev/null 2>&1; then
    local javac_path
    javac_path="$(command -v javac)"
    if [[ "$(detect_os)" == "mac" ]] && [[ "$javac_path" == "/usr/bin/javac" ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
      candidate="$(/usr/libexec/java_home 2>/dev/null || true)"
      candidate="$(find_java_from_home "$candidate" || true)"
      if [[ -n "$candidate" ]]; then
        echo "$candidate"
        return 0
      fi
    fi
    # If javac is a wrapper, this still typically lives under <JAVA_HOME>/bin
    echo "$(cd "$(dirname "$javac_path")/.." && pwd)"
    return 0
  fi

  return 1
}

find_java_home_in_tools() {
  local candidate=""
  if [[ ! -d "$TOOLS_DIR/jdk" ]]; then
    return 1
  fi
  # macOS
  candidate="$(find "$TOOLS_DIR/jdk" -maxdepth 4 -type f -name javac -path "*/Contents/Home/bin/javac" -print -quit 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    echo "$(cd "$(dirname "$candidate")/.." && pwd)"
    return 0
  fi
  # linux/windows style
  candidate="$(find "$TOOLS_DIR/jdk" -maxdepth 3 -type f -name javac -path "*/bin/javac" -print -quit 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    echo "$(cd "$(dirname "$candidate")/.." && pwd)"
    return 0
  fi
  return 1
}

download_jdk() {
  local major="$1"
  local os arch url tmp
  os="$(detect_os)"
  arch="$(detect_arch)"

  ensure_dirs
  mkdir -p "$TOOLS_DIR/jdk"

  url="https://api.adoptium.net/v3/binary/latest/${major}/ga/${os}/${arch}/jdk/hotspot/normal/eclipse"
  tmp="$DOWNLOADS_DIR/jdk-${major}-${os}-${arch}.$(date +%s)"

  log "Downloading JDK ${major} (${os}/${arch})..."
  curl -fsSL -L -o "$tmp" "$url"

  # Clean old installs for the same major (best-effort)
  rm -rf "$TOOLS_DIR/jdk/jdk-${major}"* 2>/dev/null || true

  if [[ "$os" == "windows" ]]; then
    command -v unzip >/dev/null 2>&1 || die "unzip is required to extract the JDK on Windows"
    unzip -q "$tmp" -d "$TOOLS_DIR/jdk"
  else
    tar -xzf "$tmp" -C "$TOOLS_DIR/jdk"
  fi

  # Record discovered JAVA_HOME for faster future runs
  local home
  home="$(find_java_home_in_tools || true)"
  if [[ -z "$home" ]]; then
    die "JDK download/extract completed, but JAVA_HOME could not be detected under $TOOLS_DIR/jdk"
  fi
  printf '%s\n' "$home" >"$TOOLS_DIR/jdk/.java_home"
  log "Installed JDK home: $home"
}

ensure_java() {
  local baseline="25"
  local required="${LAB02_REQUIRED_JAVA_MAJOR:-}"
  if [[ -z "$required" ]]; then
    required="$(required_java_major_from_pom || true)"
  fi
  if [[ -z "$required" ]]; then
    required="$baseline"
  fi
  if [[ "$required" =~ ^[0-9]+$ ]] && (( required < baseline )); then
    required="$baseline"
  fi

  local home
  home="$(find_java_home || true)"
  if [[ -z "$home" ]]; then
    if [[ "$INSTALL_MISSING" == true ]] && prompt_yes_no "Java (JDK) not found. Download a portable JDK ${required}?"; then
      download_jdk "$required"
      home="$(find_java_home)"
    else
      die "Java (JDK) not found. Install a JDK ${required}+ or re-run and accept the portable install prompt."
    fi
  fi

  local javac="$home/bin/javac"
  local java="$home/bin/java"
  if [[ ! -x "$javac" || ! -x "$java" ]]; then
    die "Invalid JAVA_HOME detected: $home"
  fi

  local javac_ver major
  javac_ver="$("$javac" -version 2>&1 || true)"
  major="$(parse_javac_major "$javac_ver")"
  if [[ -z "$major" ]]; then
    die "Could not determine javac version from: $javac_ver"
  fi

  if (( major < required )); then
    if [[ "$INSTALL_MISSING" == true ]] && prompt_yes_no "JDK ${major} found but ${required}+ is required. Download JDK ${required}?"; then
      download_jdk "$required"
      home="$(cat "$TOOLS_DIR/jdk/.java_home" 2>/dev/null || true)"
      [[ -n "$home" ]] || home="$(find_java_home_in_tools)"
      javac="$home/bin/javac"
      java="$home/bin/java"
      javac_ver="$("$javac" -version 2>&1 || true)"
      major="$(parse_javac_major "$javac_ver")"
    else
      die "JDK ${required}+ required (found javac ${major}). Install a newer JDK or re-run and accept the portable install prompt."
    fi
  fi

  JAVA_HOME="$home"
  JAVA_BIN="$java"
  JAVAC_BIN="$javac"
  JAVA_MAJOR="$major"
}

find_maven_bin() {
  # 1) Maven Wrapper in repo (preferred)
  if [[ -x "$LAB02_ROOT/mvnw" ]]; then
    echo "$LAB02_ROOT/mvnw"
    return 0
  fi

  # 2) Previously installed portable Maven (marker file)
  if [[ -f "$TOOLS_DIR/maven/.mvn_bin" ]]; then
    local p
    p="$(cat "$TOOLS_DIR/maven/.mvn_bin" 2>/dev/null | tr -d '\r' || true)"
    if [[ -n "$p" && -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  fi

  # 3) Previously installed portable Maven (best-effort search)
  if [[ -d "$TOOLS_DIR/maven" ]]; then
    local os
    os="$(detect_os)"
    local candidate
    if [[ "$os" == "windows" ]]; then
      candidate="$(find "$TOOLS_DIR/maven" -maxdepth 3 -type f -name mvn.cmd -print -quit 2>/dev/null || true)"
      [[ -n "$candidate" ]] || candidate="$(find "$TOOLS_DIR/maven" -maxdepth 3 -type f -name mvn -print -quit 2>/dev/null || true)"
    else
      candidate="$(find "$TOOLS_DIR/maven" -maxdepth 3 -type f -name mvn -print -quit 2>/dev/null || true)"
      [[ -n "$candidate" ]] || candidate="$(find "$TOOLS_DIR/maven" -maxdepth 3 -type f -name mvn.cmd -print -quit 2>/dev/null || true)"
    fi
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  # 4) System Maven
  if command -v mvn >/dev/null 2>&1; then
    echo "mvn"
    return 0
  fi
  return 1
}

desired_maven_version() {
  if [[ -n "${LAB02_MAVEN_VERSION:-}" ]]; then
    printf '%s\n' "$LAB02_MAVEN_VERSION"
    return 0
  fi
  printf '%s\n' "3.9.6"
}

download_maven() {
  local ver os asset url tmp dest bin
  ver="${1:-}"
  [[ -n "$ver" ]] || ver="$(desired_maven_version)"

  os="$(detect_os)"

  ensure_dirs
  mkdir -p "$TOOLS_DIR/maven"

  if [[ "$os" == "windows" ]]; then
    asset="apache-maven-${ver}-bin.zip"
  else
    asset="apache-maven-${ver}-bin.tar.gz"
  fi

  url="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${ver}/${asset}"
  tmp="$DOWNLOADS_DIR/${asset}"
  dest="$TOOLS_DIR/maven/apache-maven-${ver}"

  log "Downloading Maven ${ver}..."
  curl -fsSL -L -o "$tmp" "$url"

  rm -rf "$dest" 2>/dev/null || true

  if [[ "$asset" == *.zip ]]; then
    command -v unzip >/dev/null 2>&1 || die "unzip is required to extract Maven on Windows"
    unzip -q "$tmp" -d "$TOOLS_DIR/maven"
    bin="$dest/bin/mvn.cmd"
  else
    tar -xzf "$tmp" -C "$TOOLS_DIR/maven"
    bin="$dest/bin/mvn"
  fi

  [[ -f "$bin" ]] || die "Maven download/extract completed, but mvn was not found under $dest"
  chmod +x "$bin" 2>/dev/null || true

  printf '%s\n' "$bin" >"$TOOLS_DIR/maven/.mvn_bin"
  log "Installed Maven bin: $bin"
}

ensure_maven() {
  local mvn
  mvn="$(find_maven_bin || true)"
  if [[ -z "$mvn" ]]; then
    if [[ "$INSTALL_MISSING" == true ]] && prompt_yes_no "Maven not found. Download a portable Maven?"; then
      download_maven "$(desired_maven_version)"
      mvn="$(find_maven_bin || true)"
    fi
  fi
  if [[ -z "$mvn" ]]; then
    die "Maven not found. Install Maven (or add the Maven Wrapper), or re-run and accept the portable install prompt."
  fi
  MVN_BIN="$mvn"
}

find_arduino_cli_bin() {
  if [[ -n "${ARDUINO_CLI:-}" ]] && [[ -x "${ARDUINO_CLI}" ]]; then
    echo "${ARDUINO_CLI}"
    return 0
  fi
  if [[ -f "$TOOLS_DIR/arduino-cli/.arduino_cli" ]]; then
    local p
    p="$(cat "$TOOLS_DIR/arduino-cli/.arduino_cli" 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  fi
  if [[ -x "$TOOLS_DIR/arduino-cli/arduino-cli" ]]; then
    echo "$TOOLS_DIR/arduino-cli/arduino-cli"
    return 0
  fi
  if [[ -x "$LAB02_ROOT/arduino-cli" ]]; then
    echo "$LAB02_ROOT/arduino-cli"
    return 0
  fi
  if command -v arduino-cli >/dev/null 2>&1; then
    echo "arduino-cli"
    return 0
  fi
  return 1
}

latest_arduino_cli_tag() {
  local json tag
  json="$(curl -fsSL "https://api.github.com/repos/arduino/arduino-cli/releases/latest")"
  tag="$(echo "$json" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')"
  [[ -n "$tag" ]] || die "Could not determine latest arduino-cli version from GitHub API"
  echo "$tag"
}

download_arduino_cli() {
  local os arch tag ver asset url tmp extract_dir bin_path
  os="$(detect_os)"
  arch="$(detect_arch)"
  tag="$(latest_arduino_cli_tag)"
  ver="${tag#v}"

  ensure_dirs
  mkdir -p "$TOOLS_DIR/arduino-cli"

  case "${os}/${arch}" in
    mac/aarch64) asset="arduino-cli_${ver}_macOS_ARM64.tar.gz" ;;
    mac/x64) asset="arduino-cli_${ver}_macOS_64bit.tar.gz" ;;
    linux/aarch64) asset="arduino-cli_${ver}_Linux_ARM64.tar.gz" ;;
    linux/x64) asset="arduino-cli_${ver}_Linux_64bit.tar.gz" ;;
    windows/x64) asset="arduino-cli_${ver}_Windows_64bit.zip" ;;
    *) die "Unsupported arduino-cli platform: ${os}/${arch}" ;;
  esac

  url="https://github.com/arduino/arduino-cli/releases/download/${tag}/${asset}"
  tmp="$DOWNLOADS_DIR/${asset}"

  log "Downloading arduino-cli ${ver} (${os}/${arch})..."
  curl -fsSL -L -o "$tmp" "$url"

  extract_dir="$TOOLS_DIR/arduino-cli/${ver}"
  rm -rf "$extract_dir" 2>/dev/null || true
  mkdir -p "$extract_dir"

  if [[ "$asset" == *.zip ]]; then
    command -v unzip >/dev/null 2>&1 || die "unzip is required to extract arduino-cli zip"
    unzip -q "$tmp" -d "$extract_dir"
    bin_path="$(find "$extract_dir" -maxdepth 2 -type f -name 'arduino-cli.exe' -print -quit 2>/dev/null || true)"
  else
    tar -xzf "$tmp" -C "$extract_dir"
    bin_path="$(find "$extract_dir" -maxdepth 2 -type f -name 'arduino-cli' -print -quit 2>/dev/null || true)"
  fi

  [[ -n "$bin_path" && -f "$bin_path" ]] || die "arduino-cli archive extracted, but binary not found"
  chmod +x "$bin_path" 2>/dev/null || true

  # Create a stable copy/symlink path for scripts
  if [[ "$asset" == *.zip ]]; then
    cp -f "$bin_path" "$TOOLS_DIR/arduino-cli/arduino-cli.exe"
    chmod +x "$TOOLS_DIR/arduino-cli/arduino-cli.exe" 2>/dev/null || true
    printf '%s\n' "$TOOLS_DIR/arduino-cli/arduino-cli.exe" >"$TOOLS_DIR/arduino-cli/.arduino_cli"
    ARDUINO_CLI="$TOOLS_DIR/arduino-cli/arduino-cli.exe"
  else
    cp -f "$bin_path" "$TOOLS_DIR/arduino-cli/arduino-cli"
    chmod +x "$TOOLS_DIR/arduino-cli/arduino-cli" 2>/dev/null || true
    printf '%s\n' "$TOOLS_DIR/arduino-cli/arduino-cli" >"$TOOLS_DIR/arduino-cli/.arduino_cli"
    ARDUINO_CLI="$TOOLS_DIR/arduino-cli/arduino-cli"
  fi

  log "Installed arduino-cli: $ARDUINO_CLI"
}

ensure_arduino_cli() {
  local cli
  cli="$(find_arduino_cli_bin || true)"

  # Only offer to install arduino-cli when it is required by the caller.
  if [[ -z "$cli" ]] && [[ "$REQUIRE_ARDUINO_CLI" == true ]]; then
    if [[ "$INSTALL_MISSING" == true ]] && prompt_yes_no "arduino-cli not found. Download a portable arduino-cli?"; then
      download_arduino_cli
      cli="$(find_arduino_cli_bin || true)"
    fi
  fi

  if [[ -z "$cli" ]]; then
    if [[ "$REQUIRE_ARDUINO_CLI" == true ]]; then
      die "arduino-cli not found. Install it, or re-run and accept the portable install prompt."
    fi
    ARDUINO_CLI=""
    return 0
  fi
  ARDUINO_CLI="$cli"
}

detect_arduino_ide() {
  local os
  os="$(detect_os)"
  ARDUINO_IDE_PATH=""

  case "$os" in
    mac)
      if [[ -d "/Applications/Arduino IDE.app" ]]; then
        ARDUINO_IDE_PATH="/Applications/Arduino IDE.app"
      elif [[ -d "/Applications/Arduino.app" ]]; then
        ARDUINO_IDE_PATH="/Applications/Arduino.app"
      fi
      ;;
    linux)
      if command -v arduino-ide >/dev/null 2>&1; then
        ARDUINO_IDE_PATH="$(command -v arduino-ide)"
      elif command -v arduino >/dev/null 2>&1; then
        ARDUINO_IDE_PATH="$(command -v arduino)"
      fi
      ;;
    windows)
      # Not reliable under MSYS/Cygwin; keep empty.
      ;;
  esac
}

emit_var() {
  local name="$1"
  local value="$2"
  printf 'export %s=%q\n' "$name" "$value"
}

main() {
  ensure_java
  ensure_maven
  ensure_arduino_cli
  detect_arduino_ide

  if [[ "$EMIT" == true ]]; then
    emit_var "LAB02_ROOT" "$LAB02_ROOT"
    emit_var "LAB02_TOOLS_DIR" "$TOOLS_DIR"
    emit_var "JAVA_HOME" "$JAVA_HOME"
    emit_var "JAVA_BIN" "$JAVA_BIN"
    emit_var "JAVAC_BIN" "$JAVAC_BIN"
    emit_var "JAVA_MAJOR" "$JAVA_MAJOR"
    emit_var "MVN_BIN" "$MVN_BIN"
    emit_var "ARDUINO_CLI" "$ARDUINO_CLI"
    emit_var "ARDUINO_IDE_PATH" "$ARDUINO_IDE_PATH"
    exit 0
  fi

  log "LAB02_ROOT: $LAB02_ROOT"
  log "JAVA_HOME: $JAVA_HOME (javac $JAVA_MAJOR)"
  log "MVN_BIN: $MVN_BIN"
  if [[ -n "$ARDUINO_CLI" ]]; then
    log "ARDUINO_CLI: $ARDUINO_CLI"
  else
    log "ARDUINO_CLI: (not found)"
  fi
  if [[ -n "$ARDUINO_IDE_PATH" ]]; then
    log "ARDUINO_IDE_PATH: $ARDUINO_IDE_PATH"
  else
    log "ARDUINO_IDE_PATH: (not found)"
  fi
}

main
