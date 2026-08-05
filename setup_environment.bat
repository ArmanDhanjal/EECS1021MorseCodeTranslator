@echo off
REM =============================================================================
REM setup_environment.bat - Prepare environment for Lab 2 execution
REM =============================================================================
REM This script prepares the environment by:
REM   1. Unblocking PowerShell scripts
REM   2. Setting PowerShell execution policy
REM   3. Detecting (and optionally installing) JDK/Maven/Arduino CLI
REM   4. Downloading Maven dependencies
REM   5. Compiling the project
REM =============================================================================

setlocal enabledelayedexpansion

echo.
echo =============================================================================
echo Lab 2 Environment Setup
echo =============================================================================
echo.

REM Get the script directory
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

REM ----------------------------------------------------------------------------
REM Args
REM ----------------------------------------------------------------------------
set "PS_FLAGS="
set "INSTALL_MISSING="
set "YES_MODE="
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--install-missing" (
    set "PS_FLAGS=%PS_FLAGS% -InstallMissing"
    set "INSTALL_MISSING=1"
)
if /i "%~1"=="--yes" (
    set "PS_FLAGS=%PS_FLAGS% -Yes"
    set "YES_MODE=1"
)
if /i "%~1"=="--require-arduino-cli" set "PS_FLAGS=%PS_FLAGS% -RequireArduinoCli"
shift
goto parse_args
:args_done

REM If user passed --yes, ensure portable installs are auto-accepted.
if defined YES_MODE if not defined INSTALL_MISSING (
    set "PS_FLAGS=%PS_FLAGS% -InstallMissing"
    set "INSTALL_MISSING=1"
)

REM Step 1: Unblock PowerShell scripts
echo [STEP 1/7] Unblocking PowerShell scripts...
powershell -Command "Get-ChildItem -Path '.' -Filter '*.ps1' -Recurse | ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }"
if %ERRORLEVEL% EQU 0 (
    echo [OK] PowerShell scripts unblocked
) else (
    echo [WARNING] Some PowerShell scripts may not have been unblocked
)
echo.

REM Step 2: Set PowerShell execution policy
echo [STEP 2/7] Setting PowerShell execution policy...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue"
if %ERRORLEVEL% EQU 0 (
    echo [OK] Execution policy set to RemoteSigned for current user
) else (
    echo [INFO] Execution policy may already be set or overridden
)
echo.

REM Step 3: Detect toolchain via PowerShell helper (optionally installs missing tools)
echo [STEP 3/7] Detecting toolchain (JDK/Maven/Arduino CLI)...
if not exist "%SCRIPT_DIR%scripts\env.ps1" (
    echo [ERROR] Missing required helper: %SCRIPT_DIR%scripts\env.ps1
    exit /b 1
)
set "RETRIED_WITH_INSTALL_MISSING="
:detect_toolchain
set "ENV_TMP=%TEMP%\\lab02_env_%RANDOM%_%RANDOM%.cmd"
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\\env.ps1" -EmitCmd %PS_FLAGS% > "%ENV_TMP%"
set "PS_EXIT=%ERRORLEVEL%"
if %PS_EXIT% NEQ 0 goto toolchain_failed
call "%ENV_TMP%"
if not defined JAVA_HOME (
    echo [ERROR] JAVA_HOME was not set by toolchain detection
    goto toolchain_failed
)
if not exist "%JAVA_HOME%\\bin\\java.exe" (
    echo [ERROR] JAVA_HOME is invalid: %JAVA_HOME%
    goto toolchain_failed
)
if not defined MVN_BIN (
    echo [ERROR] MVN_BIN was not set by toolchain detection
    goto toolchain_failed
)
del "%ENV_TMP%" >nul 2>nul
goto toolchain_ok

:toolchain_failed
echo [ERROR] Toolchain detection failed
if exist "%ENV_TMP%" (
    echo.
    echo [INFO] env.ps1 output (stdout):
    type "%ENV_TMP%"
    echo.
)
del "%ENV_TMP%" >nul 2>nul

REM If --install-missing wasn't specified, retry once with it enabled (legacy behavior).
if not defined INSTALL_MISSING if not defined RETRIED_WITH_INSTALL_MISSING goto retry_toolchain

