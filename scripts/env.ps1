# Lab02 toolchain detection and (optional) portable installer

[CmdletBinding()]
param(
    [switch]$InstallMissing,
    [switch]$Yes,
    [switch]$RequireArduinoCli,
    [switch]$EmitCmd
)

$ErrorActionPreference = "Stop"
if ($EmitCmd) { $ProgressPreference = "SilentlyContinue" }

# Default: behave as if -InstallMissing was passed unless explicitly disabled.
if (-not $PSBoundParameters.ContainsKey('InstallMissing')) { $InstallMissing = $true }

$Lab02Root = Split-Path -Parent $PSScriptRoot
$ToolsDir = if ($env:LAB02_TOOLS_DIR) { $env:LAB02_TOOLS_DIR } else { Join-Path $Lab02Root ".tools" }
$DownloadsDir = Join-Path $ToolsDir "downloads"

function Write-EnvStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )

    if ($EmitCmd) {
        # When this script is called with -EmitCmd, stdout must contain ONLY
        # `set "NAME=value"` lines so cmd.exe wrappers can safely consume them.
        [Console]::Error.WriteLine($Message)
        return
    }

    Write-Host $Message -ForegroundColor $ForegroundColor
}

function New-Dirs {
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $DownloadsDir -Force | Out-Null
}

function Prompt-YesNo {
    param([string]$Message)
    if ($Yes) { return $true }
    try {
        $reply = Read-Host "$Message [y/N]"
    } catch {
        return $false
    }
    return ($reply -match '^(y|yes)$')
}

function Get-RequiredJavaMajor {
    $override = $env:LAB02_REQUIRED_JAVA_MAJOR
    if ($override) { return [int]$override }

    $baseline = 25

    $pom = Join-Path $Lab02Root "pom.xml"
    if (-not (Test-Path $pom)) { return $baseline }

    $text = Get-Content $pom -Raw
    $patterns = @(
        '<maven\.compiler\.release>(\d+)</maven\.compiler\.release>',
        '<maven\.compiler\.source>(\d+)</maven\.compiler\.source>',
        '<maven\.compiler\.target>(\d+)</maven\.compiler\.target>'
    )
    foreach ($p in $patterns) {
        $m = [regex]::Match($text, $p)
        if ($m.Success) {
            $fromPom = [int]$m.Groups[1].Value
            return [Math]::Max($baseline, $fromPom)
        }
    }

    return $baseline
}

function Get-JavacMajor {
    param([string]$JavacExe)
    $out = & $JavacExe -version 2>&1 | Out-String
    $out = $out.Trim()
    $m = [regex]::Match($out, 'javac\s+([0-9]+)(\..*)?$')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    $m = [regex]::Match($out, 'javac\s+1\.([0-9]+)\..*$')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    throw "Could not parse javac version from: $out"
}

function Get-JavaInfoFromHome {
    param([string]$JavaHome)
    if (-not $JavaHome) { return $null }

    # Avoid `$home` because `$HOME` is a built-in read-only variable in Windows
    # PowerShell (and variable names are case-insensitive).
    $javaHomePath = $JavaHome
    $javac = Join-Path $javaHomePath "bin\javac.exe"
    $java = Join-Path $javaHomePath "bin\java.exe"
    if ((Test-Path $javac) -and (Test-Path $java)) {
        return [PSCustomObject]@{
            JavaHome = $javaHomePath
            JavacExe = $javac
            JavaExe = $java
        }
    }

    # macOS bundle layout (if running in PowerShell on macOS)
    $javacMac = Join-Path $javaHomePath "Contents/Home/bin/javac"
    $javaMac = Join-Path $javaHomePath "Contents/Home/bin/java"
    if ((Test-Path $javacMac) -and (Test-Path $javaMac)) {
        $realHome = Join-Path $javaHomePath "Contents/Home"
        return [PSCustomObject]@{
            JavaHome = $realHome
            JavacExe = $javacMac
            JavaExe = $javaMac
        }
    }

    return $null
}

