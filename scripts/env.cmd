@echo off
REM Lab02 env bootstrap for cmd.exe
REM Sets JAVA_HOME / MVN_BIN / ARDUINO_CLI etc for the current cmd session.

set "SCRIPT_DIR=%~dp0"

REM Translate common GNU-style flags to PowerShell switches
set "PS_FLAGS="
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--install-missing" set "PS_FLAGS=%PS_FLAGS% -InstallMissing"
if /i "%~1"=="-InstallMissing" set "PS_FLAGS=%PS_FLAGS% -InstallMissing"
if /i "%~1"=="--yes" set "PS_FLAGS=%PS_FLAGS% -Yes"
if /i "%~1"=="-Yes" set "PS_FLAGS=%PS_FLAGS% -Yes"
if /i "%~1"=="--require-arduino-cli" set "PS_FLAGS=%PS_FLAGS% -RequireArduinoCli"
if /i "%~1"=="-RequireArduinoCli" set "PS_FLAGS=%PS_FLAGS% -RequireArduinoCli"
shift
goto parse_args
:args_done

set "ENV_TMP=%TEMP%\\lab02_env_%RANDOM%_%RANDOM%.cmd"
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%env.ps1" -EmitCmd %PS_FLAGS% > "%ENV_TMP%"
set "PS_EXIT=%ERRORLEVEL%"
if %PS_EXIT% NEQ 0 (
  del "%ENV_TMP%" >nul 2>nul
  exit /b %PS_EXIT%
)
call "%ENV_TMP%"
set "CALL_EXIT=%ERRORLEVEL%"
del "%ENV_TMP%" >nul 2>nul
exit /b %CALL_EXIT%
