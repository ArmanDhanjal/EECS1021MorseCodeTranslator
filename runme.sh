#!/usr/bin/env bash
# =============================================================================
# runme.sh - Complete Lab 2 Setup and Execution (macOS/Linux)
# =============================================================================
# This script runs all necessary setup and execution steps in order:
#   1. Setup environment (JDK, Maven, dependencies)
#   2. Install Arduino Pico board manager
#   3. Compile and upload Pico firmware
#   4. Run a Java main class
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
INSTALL_MISSING=true
YES=false
SKIP_ARDUINO=false
MAIN_CLASS="Lab2ExerciseSolution"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-missing) INSTALL_MISSING=true ;;
        --yes) YES=true ;;
        --java-only|--skip-arduino) SKIP_ARDUINO=true ;;
        --run)
            MAIN_CLASS="${2:-}"
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: ./runme.sh [options]

Options:
  --install-missing          Offer to download portable tools into .tools/ (default)
  --yes                      Non-interactive: auto-accept installs
  --java-only, --skip-arduino  Skip Arduino CLI/core install + Pico upload steps
  --run <MainClass>          Java main class to run (default: Lab2ExerciseSolution)
EOF
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "============================================================================="
echo "Lab 2 - Complete Setup and Execution"
echo "============================================================================="
echo ""
echo "This script will run the following steps:"
echo "  1. Setup environment (JDK, Maven, dependencies)"
if [[ "$SKIP_ARDUINO" == false ]]; then
  echo "  2. Install Arduino Pico board manager"
  echo "  3. Compile and upload Pico firmware"
fi
echo "  4. Run Java: $MAIN_CLASS"
echo ""
echo "Press Ctrl+C to cancel at any time."
echo ""
read -p "Press Enter to continue..."

# =============================================================================
# Step 1: Setup Environment
# =============================================================================
echo ""
echo "============================================================================="
echo "[STEP 1/4] Setting up environment..."
echo "============================================================================="
echo ""

SETUP_ARGS=()
if [[ "$INSTALL_MISSING" == true ]]; then
  SETUP_ARGS+=(--install-missing)
fi
if [[ "$YES" == true ]]; then
  SETUP_ARGS+=(--yes)
fi
if [[ "$SKIP_ARDUINO" == false ]]; then
  SETUP_ARGS+=(--require-arduino-cli)
fi

if bash "$SCRIPT_DIR/setup_environment.sh" "${SETUP_ARGS[@]}"; then
    echo ""
    print_info "Environment setup completed successfully!"
    echo ""
else
    echo ""
    print_error "Environment setup failed!"
    echo "Please check the error messages above."
    exit 1
fi

# =============================================================================
# Step 2: Install Arduino Pico Board Manager
# =============================================================================
if [[ "$SKIP_ARDUINO" == false ]]; then
echo ""
echo "============================================================================="
echo "[STEP 2/4] Installing Arduino Pico board manager..."
echo "============================================================================="
echo ""

ARDUINO_ARGS=()
if [[ "$INSTALL_MISSING" == true ]]; then
  ARDUINO_ARGS+=(--install-missing)
fi
if [[ "$YES" == true ]]; then
  ARDUINO_ARGS+=(--yes)
fi

if bash "$SCRIPT_DIR/install_arduino_pico_board_manager.sh" "${ARDUINO_ARGS[@]}"; then
    echo ""
    print_info "Board manager installation completed successfully!"
    echo ""
else
    echo ""
    print_error "Board manager installation failed!"
    echo "Please check the error messages above."
    exit 1
fi

# =============================================================================
# Step 3: Compile and Upload Pico Firmware
# =============================================================================
echo ""
echo "============================================================================="
echo "[STEP 3/4] Compiling and uploading Pico firmware..."
echo "============================================================================="
echo ""
echo "NOTE: Make sure your Pico board is connected and in BOOTSEL mode if needed."
echo ""

if bash "$SCRIPT_DIR/compile_and_upload_pico.sh" "${ARDUINO_ARGS[@]}"; then
    echo ""
    print_info "Firmware compilation and upload completed successfully!"
    echo ""
else
    echo ""
    print_error "Firmware compilation/upload failed!"
    echo "Please check the error messages above."
    echo ""
    echo "You can try running compile_and_upload_pico.sh manually later."
    echo ""
    exit 1
fi
fi

# =============================================================================
# Step 4: Run Java Program
# =============================================================================
echo ""
echo "============================================================================="
echo "[STEP 4/4] Running Java: $MAIN_CLASS..."
echo "============================================================================="
echo ""

RUN_ARGS=()
if [[ "$INSTALL_MISSING" == true ]]; then
  RUN_ARGS+=(--install-missing)
fi
if [[ "$YES" == true ]]; then
  RUN_ARGS+=(--yes)
fi

if bash "$SCRIPT_DIR/run_java.sh" "${RUN_ARGS[@]}" "$MAIN_CLASS"; then
    echo ""
    print_info "Java program completed successfully!"
    echo ""
else
    echo ""
    print_error "Java program execution failed!"
    echo "Please check the error messages above."
    exit 1
fi

# =============================================================================
# All Steps Completed
# =============================================================================
echo ""
echo "============================================================================="
echo "All steps completed successfully!"
echo "============================================================================="
echo ""
echo "Summary:"
echo "  [OK] Environment setup"
if [[ "$SKIP_ARDUINO" == false ]]; then
  echo "  [OK] Arduino Pico board manager installed"
  echo "  [OK] Pico firmware compiled and uploaded"
fi
echo "  [OK] Java executed ($MAIN_CLASS)"
echo ""
echo "You can now:"
echo "  - Run ./run_java.sh HashMapExample"
echo "  - Run ./run_java.sh InMemoryDatabase"
echo "  - Run ./run_java.sh Lab2ExerciseSolution"
echo ""
