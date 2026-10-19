@echo off
setlocal EnableExtensions DisableDelayedExpansion

chcp 65001 >nul

if "%~1"=="" (
    echo.
    echo  Word to InDesign JSON Converter
    echo  Drag one or more .docx files onto this icon.
    echo.
    if not "%W2ID_NO_PAUSE%"=="1" pause
    exit /b 1
)

setlocal EnableExtensions
set "SCRIPT=%~dp0docx_to_id_json.ps1"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

if not exist "%SCRIPT%" (
    echo.
    echo  ERROR: Cannot find docx_to_id_json.ps1 in the same folder.
    echo.
    if not "%W2ID_NO_PAUSE%"=="1" pause
    exit /b 1
)

set "FAIL_COUNT=0"

:loop
if "%~1"=="" goto done

if /I not "%~x1"==".docx" if /I not "%~x1"==".doc" (
    echo [SKIP] Not a .doc/.docx: "%~1"
    shift
    goto loop
)

echo.
echo ----------------------------------------
echo [RUN] "%~1"
echo.

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" "%~1"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo [FAIL] PowerShell exit code: %RC%
    echo.
    set /a FAIL_COUNT+=1
    shift
    goto loop
)

for %%I in ("%~1") do set "OUT=%%~dpnI.json"
if not exist "%OUT%" (
    echo.
    echo [FAIL] Output file not found: "%OUT%"
    echo.
    set /a FAIL_COUNT+=1
    shift
    goto loop
)

shift
goto loop

:done
echo.
echo ========================================
if "%FAIL_COUNT%"=="0" (
    echo  All files converted successfully.
) else (
    echo  Completed with %FAIL_COUNT% failure(s^).
)
echo ========================================
echo.
if not "%W2ID_NO_PAUSE%"=="1" pause
if not "%FAIL_COUNT%"=="0" exit /b 1
exit /b 0