function Find-JavaInfo {
    # 1) JAVA_HOME
    $info = Get-JavaInfoFromHome -JavaHome $env:JAVA_HOME
    if ($info) { return $info }

    # 2) project-local marker
    $marker = Join-Path $ToolsDir "jdk\.java_home"
    if (Test-Path $marker) {
        $javaHomePath = (Get-Content $marker -Raw).Trim()
        $info = Get-JavaInfoFromHome -JavaHome $javaHomePath
        if ($info) { return $info }
    }

    # 3) project-local tools
    $jdkDir = Join-Path $ToolsDir "jdk"
    if (Test-Path $jdkDir) {
        $best = $null
        $bestMajor = -1

        $dirs = Get-ChildItem -Path $jdkDir -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            $info = Get-JavaInfoFromHome -JavaHome $d.FullName
            if (-not $info) { continue }

            try {
                $m = Get-JavacMajor -JavacExe $info.JavacExe
            } catch {
                continue
            }

            if ($m -gt $bestMajor) {
                $bestMajor = $m
                $best = $info
            }
        }

        if ($best) { return $best }
    }

    # 4) system javac/java
    $javacCmd = Get-Command "javac.exe" -ErrorAction SilentlyContinue
    $javaCmd = Get-Command "java.exe" -ErrorAction SilentlyContinue
    if ($javacCmd -and $javaCmd) {
        $javaHomePath = Split-Path -Parent (Split-Path -Parent $javacCmd.Source)
        $info = Get-JavaInfoFromHome -JavaHome $javaHomePath
        if ($info) { return $info }
    }

    return $null
}

function Install-Jdk {
    param([int]$Major)

    New-Dirs
    $os = "windows"
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    if ($arch -eq "x86") { throw "32-bit Windows is not supported by this installer script." }

    $dest = Join-Path $ToolsDir "jdk"

    # If the requested major is already present under the tools directory, prefer it
    # without re-downloading (and update the marker file).
    if (Test-Path $dest) {
        $existing = Get-ChildItem -Path $dest -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "jdk-$Major*" } |
            Sort-Object -Property LastWriteTime -Descending

        foreach ($d in $existing) {
            $info = Get-JavaInfoFromHome -JavaHome $d.FullName
            if (-not $info) { continue }

            try {
                $m = Get-JavacMajor -JavacExe $info.JavacExe
            } catch {
                continue
            }

            if ($m -eq $Major) {
                Set-Content -Path (Join-Path $dest ".java_home") -Value $info.JavaHome
                return $info
            }
        }
    }

    $url = "https://api.adoptium.net/v3/binary/latest/$Major/ga/$os/$arch/jdk/hotspot/normal/eclipse"
    $zipPath = Join-Path $DownloadsDir "jdk-$Major-$os-$arch.zip"

    Write-EnvStatus "[env] Downloading JDK $Major ($os/$arch)..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    if (Test-Path $dest) {
        # Keep other versions; extraction will create a new folder
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    } else {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    Expand-Archive -Path $zipPath -DestinationPath $dest -Force

    # Prefer the just-installed major when multiple JDKs exist under $dest.
    $candidateDirs = Get-ChildItem -Path $dest -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "jdk-$Major*" } |
        Sort-Object -Property LastWriteTime -Descending

    foreach ($d in $candidateDirs) {
        $info = Get-JavaInfoFromHome -JavaHome $d.FullName
        if (-not $info) { continue }

        try {
            $m = Get-JavacMajor -JavacExe $info.JavacExe
        } catch {
            continue
        }

        if ($m -eq $Major) {
            Set-Content -Path (Join-Path $dest ".java_home") -Value $info.JavaHome
            return $info
        }
    }

    throw "JDK extracted, but could not locate a Java home for major $Major under $dest"
}

