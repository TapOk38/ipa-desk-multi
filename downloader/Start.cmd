@echo off
setlocal
set "GODEBUG=http2client=0"
set "HTTP_PROXY="
set "HTTPS_PROXY="
set "ALL_PROXY="
set "NO_PROXY=*"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0IPA-Desk.ps1"
if errorlevel 1 (
  echo TapOk IPA Downloader could not start.
  pause
)
