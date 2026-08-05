# =============================================================================
# Pico Serial Bridge - Compile and Upload Script (PowerShell)
# =============================================================================
# Enhanced version with improved port detection for RP2040/RP2350 boards
# =============================================================================

[CmdletBinding()]
param(
    [switch]$InstallMissing,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

# Default: behave as if -InstallMissing was passed unless explicitly disabled.
if (-not $PSBoundParameters.ContainsKey('InstallMissing')) { $InstallMissing = $true }

# Set the sketch directory
$SKETCH_DIR = "pico_serial_bridge_v1.0"
$SKETCH_NAME = "pico_serial_bridge_v1.0"

# Default FQBN for Raspberry Pi Pico 2 W
$FQBN = "rp2040:rp2040:rpipico2w"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pico Serial Bridge - Compile and Upload" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
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

Write-Host "Checking for connected boards..." -ForegroundColor Yellow
& $arduinoCli board list
Write-Host ""

# Ask user which board type
Write-Host "Select board type:"
Write-Host "1. Raspberry Pi Pico 2 (rpipico2)"
Write-Host "2. Raspberry Pi Pico 2 W (rpipico2w)"
Write-Host "3. Raspberry Pi Pico (rpipico)"
Write-Host "4. Raspberry Pi Pico W (rpipicow)"
try {
    $boardChoice = Read-Host "Enter choice (1-4, default is 2)"
} catch {
    # Non-interactive mode, use default
    Write-Host "Non-interactive mode: Using default board type (2 - Pico 2 W)" -ForegroundColor Yellow
    $boardChoice = "2"
}

switch ($boardChoice) {
    "1" { $FQBN = "rp2040:rp2040:rpipico2" }
    "3" { $FQBN = "rp2040:rp2040:rpipico" }
    "4" { $FQBN = "rp2040:rp2040:rpipicow" }
    default { $FQBN = "rp2040:rp2040:rpipico2w" }
}

Write-Host ""
Write-Host "Using FQBN: $FQBN" -ForegroundColor Green
Write-Host ""

# Step 1: Compile
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 1: Compiling sketch..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    & $arduinoCli compile --fqbn $FQBN $SKETCH_DIR
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Compilation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    try {
        Read-Host "Press Enter to exit" | Out-Null
    } catch {
        # Non-interactive mode, just exit
    }
    exit 1
}

Write-Host ""
Write-Host "Compilation successful!" -ForegroundColor Green
Write-Host ""

# Step 2: Detect port with enhanced detection
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 2: Detecting board port..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$PORT = $null

try {
    # Get board list output
    $boardListOutput = & $arduinoCli board list 2>&1 | Out-String

    # If the Pico is in BOOTSEL mode, arduino-cli shows it as "UF2_Board". This is
    # the most reliable upload target on Windows (mass storage UF2 flashing).
    if ($boardListOutput -match "(?m)^[\\s]*UF2_Board\\b") {
        $PORT = "UF2_Board"
        Write-Host "Detected UF2_Board (BOOTSEL/UF2). Using port: $PORT" -ForegroundColor Green
    }
    
    # Parse the output to find RP2040/RP2350 boards
    $lines = $boardListOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
    
    # Skip header lines
    $dataLines = $lines | Where-Object { 
        $_ -notmatch "^(Port|Protocol|Board Name|FQBN|Core)" -and 
        $_.Trim() -match "^\S"
    }
    
    $candidates = @()
    
    foreach ($line in $dataLines) {
        # Split by whitespace - arduino-cli board list format: Port Protocol Type BoardName FQBN Core
        $fields = $line -split '\s+', 6
        if ($fields.Count -ge 1) {
            $port = $fields[0].Trim()

            # UF2_Board is handled above (preferred for BOOTSEL uploads).
            if ($port -eq "UF2_Board") { continue }
            
            # Parse fields based on typical arduino-cli board list output
            # Format: Port Protocol Type BoardName FQBN Core
            # Note: Type field can contain spaces like "Serial Port (USB)", so we need to be careful
            $protocol = if ($fields.Count -ge 2) { $fields[1] } else { "" }
            $type = if ($fields.Count -ge 3) { $fields[2] } else { "" }
            $boardName = if ($fields.Count -ge 4) { $fields[3] } else { "" }
            # FQBN is typically the 5th field, but Type might have spaces, so we need to parse more carefully
            # For "COM6      serial   Serial Port (USB) Unknown", the fields are split incorrectly
            # Let's use a different approach - find FQBN by looking for the pattern or by position
            $lineFqbn = ""
            if ($fields.Count -ge 5) {
                # Try to find a field that looks like an FQBN (contains :)
                for ($i = 4; $i -lt $fields.Count; $i++) {
                    if ($fields[$i] -match ":") {
                        $lineFqbn = $fields[$i]
                        break
                    }
                }
                # If no FQBN pattern found, the last field before "Unknown" or empty might be it
                if (-not $lineFqbn -and $fields.Count -ge 5) {
                    $lineFqbn = $fields[4]
                }
            }
            
            # Check if this is an RP2040/RP2350 board
            # Look in FQBN, board name, or anywhere in the line
            $isRP2040 = $lineFqbn -match "rp2040|rp2350" -or 
                       $boardName -match "rp2040|rp2350|Pico|RP2040|RP2350" -or
                       $line -match "rp2040|rp2350"
            
            # Only consider serial COM ports for upload (not UF2_Board)
            if ($port -match "^COM\d+") {
                $portNum = [int]($port -replace 'COM', '')
                
                if ($isRP2040) {
                    $candidates += [PSCustomObject]@{
                        Port = $port
                        PortNumber = $portNum
                        FQBN = $lineFqbn
                        BoardName = $boardName
                        Line = $line
                        Priority = 1  # High priority for RP2040/RP2350
                    }
                } else {
                    # Lower priority for non-RP2040 COM ports
                    $candidates += [PSCustomObject]@{
                        Port = $port
                        PortNumber = $portNum
                        FQBN = $lineFqbn
                        BoardName = $boardName
                        Line = $line
                        Priority = 2
                    }
                }
            }
        }
    }
    
    if (-not $PORT) {
        # Sort candidates: first by priority (RP2040/RP2350 first), then by port number (higher first)
        $sortedCandidates = $candidates | Sort-Object -Property Priority, { -$_.PortNumber }
        
        if ($sortedCandidates.Count -gt 0) {
            $PORT = $sortedCandidates[0].Port
            Write-Host "Found board candidate(s):" -ForegroundColor Yellow
            foreach ($candidate in $sortedCandidates | Select-Object -First 5) {
                $priorityText = if ($candidate.Priority -eq 1) { "RP2040/RP2350" } else { "Other" }
                Write-Host "  - $($candidate.Port) ($priorityText, COM$($candidate.PortNumber))" -ForegroundColor Gray
            }
            Write-Host ""
            Write-Host "Selected port: $PORT" -ForegroundColor Green
        }
    }
    
} catch {
    Write-Host "Warning: Error during port detection: $($_.Exception.Message)" -ForegroundColor Yellow
}

