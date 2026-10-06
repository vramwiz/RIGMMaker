param([Parameter(Mandatory)][string]$ExecutablePath,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$FixtureProject,[Parameter(Mandatory)][string]$FixtureDataRoot)
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8
$fixture=Get-Content -LiteralPath $FixtureProject -Raw -Encoding utf8 | ConvertFrom-Json
if($fixture.title -ne 'Codex実往復用：架空の星空観測所' -or $fixture.scriptWizard.stage -ne 'subtitles'){throw 'Owned semantic subtitle fixture required'}
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptVoice-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptVoice.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
$hashes=@{};$sourceHash=(Get-FileHash $FixtureProject).Hash
foreach($c in $fixture.scriptWizard.selectedCharacters){if($c.path -notin @('RIGM\casting-guide.rigm','RIGM\casting-question.rigm')){throw 'Owned character path required'};$source=Join-Path $FixtureDataRoot $c.path;$hashes[$source]=(Get-FileHash $source).Hash;Copy-Item -LiteralPath $source -Destination (Join-Path $root $c.path)}
$relative='Projects\'+$fixture.projectId+'\project.rigmovie';$target=Join-Path $root $relative;New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null;Copy-Item -LiteralPath $FixtureProject -Destination $target;$relative | Set-Content (Join-Path $root 'fixture-project.txt') -Encoding utf8
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null;$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-voice.json';$utf8=[Text.UTF8Encoding]::new($false);$checks=[Collections.Generic.List[string]]::new();$records=[Collections.Generic.List[object]]::new()
function Invoke-Pipe([string]$name,[string]$command,[hashtable]$arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{$client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message;$packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$command;args=$arguments};$bytes=$utf8.GetBytes(($packet | ConvertTo-Json -Depth 12 -Compress));if($bytes.Length -gt 60000){throw 'Pipe packet too large'}
  $client.Write($bytes,0,$bytes.Length);$client.Flush();$buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length);if(-not $read.Wait(6000)){throw 'Owned pipe timeout'};$response=$utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json;$records.Add(@{request=$packet;response=$response});return $response
 }finally{$client.Dispose()}
}
function Require-Ok($r){if(-not $r.ok){throw ('Pipe failed '+($r | ConvertTo-Json -Depth 6 -Compress))};return $r.data}
function Read-SharedJson($path){$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));try{$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true);try{$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}}finally{$stream.Dispose()}}
$version=Invoke-RestMethod 'http://127.0.0.1:50022/version' -TimeoutSec 5;if($version -ne '0.25.2'){throw 'Expected existing real engine version differs'}
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-voice';if($phase -eq 1){$flag='--verify-script-voice-reopen'};$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(240);$captured=@{}
 while(-not $process.HasExited){
  $request=$null;if(Test-Path ($result+'.capture-request.json')){try{$request=Read-SharedJson ($result+'.capture-request.json')}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json;if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection differs'};$pipe=$connection.commandPipe
   $status=Require-Ok (Invoke-Pipe $pipe 'app-script-status' @{});$common=@{projectId=$status.projectId;revision=$status.revision};$voice=Require-Ok (Invoke-Pipe $pipe 'app-script-voice' $common);$row=$voice.rows[0]
   if($status.wizard.stage -ne 'voice' -or $status.canAdvance -or $voice.rows.Count -ne 1 -or -not $voice.hasMore){throw 'Voice boundary or pagination differs'}
   if($request.stage -eq '.editing'){
    if(-not $status.textEditing -or $row.reading -eq $row.subtitle){throw 'Independent human reading input missing'}
    foreach($command in @('app-script-edit-voice','app-script-bind-voice','app-script-generate-voice','app-script-new')){if((Invoke-Pipe $pipe $command ($common+@{cueId=$row.cueId;reading='上書き';settings=@{};role=1;styleId=108;uuid='1bd6b32b-d650-4072-bbe5-1d0ef4aaa28b'})).ok){throw 'Human voice edit lock bypassed'};$checks.Add('human voice edit lock rejects '+$command)}
   }elseif($request.stage -eq '.generated'){
    if(-not $row.ready -or -not $row.stored -or $row.audioSeconds -le 0 -or $row.speaker.styleId -ne 108){throw 'Actual audio binding or measured metadata missing'}
    $catalog=Require-Ok (Invoke-Pipe $pipe 'app-script-voice-catalog' $common);if($catalog.styles.Count -gt 20 -or $catalog.engineUrl -ne 'http://127.0.0.1:50022'){throw 'Catalog bound or endpoint differs'}
    $checks.Add('live generated WAV LAB seconds and exact UUID/style are read through shared pipe');$checks.Add('real catalog is bounded to 20 styles')
   }elseif($request.stage -eq '.pipe'){
    $before=$row | ConvertTo-Json -Depth 8 -Compress
    foreach($change in @(@{revision=($common.revision-1)},@{projectId='wrong'},@{cueId='missing'},@{reading=('あ'*2001)},@{reading=('A'+[char]1)},@{settings=@{speedScale=99}},@{settings=@{unknownScale=1}},@{settings=@{VolumeScale=1}})){
     $updateArgs=$common+@{cueId=$row.cueId;reading='変更候補';settings=@{speedScale=1}};foreach($k in $change.Keys){$updateArgs[$k]=$change[$k]};if((Invoke-Pipe $pipe 'app-script-edit-voice' $updateArgs).ok){throw 'Invalid voice update accepted'}
     $current=(Require-Ok (Invoke-Pipe $pipe 'app-script-voice' $common)).rows[0];if(($current | ConvertTo-Json -Depth 8 -Compress) -ne $before){throw 'Rejected voice update partially mutated cue'};$checks.Add('invalid voice update atomically rejected '+(@($change.Keys)[0]))
    }
    if((Invoke-Pipe $pipe 'app-script-bind-voice' ($common+@{role=1;styleId=108;uuid='guessed'})).ok){throw 'Unverified speaker UUID accepted'};$checks.Add('binding rejects guessed UUID')
    $accepted=Require-Ok (Invoke-Pipe $pipe 'app-script-edit-voice' ($common+@{cueId=$row.cueId;reading='ぱいぷでかくにんです。';settings=@{speedScale=0.97;pitchScale=0.02;intonationScale=1;volumeScale=1;prePhonemeLength=0.1;postPhonemeLength=0.1}}))
    $changed=(Require-Ok (Invoke-Pipe $pipe 'app-script-voice' @{projectId=$accepted.projectId;revision=$accepted.revision})).rows[0]
    if($changed.reading -ne 'ぱいぷでかくにんです。' -or $changed.subtitle -ne $row.subtitle -or $changed.sourceText -ne $row.sourceText -or $changed.sceneId -ne $row.sceneId -or $changed.waveFile -ne $row.waveFile -or $changed.ready){throw 'Pipe reading edit crossed subtitle source audio retention boundary'};$checks.Add('actual pipe reading edit keeps source subtitle scene and prior WAV but marks stale')
   }elseif($request.stage -in @('.saved','.reopened')){
    if(-not $row.ready -or $row.reading -ne 'ぱいぷでかくにんです。'){throw 'Saved reading and actual audio not retained'};$checks.Add('saved binding reading query and actual audio ready at '+$request.stage)
   }else{throw 'Unknown voice capture'}
   $records | ConvertTo-Json -Depth 15 | Set-Content ($result+'.pipe-transcript.json') -Encoding utf8
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png');$request.token | Set-Content ($result+'.capture-ack.txt') -Encoding utf8;$captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation still active preserve PID/root '+$process.Id+' '+$root)};Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit();if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Voice GUI validation failed'}
}
if((Get-FileHash $FixtureProject).Hash -ne $sourceHash){throw 'Original semantic fixture changed'};foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Original rigm changed'}}
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$second=Get-Content ($result+'.reopened.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$checks;engineVersion=$version;testVoice='Explicit fixture-only Tohoku Kiritan normal 108 actual UUID';source=$FixtureProject;sourceHash=$sourceHash;originalCharacterHashes=$hashes;noVideoEncoding=$true} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
