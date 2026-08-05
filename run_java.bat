@echo off
REM =============================================================================
REM run_java.bat - Compile and run a Java main class (Lab02)
REM =============================================================================

set "SCRIPT_DIR=%~dp0"
setlocal enabledelayedexpansion

set "PS_FLAGS="
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--install-missing" set "PS_FLAGS=%PS_FLAGS% -InstallMissing" & shift & goto parse_args
if /i "%~1"=="--yes" set "PS_FLAGS=%PS_FLAGS% -Yes" & shift & goto parse_args
if /i "%~1"=="--native-access" (
  if "%~2"=="" (
    echo ERROR: --native-access requires a value: ALL-UNNAMED or com.fazecast.jSerialComm
    exit /b 2
  )
  set "PS_FLAGS=%PS_FLAGS% -NativeAccess %~2"
  shift
  shift
  goto parse_args
)
goto args_done
:args_done

if "%~1"=="" (
  echo Usage: run_java.bat [--yes] [--install-missing] MainClass [args...]
  exit /b 2
)

REM %* is NOT affected by SHIFT. Collect remaining args explicitly.
set "FORWARD_ARGS="
:collect_args
if "%~1"=="" goto collected
set "FORWARD_ARGS=!FORWARD_ARGS! \"%~1\""
shift
goto collect_args
:collected

powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run_java.ps1" %PS_FLAGS% %FORWARD_ARGS%
endlocal & exit /b %ERRORLEVEL%
