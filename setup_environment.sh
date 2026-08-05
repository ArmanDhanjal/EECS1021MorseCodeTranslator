#!/usr/bin/env bash
# =============================================================================
# setup_environment.sh - Prepare environment for Lab 2 execution (macOS/Linux)
# =============================================================================
# This script prepares the environment by:
#   1. Detecting (and optionally installing) JDK/Maven
#   2. Downloading Maven dependencies
#   3. Compiling the project
#   4. Extracting jSerialComm native library
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
INSTALL_MISSING=true
YES=false
REQUIRE_ARDUINO_CLI=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-missing) INSTALL_MISSING=true ;;
        --yes) YES=true ;;
        --require-arduino-cli) REQUIRE_ARDUINO_CLI=true ;;
        -h|--help)
            cat <<'EOF'
Usage: ./setup_environment.sh [options]

Options:
  --install-missing      Offer to download portable tools into .tools/ (default)
  --yes                  Non-interactive: auto-accept installs
  --require-arduino-cli  Also ensure arduino-cli is available
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 2
            ;;
    esac
    shift
done

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "============================================================================="
echo "Lab 2 Environment Setup (macOS/Linux)"
echo "============================================================================="
echo

# Detect OS and architecture
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"

print_info "Detected OS: $OS_TYPE"
print_info "Detected Architecture: $ARCH_TYPE"
echo

# Step 1: Detect tools (and optionally install missing ones)
print_step "Step 1/5: Detecting toolchain (JDK/Maven/Arduino)..."

ENV_ARGS=(--emit --quiet)
if [[ "$INSTALL_MISSING" == true ]]; then
    ENV_ARGS+=(--install-missing)
fi
if [[ "$YES" == true ]]; then
    ENV_ARGS+=(--yes)
fi
if [[ "$REQUIRE_ARDUINO_CLI" == true ]]; then
    ENV_ARGS+=(--require-arduino-cli)
fi

if [[ ! -f "$SCRIPT_DIR/scripts/env.sh" ]]; then
    print_error "Missing required helper: $SCRIPT_DIR/scripts/env.sh"
    exit 1
fi

# shellcheck disable=SC1091
eval "$("$SCRIPT_DIR/scripts/env.sh" "${ENV_ARGS[@]}")"

print_info "JAVA_HOME: $JAVA_HOME (javac $JAVA_MAJOR)"
print_info "Maven: $MVN_BIN"
if [[ -n "${ARDUINO_CLI:-}" ]]; then
    print_info "arduino-cli: $ARDUINO_CLI"
else
    print_warning "arduino-cli: not found (OK if you only need Java part)"
fi
echo

# Step 3: Download Maven dependencies
print_step "Step 2/5: Downloading Maven dependencies..."

if ! "$MVN_BIN" -q dependency:resolve; then
    print_error "Failed to download Maven dependencies"
    print_error "Please check your internet connection and Maven configuration"
    exit 1
fi

print_info "Maven dependencies downloaded"
echo

# Step 4: Compile the project
print_step "Step 3/5: Compiling project..."

if ! "$MVN_BIN" -q compile; then
    print_error "Project compilation failed"
    print_error "Please check the error messages above"
    exit 1
fi

print_info "Project compiled successfully"
echo

# Step 5: Clean up corrupted jSerialComm temp directories
print_step "Step 4/5: Cleaning up jSerialComm temp directories..."

# Clean up temp directories that might have corrupted files
TMPDIR="${TMPDIR:-/tmp}"
TEMP_PATHS=(
    "$TMPDIR/jSerialComm"
    "$HOME/.jSerialComm"
    "/tmp/jSerialComm"
)

for temp_path in "${TEMP_PATHS[@]}"; do
    if [ -d "$temp_path" ]; then
        # Check for corrupted directories (containing .* or wrong architecture)
        if find "$temp_path" -name ".*" -o -name "*aarch64*" -o -name "*arm64*" 2>/dev/null | grep -q .; then
            rm -rf "$temp_path" 2>/dev/null || true
            print_info "Cleaned up corrupted directory: $temp_path"
        fi
    fi
done

print_info "Cleanup completed"
echo

# Step 6: Extract jSerialComm native library
print_step "Step 5/5: Extracting jSerialComm native library..."

# Determine the correct native library name and path based on OS
NATIVE_LIB_DIR="$SCRIPT_DIR/native-libs"
NATIVE_LIB_NAME=""
NATIVE_LIB_PATH=""
JAR_EXTRACT_PATH=""

case "$OS_TYPE" in
    Darwin)
        # macOS
        if [[ "$ARCH_TYPE" == "arm64" ]]; then
            NATIVE_LIB_NAME="libjSerialComm.dylib"
            JAR_EXTRACT_PATH="macOS/arm64/libjSerialComm.dylib"
        else
            NATIVE_LIB_NAME="libjSerialComm.dylib"
            JAR_EXTRACT_PATH="macOS/x86_64/libjSerialComm.dylib"
        fi
        ;;
    Linux)
        # Linux
        if [[ "$ARCH_TYPE" == "aarch64" ]] || [[ "$ARCH_TYPE" == "arm64" ]]; then
            NATIVE_LIB_NAME="libjSerialComm.so"
            JAR_EXTRACT_PATH="Linux/arm64/libjSerialComm.so"
        else
            NATIVE_LIB_NAME="libjSerialComm.so"
            JAR_EXTRACT_PATH="Linux/x86_64/libjSerialComm.so"
        fi
        ;;
    *)
        print_warning "Unknown OS type: $OS_TYPE. Attempting to use Linux x86_64 library."
        NATIVE_LIB_NAME="libjSerialComm.so"
        JAR_EXTRACT_PATH="Linux/x86_64/libjSerialComm.so"
        ;;
