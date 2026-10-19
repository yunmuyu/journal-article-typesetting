@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_to_indesign.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" if not "%W2ID_NO_PAUSE%"=="1" pause
exit /b %RC%