function Ensure-Java {
    $required = Get-RequiredJavaMajor
    $info = Find-JavaInfo

    if (-not $info) {
        if ($InstallMissing -and (Prompt-YesNo "Java (JDK) not found. Download a portable JDK $required?")) {
            $info = Install-Jdk -Major $required
        } else {
            throw "Java (JDK) not found. Install JDK $required+ or re-run and accept the portable install prompt."
        }
    }

    $major = Get-JavacMajor -JavacExe $info.JavacExe
    if ($major -lt $required) {
        if ($InstallMissing -and (Prompt-YesNo "JDK $major found but $required+ is required. Download JDK $required?")) {
            $info = Install-Jdk -Major $required
            $major = Get-JavacMajor -JavacExe $info.JavacExe
        } else {
            throw "JDK $required+ required (found javac $major)."
        }
    }

    $env:JAVA_HOME = $info.JavaHome
    return [PSCustomObject]@{
        JavaHome = $info.JavaHome
        JavaExe = $info.JavaExe
        JavacExe = $info.JavacExe
        JavaMajor = $major
    }
}

function Get-DesiredMavenVersion {
    $override = $env:LAB02_MAVEN_VERSION
    if ($override) { return $override }
    return "3.9.6"
}

function Find-MavenBin {
    # 1) Maven Wrapper in repo (preferred)
    $mvnw = Join-Path $Lab02Root "mvnw.cmd"
    if (Test-Path $mvnw) { return $mvnw }

    # 2) Previously installed portable Maven (marker file)
    $marker = Join-Path $ToolsDir "maven\.mvn_bin"
    if (Test-Path $marker) {
        $p = (Get-Content $marker -Raw).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }

    # 3) Previously installed portable Maven (best-effort search)
    $mavenRoot = Join-Path $ToolsDir "maven"
    if (Test-Path $mavenRoot) {
        $mvnCmd = Get-ChildItem -Path $mavenRoot -Recurse -File -Filter "mvn.cmd" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($mvnCmd) { return $mvnCmd.FullName }
    }

    # 4) System Maven
    $mvn = Get-Command "mvn.cmd" -ErrorAction SilentlyContinue
    if ($mvn) { return $mvn.Source }

    $mvn = Get-Command "mvn.exe" -ErrorAction SilentlyContinue
    if ($mvn) { return $mvn.Source }

    return $null
}

function Install-Maven {
    param([string]$Version)

    New-Dirs
    $ver = if ($Version) { $Version } else { Get-DesiredMavenVersion }

    $asset = "apache-maven-$ver-bin.zip"
    $url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/$ver/$asset"
    $zipPath = Join-Path $DownloadsDir $asset

    $destRoot = Join-Path $ToolsDir "maven"
    $destVer = Join-Path $destRoot "apache-maven-$ver"

    Write-EnvStatus "[env] Downloading Maven $ver..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    if (Test-Path $destVer) { Remove-Item -Path $destVer -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null

    Expand-Archive -Path $zipPath -DestinationPath $destRoot -Force

    $mvnCmd = Join-Path $destVer "bin\mvn.cmd"
    if (-not (Test-Path $mvnCmd)) { throw "Maven extracted, but mvn.cmd not found under $destVer" }

    Set-Content -Path (Join-Path $destRoot ".mvn_bin") -Value $mvnCmd
    return $mvnCmd
}

function Ensure-Maven {
    $mvn = Find-MavenBin
    if (-not $mvn) {
        if ($InstallMissing -and (Prompt-YesNo "Maven not found. Download a portable Maven?")) {
            $mvn = Install-Maven -Version (Get-DesiredMavenVersion)
        }
    }

    if (-not $mvn) {
        throw "Maven not found. Install Maven (or add the Maven Wrapper), or re-run and accept the portable install prompt."
    }

    $env:MVN_BIN = $mvn
    return $mvn
}