esac

NATIVE_LIB_PATH="$NATIVE_LIB_DIR/$NATIVE_LIB_NAME"

# Create native-libs directory if it doesn't exist
mkdir -p "$NATIVE_LIB_DIR"

# Check if native library already exists
if [ -f "$NATIVE_LIB_PATH" ]; then
    print_info "Native library already extracted: $NATIVE_LIB_NAME"
else
    # Try to find the jSerialComm JAR in Maven repository
    MAVEN_REPO="$HOME/.m2/repository"
    JAR_PATH="$MAVEN_REPO/com/fazecast/jSerialComm/2.10.4/jSerialComm-2.10.4.jar"
    
    if [ ! -f "$JAR_PATH" ]; then
        print_warning "jSerialComm JAR not found at: $JAR_PATH"
        print_warning "Native library extraction skipped. It will be extracted automatically when needed."
    else
        # Extract the native library from the JAR
        TEMP_EXTRACT="$SCRIPT_DIR/temp_extract"
        rm -rf "$TEMP_EXTRACT" 2>/dev/null || true
        mkdir -p "$TEMP_EXTRACT"
        
        # Extract JAR (JARs are ZIP files)
        if command -v unzip &> /dev/null; then
            unzip -q "$JAR_PATH" -d "$TEMP_EXTRACT" 2>/dev/null || true
            
            # Look for the native library in the extracted files
            SOURCE_LIB=""
            if [ -f "$TEMP_EXTRACT/$JAR_EXTRACT_PATH" ]; then
                SOURCE_LIB="$TEMP_EXTRACT/$JAR_EXTRACT_PATH"
            else
                # Try to find any matching library file
                SOURCE_LIB=$(find "$TEMP_EXTRACT" -name "$NATIVE_LIB_NAME" 2>/dev/null | head -n 1)
                if [ -z "$SOURCE_LIB" ]; then
                    # Try alternative paths
                    SOURCE_LIB=$(find "$TEMP_EXTRACT" -name "*.dylib" -o -name "*.so" 2>/dev/null | grep -i "$ARCH_TYPE\|x86_64" | head -n 1)
                fi
            fi
            
            if [ -n "$SOURCE_LIB" ] && [ -f "$SOURCE_LIB" ]; then
                cp "$SOURCE_LIB" "$NATIVE_LIB_PATH"
                print_info "Native library extracted: $NATIVE_LIB_NAME"
            else
                print_warning "Could not find native library for $OS_TYPE/$ARCH_TYPE in JAR"
                print_warning "Expected path: $JAR_EXTRACT_PATH"
            fi
            
            rm -rf "$TEMP_EXTRACT"
        else
            print_warning "unzip not found. Cannot extract native library from JAR."
        fi
    fi
fi

echo

# Verification
echo "============================================================================="
echo "Verification"
echo "============================================================================="
echo

print_info "Checking Java version:"
if ! "$JAVA_BIN" -version; then
    print_error "Java is not working correctly"
    exit 1
fi
echo

print_info "Checking Maven version:"
if ! "$MVN_BIN" -version; then
    print_error "Maven is not working correctly"
    exit 1
fi
echo

print_info "Checking compiled classes:"
if [ -f "target/classes/HashMapExample.class" ]; then
    print_info "HashMapExample.class found"
else
    print_warning "HashMapExample.class not found"
fi

if [ -f "target/classes/InMemoryDatabase.class" ]; then
    print_info "InMemoryDatabase.class found"
else
    print_warning "InMemoryDatabase.class not found"
fi

if [ -f "target/classes/Lab2ExerciseSolution.class" ]; then
    print_info "Lab2ExerciseSolution.class found"
else
    print_warning "Lab2ExerciseSolution.class not found"
fi
echo

echo "============================================================================="
print_info "Setup Complete!"
echo "============================================================================="
echo
echo "You can now run:"
echo "   ./run_java.sh HashMapExample"
echo "   ./run_java.sh InMemoryDatabase"
echo "   ./run_java.sh Lab2ExerciseSolution"
echo
echo "Note: JAVA_HOME is set for this script's process; use scripts/env.sh if you"
echo "      want to export the same environment into your current shell."
echo
echo "Troubleshooting:"
echo "   - If you see 'NoClassDefFoundError' for jSerialComm, run this setup"
echo "     script again to ensure dependencies are downloaded."
echo "   - If you see native library errors, ensure you're using the correct"
echo "     architecture version of jSerialComm for your system ($OS_TYPE/$ARCH_TYPE)."
echo "   - On macOS, you may need to allow the native library to run:"
echo "     System Preferences > Security & Privacy > General"
echo
