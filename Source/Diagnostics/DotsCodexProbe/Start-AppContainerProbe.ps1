param([string]$Exe, [string]$StateDirectory)
$ErrorActionPreference = 'Stop'
if (-not $Exe) {
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    $Exe = Join-Path $repoRoot 'Win64\DotsCodexProbe\AppContainerFix\Release\DotsCodexProbe.exe'
}
$Exe = [IO.Path]::GetFullPath($Exe)
if (-not (Test-Path -LiteralPath $Exe)) { throw ('EXE not found: '+$Exe) }
$arguments = '--allow-appcontainer'
if ($StateDirectory) {
    $StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
    if ($StateDirectory.Contains('"')) { throw 'Invalid state directory.' }
    $arguments += ' --state-dir "'+$StateDirectory+'"'
}
# This launches the interactive one-form test app for the user.
$started = Start-Process -FilePath $Exe -ArgumentList $arguments -PassThru -WindowStyle Normal
[pscustomobject]@{processId=$started.Id;executable=$Exe;accessMode='appcontainer-test'}
