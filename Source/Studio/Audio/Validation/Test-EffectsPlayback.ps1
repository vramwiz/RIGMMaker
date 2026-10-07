param(
    [string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('rigm-effects-playback-' + [guid]::NewGuid().ToString('N'))),
    [string]$Python = (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
)
$ErrorActionPreference = 'Stop'
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$fixtureScript = Join-Path $PSScriptRoot 'prepare-effects-playback-fixtures.py'
if (-not (Test-Path -LiteralPath $Python)) { throw 'Pass -Python with a working Python 3 executable.' }
& $Python $fixtureScript $OutDir
if ($LASTEXITCODE -ne 0) { throw 'Isolated fixture creation failed.' }
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project = Join-Path $PSScriptRoot 'EffectsPlaybackProbe.dpr'
foreach ($target in @('32','64')) {
    $compiler = (Get-Command ('dcc' + $target + '.exe') -ErrorAction Stop).Source
    $bin = Join-Path $OutDir ('bin' + $target)
    $dcu = Join-Path $OutDir ('dcu' + $target)
    New-Item -ItemType Directory -Path $bin,$dcu -Force | Out-Null
    $flags = @('-B','-Q',('-E' + $bin),('-N0' + $dcu),('-U' + $source),'-NSSystem;Winapi','-$R+','-$Q+','-$C+')
    & $compiler @flags $project
    if ($LASTEXITCODE -ne 0) { throw ('Playback probe compilation failed for Win' + $target) }
    $reportPath = Join-Path $OutDir ('result' + $target + '.json')
    & (Join-Path $bin 'EffectsPlaybackProbe.exe') (Join-Path $OutDir 'manifest.json') $reportPath
    if ($LASTEXITCODE -ne 0) { throw ('Playback probe failed for Win' + $target + ': ' + $reportPath) }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($report.failures -ne 0) { throw ('Playback failures reported: ' + $reportPath) }
    Write-Output ('Win' + $target + ': ' + $report.checks.Count + ' checks passed. MCI baseline retained in ' + $reportPath)
}
& $Python $fixtureScript $OutDir --verify
if ($LASTEXITCODE -ne 0) { throw 'Fixture hashes changed during playback.' }
Write-Output ('All reports/fixtures are isolated in ' + $OutDir)
