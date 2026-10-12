param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $output){throw 'Fresh output required'}
$bin=Join-Path $output 'bin'; $dcu=Join-Path $output 'dcu'; $run=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$run | Out-Null
$source=Join-Path $output 'ScriptCopyCheck.dpr'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ScriptCopyCheck.dpr') -Destination $source
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable); $ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')} | ForEach-Object {Join-Path $repo $_})
$flags=@('-B','-Q','-GD',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-$O+','-$R+','-$Q+')
Push-Location $output
try {
  & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags $source *> (Join-Path $output 'build.log')
  if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 12; throw 'Script-copy check build failed'}
  $inertEngine=Join-Path $bin 'run.exe'; [IO.File]::WriteAllBytes($inertEngine,[byte[]]@(0))
  [IO.File]::WriteAllText((Join-Path $bin 'VoicevoxEngine.ini'),("[VOICEVOX]`r`nEngineExe="+$inertEngine+"`r`n"),[Text.UTF8Encoding]::new($true))
  $arguments='"'+$run+'" --data-root "'+(Join-Path $run 'OwnedData')+'" --settings-dir "'+(Join-Path $run 'Settings')+'"'
  $p=Start-Process -FilePath (Join-Path $bin 'ScriptCopyCheck.exe') -ArgumentList $arguments -WorkingDirectory $output -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $run 'stdout.txt') -RedirectStandardError (Join-Path $run 'stderr.txt')
  $deadline=[DateTime]::UtcNow.AddSeconds(180)
  while(-not $p.WaitForExit(1000)){if([DateTime]::UtcNow -gt $deadline){throw ('Owned copy probe timed out; PID='+$p.Id)}}
  Get-Content -LiteralPath (Join-Path $run 'stdout.txt') -Tail 14
  $report=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
  Write-Output ('Copy checks='+$report.checks.Count+'; exit='+$p.ExitCode)
  if($p.ExitCode -ne 0 -or $report.error){throw $report.error}
} finally {Pop-Location}
