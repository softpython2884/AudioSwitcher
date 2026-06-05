@echo off
REM Double-click to configure audio-switch (downloads svcl, picks your devices).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
