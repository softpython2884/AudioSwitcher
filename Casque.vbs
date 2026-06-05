' Auto-generated launcher for Stream Deck (no window flashes)
Dim fso, here, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File """ & here & "\audio-switch.ps1"" 2"
CreateObject("WScript.Shell").Run cmd, 0, False