# If no port found, ask user
if (-not $PORT) {
    Write-Host ""
    Write-Host "WARNING: Could not auto-detect port." -ForegroundColor Yellow
    Write-Host "Please check the board list above and enter the port manually." -ForegroundColor Yellow
    try {
        $PORT = Read-Host "Enter COM port (e.g., COM3)"
    } catch {
        # Non-interactive mode, cannot proceed without port
        Write-Host "ERROR: Cannot proceed in non-interactive mode without port detection!" -ForegroundColor Red
        exit 1
    }
    
    if (-not $PORT) {
        Write-Host "ERROR: No port specified!" -ForegroundColor Red
        try {
            Read-Host "Press Enter to exit" | Out-Null
        } catch {
            # Non-interactive mode, just exit
        }
        exit 1
    }
}

Write-Host "Using port: $PORT" -ForegroundColor Green
Write-Host ""

# Step 3: Upload
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 3: Uploading to board..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: Make sure your Pico is in BOOTSEL mode!" -ForegroundColor Yellow
Write-Host "(Hold BOOTSEL button while connecting USB, or press RESET + BOOTSEL)" -ForegroundColor Yellow
Write-Host ""
try {
    Read-Host "Press Enter to continue with upload" | Out-Null
} catch {
    # Non-interactive mode, wait a moment then continue
    Write-Host "Waiting 2 seconds before upload..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}

# Debug: Show what we're about to upload with
Write-Host "Upload command: $arduinoCli upload -p $PORT --fqbn $FQBN $SKETCH_DIR" -ForegroundColor Gray
Write-Host ""

try {
    $uploadOutput = & $arduinoCli upload -p $PORT --fqbn $FQBN $SKETCH_DIR 2>&1
    $uploadExitCode = $LASTEXITCODE
    
    if ($uploadExitCode -ne 0) {
        Write-Host $uploadOutput
        throw "Upload failed with exit code $uploadExitCode"
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Upload failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure:" -ForegroundColor Yellow
    Write-Host "  1. Board is in BOOTSEL mode" -ForegroundColor Yellow
    Write-Host "  2. Correct port is selected ($PORT)" -ForegroundColor Yellow
    Write-Host "  3. Correct FQBN is used ($FQBN)" -ForegroundColor Yellow
    try {
        Read-Host "Press Enter to exit" | Out-Null
    } catch {
        # Non-interactive mode, just exit
    }
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Upload successful!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
try {
    Read-Host "Press Enter to exit" | Out-Null
} catch {
    # Non-interactive mode, just exit
}

