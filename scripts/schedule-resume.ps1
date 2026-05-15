param($ScriptPath)
try {
    $val = 'cmd.exe /c "' + $ScriptPath + '"'
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' `
        -Name 'ClaudeCodeSetup' -Value $val -PropertyType String -Force | Out-Null
    exit 0
} catch {
    exit 1
}
