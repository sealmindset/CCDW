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
    ' Docker not running -- try to auto-start Rancher Desktop
    Dim rdExe, localApp, progFiles
    rdExe = ""
    localApp = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
    progFiles = WshShell.ExpandEnvironmentStrings("%ProgramFiles%")

    If fso.FileExists(localApp & "\Programs\Rancher Desktop\Rancher Desktop.exe") Then
        rdExe = localApp & "\Programs\Rancher Desktop\Rancher Desktop.exe"
    ElseIf fso.FileExists(progFiles & "\Rancher Desktop\Rancher Desktop.exe") Then
        rdExe = progFiles & "\Rancher Desktop\Rancher Desktop.exe"
    End If

    If rdExe = "" Then
        ' Check other user profiles as last resort
        Dim usersFolder, subFolder
        Set usersFolder = fso.GetFolder("C:\Users")
        For Each subFolder In usersFolder.SubFolders
            Dim tryPath
            tryPath = subFolder.Path & "\AppData\Local\Programs\Rancher Desktop\Rancher Desktop.exe"
            If fso.FileExists(tryPath) Then
                rdExe = tryPath
                Exit For
            End If
        Next
    End If

    If rdExe = "" Then
        MsgBox "Could not find Rancher Desktop on this computer." & vbCrLf & vbCrLf & _
               "Double-click install.bat to set everything up.", _
               vbExclamation, "Claude Code Docker"
        WScript.Quit 1
    End If

    ' Start Rancher Desktop
    WshShell.Run """" & rdExe & """", 1, False

    ' Brief notification so user knows something is happening
    WshShell.Popup "Starting Docker..." & vbCrLf & vbCrLf & _
                   "This takes about a minute. Claude Code will open" & vbCrLf & _
                   "in your browser automatically when ready." & vbCrLf & vbCrLf & _
                   "Click OK or just wait.", _
                   8, "Claude Code Docker", vbInformation

    ' Wait for Docker engine (up to 2 minutes, checking every 5 seconds)
    Dim waitCount
    waitCount = 0
    Do While waitCount < 24
        ret = WshShell.Run("cmd /c docker info >nul 2>nul", 0, True)
        If ret = 0 Then Exit Do
        WScript.Sleep 5000
        waitCount = waitCount + 1
    Loop

    ' Final check
    ret = WshShell.Run("cmd /c docker info >nul 2>nul", 0, True)
    If ret <> 0 Then
        MsgBox "Docker is still starting up." & vbCrLf & vbCrLf & _
               "Wait for the Rancher Desktop icon in your system tray" & vbCrLf & _
               "(bottom-right, near the clock) to stop spinning," & vbCrLf & _
               "then double-click the Claude shortcut again.", _
               vbExclamation, "Claude Code Docker"
        WScript.Quit 1
    End If
End If

' Check if container already running
ret = WshShell.Run("cmd /c docker inspect -f ""{{.State.Running}}"" claude-code 2>nul | findstr true >nul", 0, True)
If ret = 0 Then
    ' Already running, just open browser
    WshShell.Run "http://localhost:3000", 1, False
    WScript.Quit 0
End If

' Check if image exists locally
ret = WshShell.Run("cmd /c docker image inspect ghcr.io/sealmindset/claude-code-docker:latest >nul 2>nul", 0, True)
If ret <> 0 Then
    ' First time -- run install.bat which handles build + setup with progress
    Dim installBat
    installBat = fso.BuildPath(projectDir, "install.bat")
    If fso.FileExists(installBat) Then
        WshShell.Run """" & installBat & """", 1, False
    Else
        MsgBox "First-time setup needed but install.bat was not found." & vbCrLf & vbCrLf & _
               "Re-download the project and run install.bat.", _
               vbExclamation, "Claude Code Docker"
    End If
    WScript.Quit 0
End If

' Image exists -- start the container (no build needed)
errFile = fso.BuildPath(fso.GetSpecialFolder(2), "claude-launch-err.txt")
ret = WshShell.Run("cmd /c docker compose up -d --no-build > """ & errFile & """ 2>&1", 0, True)
If ret <> 0 Then
    errText = ""
    If fso.FileExists(errFile) Then
        Dim f
        Set f = fso.OpenTextFile(errFile, 1)
        If Not f.AtEndOfStream Then errText = f.ReadAll
        f.Close
    End If
    If Len(errText) > 500 Then errText = Left(errText, 500) & "..."

    MsgBox "Could not start Claude Code Docker." & vbCrLf & vbCrLf & _
           errText & vbCrLf & vbCrLf & _
           "Run install.bat to check for problems.", _
           vbExclamation, "Claude Code Docker"
    WScript.Quit 1
End If

' Clean up temp file
If fso.FileExists(errFile) Then fso.DeleteFile errFile

' Give services a moment to initialize
WScript.Sleep 4000

' Open Welcome page in default browser
WshShell.Run "http://localhost:3000", 1, False
