param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[Parameter(Mandatory=$true)][string]$FixtureProject,[Parameter(Mandatory=$true)][string]$FixtureDataRoot)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptSubtitles-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptSubtitles.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
$fixture=Get-Content -LiteralPath $FixtureProject -Raw -Encoding utf8 | ConvertFrom-Json
if($fixture.scriptWizard.stage -ne 'casting' -or $fixture.title -ne '配役工程の分離した確認作品'){throw 'Explicit prior owned casting fixture required'}
$sourceHash=(Get-FileHash $FixtureProject).Hash;$hashes=@{}
foreach($selected in $fixture.scriptWizard.selectedCharacters){
 if($selected.path -notin @('RIGM\casting-guide.rigm','RIGM\casting-question.rigm')){throw 'Owned fixture path mismatch'}
 $path=Join-Path $FixtureDataRoot $selected.path;$hashes[$path]=(Get-FileHash $path).Hash;Copy-Item -LiteralPath $path -Destination (Join-Path $root $selected.path)
}
$relative='Projects\'+$fixture.projectId+'\project.rigmovie';$target=Join-Path $root $relative;New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
Copy-Item -LiteralPath $FixtureProject -Destination $target;$relative | Set-Content (Join-Path $root 'fixture-project.txt') -Encoding utf8
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null
$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-subtitles.json';$utf8=[Text.UTF8Encoding]::new($false)
function Invoke-Pipe([string]$name,[string]$command,[hashtable]$arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{
  $client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
  $packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$command;args=$arguments} | ConvertTo-Json -Depth 12 -Compress
  $bytes=$utf8.GetBytes($packet);if($bytes.Length -gt 60000){throw 'Request exceeds existing pipe limit'}
  $client.Write($bytes,0,$bytes.Length);$client.Flush();$buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length)
  if(-not $read.Wait(6000)){throw 'Owned pipe timeout'};$utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
 }finally{$client.Dispose()}
}
function Read-SharedJson($path){
 $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try{$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true);try{$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}}finally{$stream.Dispose()}
}
function Read-Subtitles($pipe,$common){
 $all=@();$offset=0
 do{$part=Invoke-Pipe $pipe 'app-script-subtitles' ($common+@{offset=$offset});if(-not $part.ok){throw ('Subtitle read failed '+($part | ConvertTo-Json -Depth 8 -Compress))};$all+=@($part.data.rows);$offset=$part.data.nextOffset}while($part.data.hasMore)
 return ,$all
}
$checks=[Collections.Generic.List[string]]::new()
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-subtitles';if($phase -eq 1){$flag='--verify-script-subtitles-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$captured=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json';$request=$null
  if(Test-Path -LiteralPath $requestPath){try{$request=Read-SharedJson $requestPath}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json
   if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection identity mismatch'}
   $pipe=$connection.commandPipe;$status=Invoke-Pipe $pipe 'app-script-status' @{}
   if(-not $status.ok -or $status.data.wizard.stage -ne 'subtitles'){throw 'Subtitle stage invalid'}
   $expectedAdvance=($status.data.wizard.subtitlesStatus -eq 'complete' -and -not $status.data.textEditing)
   if($status.data.canAdvance -ne $expectedAdvance){throw 'Subtitle completion gate differs from voice Next'}
   $common=@{projectId=$status.data.projectId;revision=$status.data.revision};$rows=Read-Subtitles $pipe $common
   if($rows.Count -ne 4 -or $null -ne $status.data.wizard.subtitles.rows){throw 'Subtitle pagination or summary invalid'}
   $checks.Add('bounded subtitle reads show cast display voice and note separately')
   if($request.stage -eq '.editing'){
    if(-not $status.data.textEditing){throw 'Human subtitle edit lock missing'}
    foreach($command in @('app-script-edit-subtitle','app-script-set-subtitle-break','app-script-set-title','app-script-new')){
     if((Invoke-Pipe $pipe $command ($common+@{cueId=$rows[0].cueId;subtitle='上書き';offset=4;title='上書き'})).ok){throw ('Human lock accepted '+$command)}
     $checks.Add('human subtitle edit lock rejects '+$command)
    }
   }elseif($request.stage -eq '.pipe'){
    $before=$rows | ConvertTo-Json -Depth 8 -Compress
    foreach($change in @(@{revision=($common.revision-1)},@{projectId='wrong'},@{cueId='unknown'},@{subtitle=('あ'*3001)},@{note=('あ'*2049)})){
     $invalid=$common+@{cueId=$rows[1].cueId;subtitle='変更候補';note='メモ'};foreach($key in $change.Keys){$invalid[$key]=$change[$key]}
     if((Invoke-Pipe $pipe 'app-script-edit-subtitle' $invalid).ok){throw 'Invalid subtitle edit accepted'}
     if(((Read-Subtitles $pipe $common) | ConvertTo-Json -Depth 8 -Compress) -ne $before){throw 'Invalid subtitle edit partially mutated canonical data'}
     $checks.Add('invalid subtitle edit atomically rejected '+(@($change.Keys)[0]))
    }
    if((Invoke-Pipe $pipe 'app-script-set-subtitle-break' ($common+@{cueId=$rows[0].cueId;offset=3})).ok){throw 'Surrogate middle break accepted'}
    $checks.Add('pipe rejects surrogate middle break')
    $packet=$common+@{cueId=$rows[1].cueId;subtitle="pipe表示🙂`r`n2行目";note='パイプ確認メモ'}
    $accepted=Invoke-Pipe $pipe 'app-script-edit-subtitle' $packet
    if(-not $accepted.ok){throw ('Subtitle submission failed '+($accepted | ConvertTo-Json -Depth 8 -Compress))}
    $after=Read-Subtitles $pipe @{projectId=$accepted.data.projectId;revision=$accepted.data.revision}
    if($after[1].subtitle -ne $packet.subtitle -or $after[1].voiceText -ne $rows[1].voiceText -or $after[1].sceneId -ne $rows[1].sceneId -or $after[1].role -ne $rows[1].role){throw 'Display edit crossed voice scene or cast boundary'}
    if((Invoke-Pipe $pipe 'app-script-edit-subtitle' $packet).ok){throw 'Old subtitle revision accepted'}
    $checks.Add('actual subtitle pipe edit preserves voice scene and cast');$checks.Add('obsolete display revision rejected')
   }
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
   $request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding utf8;$captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned verification remains active, preserve PID/root '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit();if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Subtitle GUI verification failed'}
}
if((Get-FileHash $FixtureProject).Hash -ne $sourceHash){throw 'Original verification project changed'}
foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Original character copy changed'}}
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$second=Get-Content ($result+'.reopened.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;exe=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$checks;fixtureProject=$FixtureProject;fixtureHash=$sourceHash;originalHashes=$hashes} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
