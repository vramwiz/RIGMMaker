param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $output){throw 'Fresh output required'}
$bin=Join-Path $output 'bin';$dcu=Join-Path $output 'dcu';$run=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$run -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BundledMp4Check.dpr') -Destination (Join-Path $output 'BundledMp4Check.dpr')
Copy-Item -LiteralPath (Join-Path $repo 'RIGMMaker.res') -Destination (Join-Path $output 'BundledMp4Check.res')
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable);$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')} | ForEach-Object {Join-Path $repo $_})
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-DDEBUG','-$O-','-$R+','-$Q+','-$C+')
Push-Location $output
try {
    & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags (Join-Path $output 'BundledMp4Check.dpr') *> (Join-Path $output 'build.log')
    if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 12;throw 'Probe build failed'}
} finally { Pop-Location }
Copy-Item -LiteralPath (Join-Path $repo 'Runtime') -Destination (Join-Path $bin 'Runtime') -Recurse
$probe=Start-Process -FilePath (Join-Path $bin 'BundledMp4Check.exe') -ArgumentList ('"'+$run+'" --data-root "'+(Join-Path $run 'OwnedData')+'" --settings-dir "'+(Join-Path $run 'Settings')+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $run 'stdout.txt') -RedirectStandardError (Join-Path $run 'stderr.txt')
$deadline=[DateTime]::UtcNow.AddSeconds(120)
while(-not $probe.WaitForExit(250)) {
    if([DateTime]::UtcNow -gt $deadline){throw ('Owned probe timed out; PID='+$probe.Id+'; output='+$output)}
}
Get-Content -LiteralPath (Join-Path $run 'stdout.txt') -Tail 8
$report=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Output ('Checks='+$report.checks.Count+'; exit='+$probe.ExitCode)
if($probe.ExitCode -ne 0 -or $report.error){throw $report.error}
$missing=Join-Path $output 'MissingRuntime'
New-Item -ItemType Directory -Path $missing -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $bin 'BundledMp4Check.exe') -Destination $missing
$probe=Start-Process -FilePath (Join-Path $missing 'BundledMp4Check.exe') -ArgumentList ('"'+$missing+'" --missing-runtime --data-root "'+(Join-Path $missing 'OwnedData')+'" --settings-dir "'+(Join-Path $missing 'Settings')+'"') -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $missing 'stdout.txt') -RedirectStandardError (Join-Path $missing 'stderr.txt')
if(-not $probe.WaitForExit(30000)){throw ('Missing-runtime probe timed out; PID='+$probe.Id)}
$missingReport=Get-Content -LiteralPath (Join-Path $missing 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Output ('Missing runtime checks='+$missingReport.checks.Count+'; exit='+$probe.ExitCode)
if($probe.ExitCode -ne 0 -or $missingReport.error){throw $missingReport.error}
