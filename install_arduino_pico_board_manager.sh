#!/bin/bash

# =============================================================================
# Install RP2040 Core for Arduino CLI (macOS/Linux)
# =============================================================================
# This script installs the RP2040 core (Raspberry Pi Pico) support for
# Arduino CLI by adding the board manager URL and installing the core.
# =============================================================================

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
INSTALL_MISSING=true
YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-missing) INSTALL_MISSING=true ;;
        --yes) YES=true ;;
        -h|--help)
            echo "Usage: ./install_arduino_pico_board_manager.sh [--install-missing] [--yes]"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 2
            ;;
    esac
    shift
done

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect/install toolchain (requires arduino-cli)
ENV_ARGS=(--emit --quiet --require-arduino-cli)
if [[ "$INSTALL_MISSING" == true ]]; then
    ENV_ARGS+=(--install-missing)
fi
if [[ "$YES" == true ]]; then
    ENV_ARGS+=(--yes)
fi

if [[ ! -f "$SCRIPT_DIR/scripts/env.sh" ]]; then
    print_error "Missing required helper: $SCRIPT_DIR/scripts/env.sh"
    exit 1
fi

# shellcheck disable=SC1091
eval "$("$SCRIPT_DIR/scripts/env.sh" "${ENV_ARGS[@]}")"

print_info "Using arduino-cli: $ARDUINO_CLI"

echo "Installing RP2040 core for Arduino CLI..."
echo

# Step 1: Add board manager URL
print_info "Adding board manager URL..."
if ! "$ARDUINO_CLI" config add board_manager.additional_urls https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json; then
    print_error "Failed to add board manager URL"
    exit 1
fi

echo
print_info "Board manager URL added successfully"
echo

# Step 2: Update core index
print_info "Updating core index..."
if ! "$ARDUINO_CLI" core update-index; then
    print_error "Failed to update core index"
    exit 1
fi

echo
print_info "Core index updated successfully"
echo

# Step 3: Install RP2040 core
print_info "Installing RP2040 core..."
print_warning "This may take a few minutes depending on your internet connection..."
if ! "$ARDUINO_CLI" core install rp2040:rp2040; then
    print_error "Failed to install RP2040 core"
    exit 1
fi

echo
echo "========================================"
print_info "RP2040 core installation completed successfully!"
echo "========================================"
echo
print_info "You can now compile and upload sketches to Raspberry Pi Pico boards"
echo
