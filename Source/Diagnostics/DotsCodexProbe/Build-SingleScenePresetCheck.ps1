param([Parameter(Mandatory=$true)][string]$OutputRoot,
  [string]$StudioRoot='C:\Program Files (x86)\Embarcadero\Studio\37.0')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable)
$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' |
  Where-Object {$_ -and -not $_.StartsWith('$(')} | ForEach-Object {Join-Path $repo $_})
$bin=[IO.Path]::GetFullPath($OutputRoot); $dcu=Join-Path $bin 'dcu'
New-Item -ItemType Directory -Path $bin,$dcu -Force | Out-Null
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),
  '-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-$R+','-$Q+')
$lines=@(& (Join-Path $StudioRoot 'bin\dcc64.exe') @flags (Join-Path $PSScriptRoot 'SingleScenePresetCheck.dpr') 2>&1)
$code=$LASTEXITCODE
$lines | Set-Content -LiteralPath (Join-Path $bin 'build.log') -Encoding UTF8
if($code -ne 0){$lines | Select-Object -Last 12; throw 'SingleScenePresetCheck compilation failed'}
Write-Output ('Compiled: '+(Join-Path $bin 'SingleScenePresetCheck.exe'))
Write-Output 'Run the check with a new, nonexistent owned output directory as its first argument.'
