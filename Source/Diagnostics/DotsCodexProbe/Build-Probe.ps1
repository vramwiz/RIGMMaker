param(
    [string]$StudioRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$rsvars = Join-Path $StudioRoot 'bin\rsvars.bat'
$msbuild = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe'
if (-not (Test-Path -LiteralPath $rsvars)) { throw 'RAD Studio rsvars.bat not found.' }
if (-not (Test-Path -LiteralPath $msbuild)) { throw 'MSBuild not found.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'Win64\DotsCodexProbe' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$previousEnvironment = @{}
try {
    # RAD Studioの既存rsvarsのSET行を、このPowerShellプロセス内だけへ適用する。
    foreach ($line in Get-Content -LiteralPath $rsvars) {
        if ($line -match '^@SET ([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $variableName = $Matches[1]
            $variableValue = [Environment]::ExpandEnvironmentVariables($Matches[2])
            $previousEnvironment[$variableName] = [Environment]::GetEnvironmentVariable($variableName, 'Process')
            [Environment]::SetEnvironmentVariable($variableName, $variableValue, 'Process')
        }
    }
    foreach ($configuration in @('Debug', 'Release')) {
        $binDir = Join-Path $OutputRoot $configuration
        New-Item -ItemType Directory -Path $binDir, (Join-Path $binDir 'dcu') -Force | Out-Null
        $logPath = Join-Path $binDir 'build.log'
        & $msbuild (Join-Path $PSScriptRoot 'DotsCodexProbe.dproj') /t:Build "/p:Config=$configuration" /p:Platform=Win64 "/p:DCC_ExeOutput=$binDir" "/p:DCC_DcuOutput=$(Join-Path $binDir 'dcu')" /v:minimal /nologo "/flp:LogFile=$logPath;Encoding=UTF-8;Verbosity=normal"
        if ($LASTEXITCODE -ne 0) { throw "$configuration build failed." }
    }
} finally {
    foreach ($variableName in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($variableName, $previousEnvironment[$variableName], 'Process')
    }
}
