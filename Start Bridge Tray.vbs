' Prop Trader Edge Bridge - background launcher
' Double-click: starts the bridge with NO console window, just a green
' dot in the system tray (right-click it for menu / exit).
Set sh = CreateObject("WScript.Shell")
dir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.CurrentDirectory = dir
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "bridge-tray.ps1""", 0, False
