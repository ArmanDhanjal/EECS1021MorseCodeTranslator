#!/bin/bash

# =============================================================================
# Pico Serial Bridge - Compile and Upload Script (macOS/Linux)
# =============================================================================
# This script compiles and uploads the Serial Bridge firmware to a Raspberry
# Pi Pico board using arduino-cli.
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

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Set the sketch directory
SKETCH_DIR="pico_serial_bridge_v1.0"
SKETCH_NAME="pico_serial_bridge_v1.0"

# Default FQBN for Raspberry Pi Pico 2 W (change if needed)
# Options: rp2040:rp2040:rpipico2 (Pico 2) or rp2040:rp2040:rpipico2w (Pico 2 W)
FQBN="rp2040:rp2040:rpipico2w"

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
            echo "Usage: ./compile_and_upload_pico.sh [--install-missing] [--yes]"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 2
            ;;
    esac
    shift
done

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

echo "========================================"
echo "Pico Serial Bridge - Compile and Upload"
echo "========================================"
echo

print_info "Checking for connected boards..."
"$ARDUINO_CLI" board list
echo

# Ask user which board type
echo "Select board type:"
echo "1. Raspberry Pi Pico 2 (rpipico2)"
echo "2. Raspberry Pi Pico 2 W (rpipico2w)"
echo "3. Raspberry Pi Pico (rpipico)"
echo "4. Raspberry Pi Pico W (rpipicow)"
read -p "Enter choice (1-4, default is 2): " BOARD_CHOICE

# Set FQBN based on user choice
if [ "$BOARD_CHOICE" = "1" ]; then
    FQBN="rp2040:rp2040:rpipico2"
elif [ "$BOARD_CHOICE" = "3" ]; then
    FQBN="rp2040:rp2040:rpipico"
elif [ "$BOARD_CHOICE" = "4" ]; then
    FQBN="rp2040:rp2040:rpipicow"
fi

echo
print_info "Using FQBN: $FQBN"
echo

# Step 1: Compile
echo "========================================"
echo "Step 1: Compiling sketch..."
echo "========================================"
if ! "$ARDUINO_CLI" compile --fqbn "$FQBN" "$SKETCH_DIR"; then
    echo
    print_error "Compilation failed!"
    exit 1
fi

echo
print_info "Compilation successful!"
echo

# Step 2: Detect port
echo "========================================"
echo "Step 2: Detecting board port..."
echo "========================================"

PORT=""
# Get board list output
BOARD_LIST=$("$ARDUINO_CLI" board list 2>/dev/null || true)

# Strategy 1: Look for rp2040 boards in the FQBN column
while IFS= read -r line; do
    # Skip header line
    if echo "$line" | grep -qiE "^(Port|Protocol)"; then
        continue
    fi
    # Look for rp2040 in the FQBN column (usually 4th or 5th column)
    if echo "$line" | grep -qi "rp2040"; then
        PORT=$(echo "$line" | awk '{print $1}')
        # Verify it's a valid serial port
        if [[ "$PORT" =~ ^/dev/(cu|tty)\. ]] && [[ ! "$PORT" =~ (Bluetooth|debug-console) ]]; then
            print_info "Found rp2040 board on port: $PORT"
            break
        fi
    fi
done <<< "$BOARD_LIST"

# Strategy 2: If no rp2040 found, look for UF2 boards (BOOTSEL mode)
if [ -z "$PORT" ]; then
    while IFS= read -r line; do
        if echo "$line" | grep -qiE "^(Port|Protocol)"; then
            continue
        fi
        # Check if this line has UF2 protocol or UF2_Board identifier
        if echo "$line" | grep -qi "uf2conv\|UF2"; then
            PORT=$(echo "$line" | awk '{print $1}')
            # UF2_Board is a valid identifier for arduino-cli upload
            if [[ "$PORT" == "UF2_Board" ]] || [[ "$PORT" =~ ^/dev/(cu|tty)\. ]]; then
                print_info "Found UF2 board (BOOTSEL mode) on: $PORT"
                break
            fi
        fi
    done <<< "$BOARD_LIST"
fi

# Strategy 3: Look for any USB serial port (usbmodem on macOS, ttyACM/ttyUSB on Linux)
# Prefer /dev/cu.* over /dev/tty.* on macOS (cu is call-out, better for uploads)
if [ -z "$PORT" ]; then
    PREFERRED_PORT=""
    FALLBACK_PORT=""
    while IFS= read -r line; do
        if echo "$line" | grep -qiE "^(Port|Protocol)"; then
            continue
        fi
        CANDIDATE=$(echo "$line" | awk '{print $1}')
        # Look for USB serial ports, excluding Bluetooth and debug ports
        if [[ "$CANDIDATE" =~ ^/dev/cu\.usbmodem ]] || \
           [[ "$CANDIDATE" =~ ^/dev/tty\.usbmodem ]] || \
           [[ "$CANDIDATE" =~ ^/dev/ttyACM ]] || \
           [[ "$CANDIDATE" =~ ^/dev/ttyUSB ]]; then
            if [[ ! "$CANDIDATE" =~ (Bluetooth|debug-console) ]]; then
                # Prefer /dev/cu.* ports (call-out, better for uploads)
                if [[ "$CANDIDATE" =~ ^/dev/cu\. ]] && [ -z "$PREFERRED_PORT" ]; then
                    PREFERRED_PORT="$CANDIDATE"
                elif [[ "$CANDIDATE" =~ ^/dev/tty\. ]] && [ -z "$FALLBACK_PORT" ]; then
                    FALLBACK_PORT="$CANDIDATE"
                fi
            fi
        fi
    done <<< "$BOARD_LIST"
    
    # Use preferred port if available, otherwise fallback
    if [ -n "$PREFERRED_PORT" ]; then
        PORT="$PREFERRED_PORT"
        print_info "Found USB serial port (preferred): $PORT"
    elif [ -n "$FALLBACK_PORT" ]; then
        PORT="$FALLBACK_PORT"
        print_info "Found USB serial port: $PORT"
    fi
fi

# If still no port found, ask user
if [ -z "$PORT" ]; then
    echo
    print_warning "Could not auto-detect port. Please enter manually."
    echo
    echo "Available ports from arduino-cli:"
    echo "$BOARD_LIST" | grep -v "^$"
    echo
    echo "On macOS, ports are typically /dev/cu.usbmodem* or /dev/tty.usbmodem*"
    echo "On Linux, ports are typically /dev/ttyACM* or /dev/ttyUSB*"
    echo "For UF2 uploads (BOOTSEL mode), you may see 'UF2_Board'"
    read -p "Enter port: " PORT
fi

print_info "Using port: $PORT"
echo

# Step 3: Upload
echo "========================================"
echo "Step 3: Uploading to board..."
echo "========================================"
echo
print_warning "IMPORTANT: Make sure your Pico is in BOOTSEL mode!"
echo "(Hold BOOTSEL button while connecting USB, or press RESET + BOOTSEL)"
echo
read -p "Press Enter to continue with upload..."

if ! "$ARDUINO_CLI" upload -p "$PORT" --fqbn "$FQBN" "$SKETCH_DIR"; then
    echo
    print_error "Upload failed!"
    echo "Make sure:"
    echo "  1. Board is in BOOTSEL mode"
    echo "  2. Correct port is selected"
    echo "  3. Correct FQBN is used"
    exit 1
fi

echo
echo "========================================"
print_info "Upload successful!"
echo "========================================"
echo
