# =============================================================================
# run_java.ps1 - Compile and run a Java main class (Lab02)
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$MainClass,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ProgramArgs,

    [switch]$InstallMissing,
    [switch]$Yes,

    [string]$NativeAccess
)

$ErrorActionPreference = "Stop"

# Default: behave as if -InstallMissing was passed unless explicitly disabled.
if (-not $PSBoundParameters.ContainsKey('InstallMissing')) { $InstallMissing = $true }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envHelper = Join-Path $ScriptDir "scripts\env.ps1"
if (-not (Test-Path $envHelper)) {
    Write-Host "[run_java] ERROR: Missing required helper: $envHelper" -ForegroundColor Red
    exit 1
}

$envInfo = & $envHelper -InstallMissing:$InstallMissing -Yes:$Yes

$mvn = $envInfo.MVN_BIN
$javaExe = $envInfo.JAVA_EXE

Write-Host "[run_java] Using JAVA_HOME: $($envInfo.JAVA_HOME) (javac $($envInfo.JAVA_MAJOR))" -ForegroundColor Green
Write-Host "[run_java] Using Maven: $mvn" -ForegroundColor Green
Write-Host ""

New-Item -ItemType Directory -Path (Join-Path $ScriptDir "target") -Force | Out-Null

Write-Host "[run_java] Resolving dependencies..." -ForegroundColor Cyan
& $mvn -q dependency:resolve | Out-Null

Write-Host "[run_java] Compiling..." -ForegroundColor Cyan
& $mvn -q compile | Out-Null

Write-Host "[run_java] Building classpath..." -ForegroundColor Cyan
$classpathFile = Join-Path $ScriptDir "target\classpath.txt"
$classpathFileUnix = $classpathFile.Replace('\', '/')
& $mvn -q "-Dmdep.outputFile=$classpathFileUnix" dependency:build-classpath | Out-Null

$deps = ""
if (Test-Path $classpathFile) {
    $deps = (Get-Content $classpathFile -Raw).Trim()
}

$cp = "target\classes"
if ($deps) { $cp = "$cp;$deps" }

$javaArgs = @()
if ($envInfo.JAVA_MAJOR -ge 24) {
    if (-not $NativeAccess) { $NativeAccess = "ALL-UNNAMED" }
    if ($NativeAccess -ne "ALL-UNNAMED") {
        Write-Host "[run_java] Note: this runner uses the classpath (-cp); module-name targets may warn 'Unknown module'." -ForegroundColor DarkGray
    }
    $javaArgs += "--enable-native-access=$NativeAccess"
    Write-Host "[run_java] Native access enabled for: $NativeAccess" -ForegroundColor DarkGray
}

$nativeLibDir = Join-Path $ScriptDir "native-libs"
$dllPath = Join-Path $nativeLibDir "jSerialComm.dll"
if (Test-Path $dllPath) {
    $javaArgs = @("-DjSerialComm.library.path=$nativeLibDir") + $javaArgs
    Write-Host "[run_java] Using jSerialComm native library from: $nativeLibDir" -ForegroundColor DarkGray
} else {
    $tmpDir = Join-Path $ScriptDir "temp"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $javaArgs = @("-Djava.io.tmpdir=$tmpDir") + $javaArgs
    Write-Host "[run_java] Using temp dir for native extraction: $tmpDir" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "[run_java] Running $MainClass..." -ForegroundColor Cyan
Write-Host ""

& $javaExe @javaArgs -cp $cp $MainClass @ProgramArgs
