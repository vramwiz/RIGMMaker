param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath (Join-Path $output 'run\result.json')){throw 'Use a fresh validation output directory.'}
$bin=Join-Path $output 'bin'; $dcu=Join-Path $output 'dcu'; $runRoot=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$runRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ScriptResearchCheck.dpr') -Destination (Join-Path $output 'ScriptResearchCheck.dpr')
Copy-Item -LiteralPath (Join-Path $repo 'RIGMMaker.res') -Destination (Join-Path $output 'ScriptResearchCheck.res')
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable); $ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$search=$project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')}
$paths=@($search | ForEach-Object {Join-Path $repo $_})+@($PSScriptRoot)
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-DDEBUG','-$O-','-$R+','-$Q+','-$C+')
Push-Location $output
try{
  & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags (Join-Path $output 'ScriptResearchCheck.dpr') *> (Join-Path $output 'build.log')
  if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 12; throw 'Probe build failed'}
}finally{Pop-Location}
$owned=Start-Process -FilePath (Join-Path $bin 'ScriptResearchCheck.exe') -ArgumentList ('"'+$runRoot+'" --data-root "'+(Join-Path $runRoot 'OwnedData')+'" --settings-dir "'+(Join-Path $runRoot 'Settings')+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runRoot 'stdout.txt') -RedirectStandardError (Join-Path $runRoot 'stderr.txt')
$ready=Join-Path $runRoot 'ready-for-pipe.json'; $deadline=[DateTime]::UtcNow.AddSeconds(50)
while(-not(Test-Path -LiteralPath $ready)){
  if($owned.HasExited -or [DateTime]::UtcNow -gt $deadline){Get-Content -LiteralPath (Join-Path $runRoot 'stdout.txt') -Tail 15; throw 'Owned probe failed before pipe tests'}
  Start-Sleep -Milliseconds 100
}
$info=Get-Content -LiteralPath $ready -Raw -Encoding UTF8 | ConvertFrom-Json
$pipeChecks=[Collections.Generic.List[string]]::new()
function Call([string]$Command,[hashtable]$Arguments=@{},[bool]$Reject=$false){
  $client=[IO.Pipes.NamedPipeClientStream]::new('.',$info.commandPipe,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
  try{
    $client.Connect(3000); $client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message; $id=[guid]::NewGuid().ToString()
    $bytes=[Text.Encoding]::UTF8.GetBytes((@{schemaVersion=1;requestId=$id;command=$Command;args=$Arguments}|ConvertTo-Json -Depth 25 -Compress))
    $client.Write($bytes,0,$bytes.Length); $buffer=[byte[]]::new(65536); $read=$client.ReadAsync($buffer,0,$buffer.Length)
    if(-not $read.Wait(5000)){throw ('Pipe timeout: '+$Command)}
    $reply=[Text.Encoding]::UTF8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
    if($reply.requestId -ne $id -or $reply.ok -eq $Reject){throw ('Unexpected '+$Command+': '+($reply|ConvertTo-Json -Depth 8 -Compress))}
    $pipeChecks.Add($Command+$(if($Reject){' rejected as expected'}else{' succeeded'}))
    if($Reject){return $reply.error}; return $reply.data
  }finally{$client.Dispose()}
}
function Args([hashtable]$Extra=@{}){
  $status=Call 'app-script-status'; $payload=@{projectId=$status.projectId;revision=$status.revision}
  $state=Call 'app-script-research' @{projectId=$status.projectId;revision=$status.revision;section='summary'}
  $payload.researchId=$state.researchId
  foreach($key in $Extra.Keys){$payload[$key]=$Extra[$key]}; return $payload
}
$focusStatus=Call 'app-script-status'
if($focusStatus.textEditing){throw 'Focused work title must not acquire an input lock'}
$state=Call 'app-script-research' (Args @{section='elements';limit=3})
if($state.phase -ne 'deepen' -or -not $state.humanConfirmed -or $state.rows.Count -ne 3 -or -not $state.hasMore){throw 'Research phase or pagination mismatch'}
[void](Call 'app-script-research-confirm-work' (Args @{confirmed=$true}) $true)
$stale=Args @{id='one';workId='work-a';state='checking'}; $stale.revision--
[void](Call 'app-script-research-element' $stale $true)
[void](Call 'app-script-research-element' (Args @{id='one';workId='other-work';state='checking'}) $true)
[void](Call 'app-script-research-element' (Args @{id='one';workId='work-a';name='パイプで取得した検証用名称';summary='パイプ経由の概要';details='実在作品の事実ではない検証データ。';state='checking'}))
$current=Call 'app-script-research' (Args @{section='element';id='one'})
if($current.expandedElementId -ne 'one' -or $current.item.state -ne 'checking' -or $current.canAdvance){throw 'Pipe update did not affect UI and progress state'}
[void](Call 'app-script-research-element' (Args @{id='one';workId='work-a';state='confirmed-info'}))
$integration=Call 'app-script-research' (Args @{section='integration'})
if($integration.rows.Count -ne 1 -or $integration.rows[0].id -ne 'one'){throw 'Integration must exclude no-information elements'}
[void](Call 'app-script-research-candidates' (Args @{candidates=@(@{id='work-a';name='確認用作品A';overview='再検索した検証用概要。実在作品ではありません。'})}))
$after=Call 'app-script-research' (Args @{section='summary'})
if($after.humanConfirmed -or $after.phase -ne 'identify' -or $after.canAdvance){throw 'Re-search did not release human approval'}
$pipeChecks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'pipe-done.json') -Encoding UTF8
if(-not $owned.WaitForExit(60000)){throw 'Owned probe failed to finish'}
Get-Content -LiteralPath (Join-Path $runRoot 'stdout.txt') -Tail 8
$report=Get-Content -LiteralPath (Join-Path $runRoot 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Output ('GUI/model checks='+$report.checks.Count+'; Named Pipe checks='+$pipeChecks.Count+'; exit='+$owned.ExitCode)
if($owned.ExitCode -ne 0 -or $report.error){throw $report.error}
