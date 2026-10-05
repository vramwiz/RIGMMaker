param([ValidateSet('Debug','Release')][string]$Configuration='Debug',[string]$Project='RIGMMaker.dpr')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$projectPath=[IO.Path]::GetFullPath((Join-Path $repo $Project))
if(-not $projectPath.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Project outside workspace'}
$output=Join-Path $repo ('Win64\Validation\IntegratedPsd\'+$Configuration)
$dcu=Join-Path $output 'Dcu'; New-Item -ItemType Directory -Path $dcu -Force | Out-Null
$paths=@((Join-Path $repo 'Source'))+@(Get-ChildItem -LiteralPath (Join-Path $repo 'Source') -Directory -Recurse | ForEach-Object {$_.FullName})
$flags=@('-B','-Q',('-E'+$output),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data')
if($Configuration -eq 'Debug'){$flags+=@('-DDEBUG','-$O-','-$R+','-$Q+','-$C+')}else{$flags+=@('-DRELEASE','-$O+','-$R-','-$Q-')}
Push-Location $repo
try{& (Get-Command dcc64.exe).Source @flags $projectPath; if($LASTEXITCODE -ne 0){throw 'Integrated Delphi build failed'}}finally{Pop-Location}
