' Lanceur "Sortie Casque" pour Stream Deck (aucune fenetre ne s'affiche)
Dim fso, dossier, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
dossier = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File """ & dossier & "\audio-switch.ps1"" 2"
CreateObject("WScript.Shell").Run cmd, 0, False
