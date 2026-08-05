# =============================================================================
# Install Arduino Pico Board Manager (PowerShell)
# =============================================================================
# This script installs the RP2040 core for Arduino CLI to support
# Raspberry Pi Pico, Pico W, Pico 2, and Pico 2 W boards
# =============================================================================

[CmdletBinding()]
param(
    [switch]$InstallMissing,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

# Default: behave as if -InstallMissing was passed unless explicitly disabled.
if (-not $PSBoundParameters.ContainsKey('InstallMissing')) { $InstallMissing = $true }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Arduino Pico Board Manager Installation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Arduino CLI is required; Arduino IDE is optional." -ForegroundColor Yellow
Write-Host "If you want the IDE: https://arduino.cc/en/software" -ForegroundColor Yellow
Write-Host ""
Write-Host "Installing RP2040 core for Arduino CLI..." -ForegroundColor Green
Write-Host ""

# Detect/install toolchain (requires arduino-cli)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envHelper = Join-Path $ScriptDir "scripts\env.ps1"
if (-not (Test-Path $envHelper)) {
    Write-Host "ERROR: Missing required helper: $envHelper" -ForegroundColor Red
    exit 1
}

$envInfo = & $envHelper -RequireArduinoCli -InstallMissing:$InstallMissing -Yes:$Yes
$arduinoCli = $envInfo.ARDUINO_CLI
if (-not $arduinoCli) {
    Write-Host "ERROR: arduino-cli.exe not found!" -ForegroundColor Red
    Write-Host "Re-run with -InstallMissing (or accept the install prompt) to download a portable copy." -ForegroundColor Yellow
    exit 1
}

# Board manager URL for RP2040 core
$boardManagerUrl = "https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json"

# Step 1: Add board manager URL
Write-Host "Step 1: Adding board manager URL..." -ForegroundColor Cyan
Write-Host "URL: $boardManagerUrl" -ForegroundColor Gray
Write-Host ""

try {
    $output = & $arduinoCli config add board_manager.additional_urls $boardManagerUrl 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Check if URL already exists (that's okay)
        $outputString = $output | Out-String
        if ($outputString -match "already exists|duplicate") {
            Write-Host "Board manager URL already exists (this is okay)" -ForegroundColor Yellow
        } else {
            Write-Host $output
            throw "Failed to add board manager URL (exit code: $LASTEXITCODE)"
        }
    } else {
        Write-Host "Board manager URL added successfully!" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to add board manager URL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    try {
        Read-Host "Press Enter to exit" | Out-Null
    } catch {
        # Non-interactive mode, just exit
    }
    exit 1
}

Write-Host ""

# Step 2: Update core index
Write-Host "Step 2: Updating core index..." -ForegroundColor Cyan
Write-Host "This may take a few moments..." -ForegroundColor Gray
Write-Host ""

try {
    $output = & $arduinoCli core update-index 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "Failed to update core index (exit code: $LASTEXITCODE)"
    }
    Write-Host "Core index updated successfully!" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to update core index" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    try {
        Read-Host "Press Enter to exit" | Out-Null
    } catch {
        # Non-interactive mode, just exit
    }
    exit 1
}

Write-Host ""

# Step 3: Install RP2040 core
Write-Host "Step 3: Installing RP2040 core..." -ForegroundColor Cyan
Write-Host "This may take several minutes depending on your internet connection..." -ForegroundColor Gray
Write-Host ""

try {
    $output = & $arduinoCli core install rp2040:rp2040 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Check if core is already installed
        $outputString = $output | Out-String
        if ($outputString -match "already installed|already available") {
            Write-Host "RP2040 core is already installed (this is okay)" -ForegroundColor Yellow
        } else {
            Write-Host $output
            throw "Failed to install RP2040 core (exit code: $LASTEXITCODE)"
        }
    } else {
        Write-Host "RP2040 core installed successfully!" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to install RP2040 core" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    try {
        Read-Host "Press Enter to exit" | Out-Null
    } catch {
        # Non-interactive mode, just exit
    }
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "RP2040 core installation completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "You can now use the compile_and_upload_pico.ps1 script to upload sketches to your Pico board." -ForegroundColor Cyan
Write-Host ""

# Verify installation
Write-Host "Verifying installation..." -ForegroundColor Yellow
try {
    $coreList = & $arduinoCli core list 2>&1
    $coreListString = $coreList | Out-String
    if ($coreListString -match "rp2040:rp2040") {
        Write-Host "[OK] RP2040 core is installed and ready to use!" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] RP2040 core not found in core list" -ForegroundColor Yellow
        Write-Host "Core list output:" -ForegroundColor Gray
        Write-Host $coreList
    }
} catch {
    Write-Host "[WARNING] Could not verify installation (this is okay if the core was already installed)" -ForegroundColor Yellow
}

Write-Host ""
try {
    Read-Host "Press Enter to exit" | Out-Null
} catch {
    # Non-interactive mode, just exit
}