function Find-ArduinoCli {
    if ($env:ARDUINO_CLI -and (Test-Path $env:ARDUINO_CLI)) { return $env:ARDUINO_CLI }

    $local = Join-Path $ToolsDir "arduino-cli\arduino-cli.exe"
    if (Test-Path $local) { return $local }

    $here = Join-Path $Lab02Root "arduino-cli.exe"
    if (Test-Path $here) { return $here }

    $cmd = Get-Command "arduino-cli.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Get-LatestArduinoCliTag {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/arduino/arduino-cli/releases/latest" -Headers @{ "User-Agent" = "Lab02-env" }
    return $release.tag_name
}

function Install-ArduinoCli {
    New-Dirs

    $tag = Get-LatestArduinoCliTag
    $ver = $tag.TrimStart('v')
    $asset = "arduino-cli_${ver}_Windows_64bit.zip"
    $url = "https://github.com/arduino/arduino-cli/releases/download/$tag/$asset"
    $zipPath = Join-Path $DownloadsDir $asset
    $destRoot = Join-Path $ToolsDir "arduino-cli"
    $destVer = Join-Path $destRoot $ver

    Write-EnvStatus "[env] Downloading arduino-cli $ver..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    if (Test-Path $destVer) { Remove-Item -Path $destVer -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $destVer -Force | Out-Null

    Expand-Archive -Path $zipPath -DestinationPath $destVer -Force

    $exe = Get-ChildItem -Path $destVer -Recurse -File -Filter "arduino-cli.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) { throw "arduino-cli extracted, but arduino-cli.exe not found under $destVer" }

    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
    Copy-Item -Path $exe.FullName -Destination (Join-Path $destRoot "arduino-cli.exe") -Force

    $final = Join-Path $destRoot "arduino-cli.exe"
    $env:ARDUINO_CLI = $final
    return $final
}

function Ensure-ArduinoCli {
    $cli = Find-ArduinoCli

    # Only offer to install arduino-cli when it is required by the caller.
    if (-not $cli -and $RequireArduinoCli) {
        if ($InstallMissing -and (Prompt-YesNo "arduino-cli not found. Download a portable arduino-cli?")) {
            $cli = Install-ArduinoCli
        }
    }

    if (-not $cli -and $RequireArduinoCli) {
        throw "arduino-cli not found. Install it, or re-run and accept the portable install prompt."
    }

    if ($cli) { $env:ARDUINO_CLI = $cli }
    return $cli
}

function Find-ArduinoIde {
    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Arduino IDE\Arduino IDE.exe")
        $candidates += (Join-Path $env:ProgramFiles "Arduino\arduino.exe")
    }
    if ($env:ProgramFiles -and ${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Arduino IDE\Arduino IDE.exe")
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Arduino\arduino.exe")
    }
    if ($env:LocalAppData) {
        $candidates += (Join-Path $env:LocalAppData "Programs\Arduino IDE\Arduino IDE.exe")
    }

    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

$javaInfo = Ensure-Java
$mvnBin = Ensure-Maven

$arduinoCli = Ensure-ArduinoCli
$arduinoIde = Find-ArduinoIde

$envInfo = [PSCustomObject]@{
    LAB02_ROOT = $Lab02Root
    LAB02_TOOLS_DIR = $ToolsDir
    JAVA_HOME = $javaInfo.JavaHome
    JAVA_EXE = $javaInfo.JavaExe
    JAVAC_EXE = $javaInfo.JavacExe
    JAVA_MAJOR = $javaInfo.JavaMajor
    MVN_BIN = $mvnBin
    ARDUINO_CLI = $arduinoCli
    ARDUINO_IDE_PATH = $arduinoIde
}

if ($EmitCmd) {
    # IMPORTANT: Emit ONLY set-lines so .bat can safely consume them.
    foreach ($kv in $envInfo.PSObject.Properties) {
        $name = $kv.Name
        $value = [string]$kv.Value
        if ($null -eq $kv.Value) { $value = "" }
        $escaped = $value.Replace('"', '""')
        Write-Output ("set `"{0}={1}`"" -f $name, $escaped)
    }
    exit 0
}

Write-Output $envInfo
