@echo off
REM =============================================================================
REM runme.bat - Complete Lab 2 Setup and Execution
REM =============================================================================
REM Steps:
REM   1. Setup environment (JDK, Maven, dependencies)
REM   2. Install Arduino Pico board manager (optional)
REM   3. Compile and upload Pico firmware (optional)
REM   4. Run a Java main class
REM =============================================================================

setlocal enabledelayedexpansion

REM ----------------------------------------------------------------------------
REM Args
REM ----------------------------------------------------------------------------
set "PS_FLAGS="
set "SETUP_ARGS="
set "RUN_ARGS="
set "SKIP_ARDUINO="
set "MAIN_CLASS=Lab2ExerciseSolution"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--install-missing" (
    set "PS_FLAGS=!PS_FLAGS! -InstallMissing"
    set "SETUP_ARGS=!SETUP_ARGS! --install-missing"
    set "RUN_ARGS=!RUN_ARGS! --install-missing"
    shift
    goto parse_args
)
if /i "%~1"=="--yes" (
    set "PS_FLAGS=!PS_FLAGS! -Yes"
    set "SETUP_ARGS=!SETUP_ARGS! --yes"
    set "RUN_ARGS=!RUN_ARGS! --yes"
    shift
    goto parse_args
)
if /i "%~1"=="--java-only" (
    set "SKIP_ARDUINO=1"
    shift
    goto parse_args
)
if /i "%~1"=="--skip-arduino" (
    set "SKIP_ARDUINO=1"
    shift
    goto parse_args
)
if /i "%~1"=="--run" (
    if "%~2"=="" (
        echo [ERROR] --run requires a class name
        exit /b 2
    )
    set "MAIN_CLASS=%~2"
    shift
    shift
    goto parse_args
)
echo [ERROR] Unknown option: %~1
exit /b 2
:args_done

echo.
echo =============================================================================
echo Lab 2 - Complete Setup and Execution
echo =============================================================================
echo.
echo This script will run the following steps:
echo   1. Setup environment (JDK, Maven, dependencies)
if not defined SKIP_ARDUINO (
    echo   2. Install Arduino Pico board manager
    echo   3. Compile and upload Pico firmware
)
echo   4. Run Java: %MAIN_CLASS%
echo.
echo Press Ctrl+C to cancel at any time.
echo.
pause

REM Get the script directory
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

REM =============================================================================
REM Step 1: Setup Environment
REM =============================================================================
echo.
echo =============================================================================
echo [STEP 1/4] Setting up environment...
echo =============================================================================
echo.
if not defined SKIP_ARDUINO (
    call "%SCRIPT_DIR%setup_environment.bat" %SETUP_ARGS% --require-arduino-cli
) else (
    call "%SCRIPT_DIR%setup_environment.bat" %SETUP_ARGS%
)
if errorlevel 1 (
    echo.
    echo [ERROR] Environment setup failed!
    echo Please check the error messages above.
    pause
    exit /b 1
)
echo.
echo [OK] Environment setup completed successfully!
echo.

REM =============================================================================
REM Step 2: Install Arduino Pico Board Manager
REM =============================================================================
if not defined SKIP_ARDUINO (
echo.
echo =============================================================================
echo [STEP 2/4] Installing Arduino Pico board manager...
echo =============================================================================
echo.
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_arduino_pico_board_manager.ps1" %PS_FLAGS%
if errorlevel 1 (
    echo.
    echo [ERROR] Board manager installation failed!
    echo Please check the error messages above.
    pause
    exit /b 1
)
echo.
echo [OK] Board manager installation completed successfully!
echo.

REM =============================================================================
REM Step 3: Compile and Upload Pico Firmware
REM =============================================================================
echo.
echo =============================================================================
echo [STEP 3/4] Compiling and uploading Pico firmware...
echo =============================================================================
echo.
echo NOTE: Make sure your Pico board is connected and in BOOTSEL mode if needed.
echo.
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%compile_and_upload_pico.ps1" %PS_FLAGS%
if errorlevel 1 (
    echo.
    echo [ERROR] Firmware compilation/upload failed!
    echo Please check the error messages above.
    echo.
    echo You can try running compile_and_upload_pico.ps1 manually later.
    echo.
    pause
    exit /b 1
)
echo.
echo [OK] Firmware compilation and upload completed successfully!
echo.
)

REM =============================================================================
REM Step 4: Run Java
REM =============================================================================
echo.
echo =============================================================================
echo [STEP 4/4] Running Java: %MAIN_CLASS%...
echo =============================================================================
echo.
call "%SCRIPT_DIR%run_java.bat" %RUN_ARGS% %MAIN_CLASS%
if errorlevel 1 (
    echo.
    echo [ERROR] Java execution failed!
    echo Please check the error messages above.
    pause
    exit /b 1
)
echo.
echo [OK] Java completed successfully!
echo.

REM =============================================================================
REM All Steps Completed
REM =============================================================================
echo.
echo =============================================================================
echo All steps completed successfully!
echo =============================================================================
echo.
echo Summary:
echo   [OK] Environment setup
if not defined SKIP_ARDUINO (
    echo   [OK] Arduino Pico board manager installed
    echo   [OK] Pico firmware compiled and uploaded
)
echo   [OK] Java executed (%MAIN_CLASS%)
echo.
echo You can now:
echo   - Run run_java.bat HashMapExample
echo   - Run run_java.bat InMemoryDatabase
echo   - Run run_java.bat Lab2ExerciseSolution
echo.
pause

endlocal

