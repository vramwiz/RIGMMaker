param([ValidateSet('Debug','Release')][string]$Configuration = 'Debug', [string]$Project = 'PsdStudio.dpr')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$projectPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Project))
if (-not $projectPath.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Project must be in this workspace' }
$compiler = (Get-Command dcc64.exe -ErrorAction Stop).Source
$out = Join-Path $repoRoot "Win64\Validation\PsdStudio\$Configuration"
$dcu = Join-Path $out 'Dcu'
New-Item -ItemType Directory -Path $dcu -Force | Out-Null
$paths = @('Source\Psd\Core','Source\Psd\Persistence','Source\Psd\Editor','Source\Psd\Rendering','Source\Psd\Integrations','Source\Psd\Shell','Source\Psd\Reference','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Integrations\Pipe') | ForEach-Object { Join-Path $repoRoot $_ }
$flags = @('-B', '-Q', "-E$out", "-N0$dcu", ('-U' + ($paths -join ';')), '-NSSystem;Winapi;Vcl;System.Win')
if ($Configuration -eq 'Debug') { $flags += @('-DDEBUG', '-$O-', '-$R+', '-$Q+', '-$C+') } else { $flags += @('-DRELEASE', '-$O+', '-$R-', '-$Q-') }
Push-Location $repoRoot
try {
  & $compiler @flags $projectPath
  if ($LASTEXITCODE -ne 0) { throw "Delphi build failed: $LASTEXITCODE" }
} finally { Pop-Location }
