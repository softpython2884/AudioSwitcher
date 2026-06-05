' Start the audio-switch daemon hidden (used for autostart)
Dim fso, here
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\audio-switch-daemon.ps1""", 0, False