echo [HINT] If you deleted .tools/, re-run with: setup_environment.bat --yes
exit /b 1

:retry_toolchain
echo [INFO] Retrying with --install-missing...
set "RETRIED_WITH_INSTALL_MISSING=1"
set "PS_FLAGS=%PS_FLAGS% -InstallMissing"
set "INSTALL_MISSING=1"
goto detect_toolchain

:toolchain_ok

REM Step 4: Set up environment variables for this session
echo [STEP 4/7] Setting up environment variables...
set "PATH=%JAVA_HOME%\bin;%PATH%"
echo [OK] JAVA_HOME set to: %JAVA_HOME%
echo [OK] PATH updated to include Java
echo.

REM Step 5: Download Maven dependencies
echo [STEP 5/7] Downloading Maven dependencies...
call "%MVN_BIN%" -q dependency:resolve
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to download Maven dependencies
    echo Please check your internet connection and Maven configuration
    exit /b 1
)
echo [OK] Maven dependencies downloaded
echo.

REM Step 6: Compile the project
echo [STEP 6/7] Compiling project...
call "%MVN_BIN%" -q compile
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Project compilation failed
    echo Please check the error messages above
    exit /b 1
)
echo [OK] Project compiled successfully
echo.

REM Step 7: Clean up corrupted jSerialComm temp directories
echo [STEP 7/7] Cleaning up jSerialComm temp directories...
powershell -Command "$paths = @((Join-Path $env:TEMP 'jSerialComm'), (Join-Path $env:USERPROFILE '.jSerialComm')); foreach ($p in $paths) { if (Test-Path $p) { $items = Get-ChildItem -Path $p -Recurse -ErrorAction SilentlyContinue; foreach ($item in $items) { if ($item.FullName -like '*\.\*' -or $item.FullName -like '*aarch64*' -or $item.FullName -like '*arm64*') { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue; break } } } }" 2>nul
echo [OK] Cleanup completed
echo.

REM Verify setup
REM Create temp directory for jSerialComm
if not exist "%SCRIPT_DIR%temp" (
    mkdir "%SCRIPT_DIR%temp"
    echo [OK] Created temp directory for jSerialComm
)

REM Extract jSerialComm native library to avoid temp directory issues (best-effort)
echo [INFO] Extracting jSerialComm native library (best-effort)...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\\extract_jserialcomm_native.ps1" 2>nul
echo.

echo =============================================================================
echo Verification
echo =============================================================================
echo.
echo Checking Java version:
"%JAVA_HOME%\bin\java.exe" -version
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Java is not working correctly
    exit /b 1
)
echo.

echo Checking Maven version:
call "%MVN_BIN%" -version
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Maven is not working correctly
    exit /b 1
)
echo.

echo Checking compiled classes:
if exist "target\classes\HashMapExample.class" (
    echo [OK] HashMapExample.class found
) else (
    echo [WARNING] HashMapExample.class not found
)
if exist "target\classes\InMemoryDatabase.class" (
    echo [OK] InMemoryDatabase.class found
) else (
    echo [WARNING] InMemoryDatabase.class not found
)
if exist "target\classes\Lab2ExerciseSolution.class" (
    echo [OK] Lab2ExerciseSolution.class found
) else (
    echo [WARNING] Lab2ExerciseSolution.class not found
)
echo.

echo =============================================================================
echo Setup Complete!
echo =============================================================================
echo.
echo You can now run:
echo   .\run_java.bat HashMapExample
echo   .\run_java.bat InMemoryDatabase
echo   .\run_java.bat Lab2ExerciseSolution
echo.
echo Note: This script sets JAVA_HOME/PATH for this process tree. For reusable
echo       env setup in cmd, use scripts\\env.cmd (or scripts\\env.ps1).
echo.
echo Troubleshooting:
echo   - If you see "NoClassDefFoundError" for jSerialComm, run this setup
echo     script again to ensure dependencies are downloaded.
echo   - If you see native library errors, ensure you're using the correct
echo     architecture (x64) version of jSerialComm for your system.
echo.

endlocal

