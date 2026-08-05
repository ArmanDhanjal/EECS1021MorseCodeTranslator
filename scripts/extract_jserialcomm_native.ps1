# =============================================================================
# extract_jserialcomm_native.ps1 - Extract the correct jSerialComm native library
# =============================================================================
#
# Best-effort helper used by setup_environment.bat. This script:
#   - detects the jSerialComm version from pom.xml (fallback: latest in ~/.m2)
#   - finds the corresponding jar in the Maven local repository
#   - extracts the host-native Windows DLL from the jar
#   - writes it to <Lab02>/native-libs/jSerialComm.dll
#
# It MUST NOT fail the overall setup flow if extraction isn't possible.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Warn([string]$Message) {
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

try {
    $Lab02Root = Split-Path -Parent $PSScriptRoot
    $pomPath = Join-Path $Lab02Root "pom.xml"

    $ver = $null
    if (Test-Path $pomPath) {
        $pom = Get-Content $pomPath -Raw
        $m = [regex]::Match(
            $pom,
            '(?is)<dependency>\s*<groupId>\s*com\.fazecast\s*</groupId>\s*<artifactId>\s*jSerialComm\s*</artifactId>.*?<version>\s*([^<\s]+)\s*</version>'
        )
        if ($m.Success) { $ver = $m.Groups[1].Value.Trim() }
    }

    # If pom.xml uses a property, fall back to "latest installed" in ~/.m2.
    if (-not $ver -or $ver -match '[$][{]') {
        $base = Join-Path $env:USERPROFILE ".m2\repository\com\fazecast\jSerialComm"
        if (Test-Path $base) {
            $ver = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name |
                Sort-Object { try { [Version]$_ } catch { [Version]"0.0.0" } } -Descending |
                Select-Object -First 1
        }
    }

    if (-not $ver) {
        Write-Warn "Could not determine jSerialComm version. Skipping native extraction."
        exit 0
    }

    $mavenRepo = Join-Path $env:USERPROFILE ".m2\repository"
    $jarPath = Join-Path $mavenRepo "com\fazecast\jSerialComm\$ver\jSerialComm-$ver.jar"
    if (-not (Test-Path $jarPath)) {
        Write-Warn "jSerialComm jar not found: $jarPath"
        exit 0
    }

    $nativeLibDir = Join-Path $Lab02Root "native-libs"
    New-Item -ItemType Directory -Path $nativeLibDir -Force | Out-Null
    $dllPath = Join-Path $nativeLibDir "jSerialComm.dll"

    $extractDir = Join-Path $Lab02Root "target\jSerialComm_native_extract"
    if (Test-Path $extractDir) {
        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($jarPath, $extractDir)

    $archPath = if ([Environment]::Is64BitOperatingSystem) { "Windows\\x86_64\\jSerialComm.dll" } else { "Windows\\x86\\jSerialComm.dll" }
    $sourceDll = Join-Path $extractDir $archPath
    if (-not (Test-Path $sourceDll)) {
        Write-Warn "Could not find native DLL in jar at: $archPath"
        exit 0
    }

    Copy-Item -Path $sourceDll -Destination $dllPath -Force
    Write-Ok "Native library extracted (jSerialComm $ver)"
} catch {
    Write-Warn $_.Exception.Message
    exit 0
} finally {
    try {
        if ($extractDir -and (Test-Path $extractDir)) {
            Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # ignore
    }
}

