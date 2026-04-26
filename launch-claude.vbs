' Claude Code Docker Launcher
' Double-click the desktop shortcut to start Claude Code
' and open it in your browser -- no terminal needed.

Option Explicit

Dim WshShell, fso, projectDir, ret, errFile, errText

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

' Check if container already running
ret = WshShell.Run("cmd /c docker inspect -f ""{{.State.Running}}"" claude-code 2>nul | findstr true >nul", 0, True)
If ret = 0 Then
    ' Already running, just open browser
    WshShell.Run "http://localhost:3000", 1, False
    WScript.Quit 0
End If

' Start the container (capture errors for diagnostics)
errFile = fso.BuildPath(fso.GetSpecialFolder(2), "claude-launch-err.txt")
ret = WshShell.Run("cmd /c docker compose up -d --no-build > """ & errFile & """ 2>&1", 0, True)
If ret <> 0 Then
    ' Read error output for the dialog
    errText = ""
    If fso.FileExists(errFile) Then
        Dim f
        Set f = fso.OpenTextFile(errFile, 1)
        If Not f.AtEndOfStream Then errText = f.ReadAll
        f.Close
    End If
    If Len(errText) > 500 Then errText = Left(errText, 500) & "..."

    MsgBox "Could not start Claude Code Docker." & vbCrLf & vbCrLf & _
           "Run install.bat first to set up the application.", _
           vbExclamation, "Claude Code Docker"
    WScript.Quit 1
End If

' Clean up temp file
If fso.FileExists(errFile) Then fso.DeleteFile errFile

' Give services a moment to initialize
WScript.Sleep 4000

' Open Welcome page in default browser
WshShell.Run "http://localhost:3000", 1, False
