@echo off
set "HERE=%~dp0"
echo Installing audio-switch daemon to startup...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h=$env:HERE; $s=New-Object -ComObject WScript.Shell; $p=Join-Path ([Environment]::GetFolderPath('Startup')) 'audio-switch-daemon.lnk'; $l=$s.CreateShortcut($p); $l.TargetPath=(Join-Path $h 'daemon-start.vbs'); $l.WorkingDirectory=$h; $l.Save(); Start-Process (Join-Path $h 'daemon-start.vbs')"
echo.
echo Done. The daemon now starts at login and is running.
echo In Stream Deck, point your two buttons at trigger-1.cmd and trigger-2.cmd.
pause
