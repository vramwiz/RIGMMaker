param(
  [string]$OutDir=(Join-Path $env:TEMP ('rigm-scenes-probe-'+[guid]::NewGuid().ToString('N').Substring(0,8))),
  [ValidateSet('Debug','Release')][string]$Configuration='Release',
  [switch]$Run,
  [switch]$DialogueOnly,
  [string]$GeneratedImage
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if($output.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)){
  throw 'Use an isolated output directory outside the repository.'
}
if($output.Length -gt 100){throw 'Use a shorter output directory.'}
$bin=Join-Path $output 'bin'; $dcu=Join-Path $output 'dcu'; $runRoot=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$runRoot -Force | Out-Null
$probe=Join-Path $output 'ScenesGuiProbe.dpr'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ScenesGuiProbe.dpr') -Destination $probe
Copy-Item -LiteralPath (Join-Path $repo 'RIGMMaker.res') -Destination (Join-Path $output 'ScenesGuiProbe.res')
$source=Join-Path $repo 'Source'
$paths=@($source)+@(Get-ChildItem -LiteralPath $source -Directory -Recurse | ForEach-Object {$_.FullName})
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data')
if($Configuration -eq 'Debug'){$flags+=@('-DDEBUG','-$O-','-$R+','-$Q+','-$C+')}else{$flags+=@('-DRELEASE','-$O+','-$R-','-$Q-')}
Push-Location $output
try{& (Get-Command dcc64.exe).Source @flags $probe *> (Join-Path $output 'build.log'); if($LASTEXITCODE -ne 0){throw 'See isolated build.log'}}finally{Pop-Location}
Write-Output ('Probe built: '+(Join-Path $bin 'ScenesGuiProbe.exe'))
if(-not $Run){return}
$probeArguments='"'+$runRoot+'"'; if($DialogueOnly){$probeArguments+=' /dialogue-only'}
$owned=Start-Process -FilePath (Join-Path $bin 'ScenesGuiProbe.exe') -ArgumentList $probeArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runRoot 'stdout.txt') -RedirectStandardError (Join-Path $runRoot 'stderr.txt')
if($DialogueOnly){
  $owned.WaitForExit()
  Get-Content -LiteralPath (Join-Path $runRoot 'stdout.txt') -Tail 5 -Encoding UTF8
  if($owned.ExitCode -ne 0){throw 'Dialogue reference validation failed'}
  return
}
$readyFile=Join-Path $runRoot 'ready-for-pipe.json'
$deadline=[DateTime]::UtcNow.AddSeconds(50)
while(-not(Test-Path -LiteralPath $readyFile)){
  if($owned.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Owned GUI probe failed before pipe tests; see run/stdout.txt'}
  Start-Sleep -Milliseconds 100
}
$info=Get-Content -LiteralPath $readyFile -Raw -Encoding UTF8 | ConvertFrom-Json
if($GeneratedImage){
  $deliveredImage=Join-Path $info.dataRoot 'Exchange\generated-image.png'
  Copy-Item -LiteralPath $GeneratedImage -Destination $deliveredImage
  $info.imageHash=(Get-FileHash -LiteralPath $deliveredImage).Hash.ToLowerInvariant()
}
$pipeChecks=[Collections.Generic.List[string]]::new()
function Call([string]$Command,[hashtable]$Arguments=@{},[bool]$Reject=$false){
  $client=[IO.Pipes.NamedPipeClientStream]::new('.',$info.commandPipe,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
  try{
    $client.Connect(3000); $client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
    $id=[guid]::NewGuid().ToString()
    $bytes=[Text.Encoding]::UTF8.GetBytes((@{schemaVersion=1;requestId=$id;command=$Command;args=$Arguments}|ConvertTo-Json -Depth 20 -Compress))
    $client.Write($bytes,0,$bytes.Length); $buffer=[byte[]]::new(65536); $read=$client.ReadAsync($buffer,0,$buffer.Length)
    if(-not $read.Wait(5000)){throw ('Pipe timeout: '+$Command)}
    $reply=[Text.Encoding]::UTF8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
    if($reply.requestId -ne $id -or $reply.ok -eq $Reject){throw ('Unexpected '+$Command+': '+($reply|ConvertTo-Json -Depth 8 -Compress))}
    $pipeChecks.Add($Command+$(if($Reject){' rejected as expected'}else{' succeeded'}))
    if($Reject){return $reply.error}; return $reply.data
  }finally{$client.Dispose()}
}
function Args([hashtable]$Extra=@{}){
  $s=Call 'app-script-status'; $payload=@{projectId=$s.projectId;revision=$s.revision}
  foreach($key in $Extra.Keys){$payload[$key]=$Extra[$key]}; return $payload
}
$first=Call 'app-script-scenes' (Args @{offset=0})
$sceneId=$first.rows[0].id
[void](Call 'app-script-request-scene-image' (Args @{sceneId=$sceneId}))
$requested=Call 'app-script-scenes' (Args @{offset=0})
$request=$requested.rows[0].imageRequest
if($request.state -ne 'pending' -or -not $request.current -or $request.prompt -ne '雪山の景色'){throw 'Request payload/current flag mismatch'}
$deliveryPath=if($GeneratedImage){'Exchange\generated-image.png'}else{'Exchange\fixture.png'}
$adopt=Args @{sceneId=$sceneId;requestId=$request.requestId;path=$deliveryPath;sha256=$info.imageHash;provenance='test-fixture'}
$stale=$adopt.Clone(); $stale.revision--
[void](Call 'app-script-adopt-scene-image' $stale $true)
$wrongId=$adopt.Clone(); $wrongId.requestId=[guid]::NewGuid().ToString()
[void](Call 'app-script-adopt-scene-image' $wrongId $true)
[void](Call 'app-script-adopt-scene-image' $adopt)
$received=Call 'app-script-scenes' (Args @{offset=0})
if($received.rows[0].imageRequest.state -ne 'adopted' -or $received.rows[0].imageApproved -or -not $received.rows[0].image){throw 'Adoption must retain human confirmation'}
$replay=Args @{sceneId=$sceneId;requestId=$request.requestId;path=$deliveryPath;sha256=$info.imageHash;provenance='test-fixture'}
[void](Call 'app-script-adopt-scene-image' $replay $true)
[void](Call 'app-script-request-unapproved-images' (Args))
$combined=Call 'app-script-scenes' (Args @{offset=1})
if(-not $combined.rows[0].imageRequest.prompt.Contains('背景を明るく') -or -not $combined.rows[0].imageRequest.prompt.Contains('山頂を追加')){throw 'Unified corrections absent from request'}
$pipeChecks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'pipe-done.json') -Encoding UTF8
$owned.WaitForExit()
Get-Content -LiteralPath (Join-Path $runRoot 'stdout.txt') -Tail 5 -Encoding UTF8
Write-Output ('Owned probe exit='+$owned.ExitCode+'; pipe checks='+$pipeChecks.Count)
if($owned.ExitCode -ne 0){throw 'GUI validation failed'}
