param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$HtmlDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $output){throw 'Use a fresh validation output directory'}
$bin=Join-Path $output 'bin'; $dcu=Join-Path $output 'dcu'; $run=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$run -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PostingCheck.dpr') -Destination (Join-Path $output 'PostingCheck.dpr')
Copy-Item -LiteralPath (Join-Path $repo 'RIGMMaker.res') -Destination (Join-Path $output 'PostingCheck.res')
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable); $ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')} | ForEach-Object {Join-Path $repo $_})
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-DDEBUG','-$O-','-$R+','-$Q+','-$C+')
Push-Location $output
try {
  & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags (Join-Path $output 'PostingCheck.dpr') *> (Join-Path $output 'build.log')
  if($LASTEXITCODE -ne 0){Get-Content (Join-Path $output 'build.log') -Tail 12; throw 'Posting probe build failed'}
} finally {Pop-Location}
$arguments='"'+$run+'" "'+[IO.Path]::GetFullPath($HtmlDir)+'" --data-root "'+(Join-Path $run 'OwnedData')+'" --settings-dir "'+(Join-Path $run 'Settings')+'"'
$probe=Start-Process -FilePath (Join-Path $bin 'PostingCheck.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $run 'stdout.txt') -RedirectStandardError (Join-Path $run 'stderr.txt')
try {
  $deadline=[DateTime]::UtcNow.AddSeconds(90)
  while(-not $probe.WaitForExit(250)){if([DateTime]::UtcNow -gt $deadline){throw 'Owned posting probe timed out'}}
  Get-Content (Join-Path $run 'stdout.txt') -Tail 12
  $report=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
  Write-Output ('Posting checks='+$report.checks.Count+'; exit='+$probe.ExitCode)
  if($probe.ExitCode -ne 0 -or $report.error){throw $report.error}
} finally {if(-not $probe.HasExited){Stop-Process -Id $probe.Id}}
