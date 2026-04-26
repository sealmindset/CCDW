' Claude Code Docker Launcher
' Double-click the desktop shortcut to start Claude Code
' and open it in your browser -- no terminal needed.

Option Explicit

Dim WshShell, fso, projectDir, ret

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Project lives wherever this script lives
projectDir = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = projectDir

' Check Docker engine is reachable
ret = WshShell.Run("cmd /c docker info >nul 2>nul", 0, True)
If ret <> 0 Then
    MsgBox "Rancher Desktop does not appear to be running." & vbCrLf & vbCrLf & _
           "Open Rancher Desktop from the Start menu and wait for " & _
           "it to finish loading, then try again.", _
           vbExclamation, "Claude Code Docker"
    WScript.Quit 1
End If

' Start the container (silently)
ret = WshShell.Run("cmd /c docker compose up -d 2>nul", 0, True)
If ret <> 0 Then
    MsgBox "Could not start Claude Code Docker." & vbCrLf & vbCrLf & _
           "Run install.bat to check for problems.", _
           vbExclamation, "Claude Code Docker"
    WScript.Quit 1
End If

' Give services a moment to initialize
WScript.Sleep 4000

' Open Welcome page in default browser
WshShell.Run "http://localhost:3000", 1, False
