param([string]$OutDir=(Join-Path ([IO.Path]::GetTempPath()) ('rigm-effects-analysis-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$OutDir=[IO.Path]::GetFullPath($OutDir)
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$sourcePaths=@($sourceRoot)+@(Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse | Select-Object -ExpandProperty FullName)
$dcuRoot=Join-Path $OutDir 'dcu'
New-Item -ItemType Directory -Path $OutDir,$dcuRoot -Force | Out-Null
$compiler=(Get-Command 'dcc64.exe' -ErrorAction Stop).Source
$flags=@('-B','-Q',('-E'+$OutDir),('-N0'+$dcuRoot),('-U'+($sourcePaths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-$R+','-$Q+','-$C+')
& $compiler @flags (Join-Path $PSScriptRoot 'NativeEffectsAnalysisProbe.dpr')
if($LASTEXITCODE -ne 0){throw 'Native effects analysis compilation failed'}
& (Join-Path $OutDir 'NativeEffectsAnalysisProbe.exe')
if($LASTEXITCODE -ne 0){throw 'Native effects analysis probe failed'}
Write-Output ('Analysis probe passed; isolated executable/DCUs: '+$OutDir)
