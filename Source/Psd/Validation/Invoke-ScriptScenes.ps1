param([Parameter(Mandatory)][string]$ExecutablePath,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$FixtureDataRoot)
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8
$relative=(Get-Content -LiteralPath (Join-Path $FixtureDataRoot 'fixture-project.txt') -Raw -Encoding utf8).Trim();$source=Join-Path $FixtureDataRoot $relative
$fixture=Get-Content -LiteralPath $source -Raw -Encoding utf8 | ConvertFrom-Json
if($fixture.title -ne 'Codex実往復用：架空の星空観測所' -or $fixture.scriptWizard.stage -ne 'voice'){throw 'Owned Stage9 fiction required'}
$sourceHash=(Get-FileHash $source).Hash;$hashes=@{};$root=Join-Path $env:TEMP ('RIGMMaker-ScriptScenes-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptScenes.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
foreach($character in $fixture.scriptWizard.selectedCharacters){if($character.path -notin @('RIGM\casting-guide.rigm','RIGM\casting-question.rigm')){throw 'Owned character required'};$original=Join-Path $FixtureDataRoot $character.path;$hashes[$original]=(Get-FileHash $original).Hash;Copy-Item -LiteralPath $original -Destination (Join-Path $root $character.path)}
$target=Join-Path $root $relative;New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
Get-ChildItem -LiteralPath (Split-Path $source) -Force | Copy-Item -Destination (Split-Path $target) -Recurse
$relative | Set-Content (Join-Path $root 'fixture-project.txt') -Encoding utf8
Add-Type -AssemblyName System.Drawing
$bitmap=[Drawing.Bitmap]::new(600,200);$random=[Random]::new(1006)
try{for($y=0;$y -lt 200;$y++){for($x=0;$x -lt 600;$x++){$bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb(255,$random.Next(50,255),$random.Next(50,255),$random.Next(50,255)))}};$bitmap.Save((Join-Path $root 'local-fixture.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
$image=[IO.File]::ReadAllBytes((Join-Path $root 'local-fixture.png'));$imageHash=(Get-FileHash (Join-Path $root 'local-fixture.png')).Hash.ToLowerInvariant()
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null;$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-scenes.json';$utf8=[Text.UTF8Encoding]::new($false);$checks=[Collections.Generic.List[string]]::new();$records=[Collections.Generic.List[object]]::new()
function Invoke-Pipe([string]$name,[string]$command,[hashtable]$arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{$client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message;$packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$command;args=$arguments};$bytes=$utf8.GetBytes(($packet | ConvertTo-Json -Depth 10 -Compress));if($bytes.Length -gt 60000){throw 'Pipe packet too large'};$client.Write($bytes,0,$bytes.Length);$client.Flush();$buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length);if(-not $read.Wait(6000)){throw 'Owned pipe timeout'};$reply=$utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json;$records.Add(@{command=$command;args=($arguments | Select-Object * -ExcludeProperty data);response=$reply});return $reply
 }finally{$client.Dispose()}
}
function Require-Ok($r){if(-not $r.ok){throw ('Pipe failed '+($r | ConvertTo-Json -Depth 6 -Compress))};return $r.data}
function Current($pipe){$s=Require-Ok (Invoke-Pipe $pipe 'app-script-status' @{});return @{projectId=$s.projectId;revision=$s.revision}}
function Send-Image($pipe,$row){
 $common=Current $pipe;$begin=Require-Ok (Invoke-Pipe $pipe 'app-script-image-transfer-begin' ($common+@{sceneId=$row.id;requestId=$row.imageRequest.requestId;byteCount=$image.Length;sha256=$imageHash;mimeType='image/png';provenance='test-fixture'}));$id=$begin.transferId
 if((Invoke-Pipe $pipe 'app-script-image-transfer-finish' @{transferId=$id}).ok){throw 'Incomplete transfer finished'};$checks.Add('incomplete finish rejects')
 if((Invoke-Pipe $pipe 'app-script-image-transfer-chunk' @{transferId=$id;offset=16384;data=[Convert]::ToBase64String($image,16384,16384)}).ok){throw 'Out of order accepted'};$checks.Add('out of order chunk rejects')
 for($offset=0;$offset -lt $image.Length;$offset+=16384){$args=@{transferId=$id;offset=$offset;data=[Convert]::ToBase64String($image,$offset,[Math]::Min(16384,$image.Length-$offset))};$reply=Invoke-Pipe $pipe 'app-script-image-transfer-chunk' $args;if(-not $reply.ok){Start-Sleep -Milliseconds 30;$reply=Invoke-Pipe $pipe 'app-script-image-transfer-chunk' $args};Require-Ok $reply | Out-Null;if($offset -eq 0){Require-Ok (Invoke-Pipe $pipe 'app-script-image-transfer-chunk' $args) | Out-Null}}
 Require-Ok (Invoke-Pipe $pipe 'app-script-image-transfer-finish' @{transferId=$id}) | Out-Null;$deadline=[DateTime]::UtcNow.AddSeconds(20)
 do{$ready=Require-Ok (Invoke-Pipe $pipe 'app-script-image-transfer-status' @{transferId=$id});if($ready.state -eq 'failed'){throw $ready.error};if([DateTime]::UtcNow -gt $deadline){throw 'Transfer decode timeout'};Start-Sleep -Milliseconds 20}while($ready.state -ne 'ready')
 if($ready.width -ne 600 -or $ready.height -ne 200 -or (Get-FileHash $ready.path).Hash.ToLowerInvariant() -ne $imageHash){throw 'Actual received image differs'};$checks.Add('real ordered PNG bytes hash dimensions decode verified');return $id
}
$version=Invoke-RestMethod 'http://127.0.0.1:50022/version' -TimeoutSec 5;if($version -ne '0.25.2'){throw 'Expected existing engine differs'}
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-scenes';if($phase -eq 1){$flag='--verify-script-scenes-reopen'};$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(180);$captured=@{}
 while(-not $process.HasExited){
  $request=$null;if(Test-Path ($result+'.capture-request.json')){try{$request=Get-Content ($result+'.capture-request.json') -Raw -Encoding utf8 | ConvertFrom-Json}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json;if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection differs'};$pipe=$connection.commandPipe;$common=Current $pipe
   if($request.stage -ne '.saved'){$scenes=Require-Ok (Invoke-Pipe $pipe 'app-script-scenes' $common);$row=$scenes.rows[0];if($scenes.rows.Count -ne 1 -or -not $scenes.hasMore){throw 'Scene pagination differs'}}
   if($request.stage -eq '.editing'){
    foreach($command in @('app-script-edit-scene','app-script-request-scene-image','app-script-next','app-script-image-transfer-begin','app-script-new')){if((Invoke-Pipe $pipe $command ($common+@{sceneId=$row.id;description='上書き';prompt='上書き';displayMode='none';requestId='missing'})).ok){throw 'Human edit lock bypassed'};$checks.Add('human scene lock rejects '+$command)}
   }elseif($request.stage -eq '.transfer'){
    if($row.imageRequest.state -ne 'pending' -or -not $row.imageRequest.current){throw 'Pending request missing'};$before=$row.imagePath
    $beforeRow=$row | ConvertTo-Json -Depth 8 -Compress
    foreach($change in @(@{revision=($common.revision-1)},@{projectId='wrong'},@{description=('あ'*3001)},@{displayMode='invalid'},@{description=('A'+[char]1)})){$a=$common+@{sceneId=$row.id;description='不正変更'};foreach($key in $change.Keys){$a[$key]=$change[$key]};if((Invoke-Pipe $pipe 'app-script-edit-scene' $a).ok){throw 'Invalid scene edit accepted'};$afterRow=(Require-Ok (Invoke-Pipe $pipe 'app-script-scenes' $common)).rows[0];if(($afterRow | ConvertTo-Json -Depth 8 -Compress) -ne $beforeRow){throw 'Rejected update partly changed scene'};$checks.Add('invalid scene edit atomically rejected '+(@($change.Keys)[0]))}
    $first=Send-Image $pipe $row;$common=Current $pipe;Require-Ok (Invoke-Pipe $pipe 'app-script-edit-scene' ($common+@{sceneId=$row.id;description='パイプからの確認修正。架空作品です。'})) | Out-Null;$common=Current $pipe
    if((Invoke-Pipe $pipe 'app-script-image-transfer-adopt' ($common+@{transferId=$first;requestId=$row.imageRequest.requestId})).ok){throw 'Stale image overwrote newer text'};$checks.Add('latest revision still rejects stale image scene fingerprint')
    $new=(Require-Ok (Invoke-Pipe $pipe 'app-script-scenes' $common)).rows[0];if($new.imagePath -ne $before -or $new.description -ne 'パイプからの確認修正。架空作品です。'){throw 'Rejected image changed scene'}
    Require-Ok (Invoke-Pipe $pipe 'app-script-request-scene-image' ($common+@{sceneId=$row.id})) | Out-Null;$common=Current $pipe;$new=(Require-Ok (Invoke-Pipe $pipe 'app-script-scenes' $common)).rows[0];$second=Send-Image $pipe $new
    Require-Ok (Invoke-Pipe $pipe 'app-script-image-transfer-adopt' ((Current $pipe)+@{transferId=$second;requestId=$new.imageRequest.requestId})) | Out-Null;$checks.Add('fresh request current scene adopts labelled real PNG')
   }elseif($request.stage -eq '.preview'){
    if(-not $scenes.preview.current -or -not(Test-Path $scenes.preview.path) -or $row.imageRequest.state -ne 'adopted' -or -not $row.imageRequest.current){throw 'Current real preview or adopted request differs'};$checks.Add('pipe reads current real preview and adopted fingerprint')
   }elseif($request.stage -eq '.reopened'){
    if(-not $row.ready -or -not $row.imageRequest.current -or $row.imageRequest.imageProvenance -ne 'test-fixture' -or $row.description -ne 'パイプからの確認修正。架空作品です。'){throw 'Saved material differs'};$checks.Add('normal restart retains real image independent text current request and provenance')
   }elseif($request.stage -ne '.saved'){throw 'Unknown scene capture'}
   $records | ConvertTo-Json -Depth 15 | Set-Content ($result+'.pipe-transcript.json') -Encoding utf8
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png');$request.token | Set-Content ($result+'.capture-ack.txt') -Encoding utf8;$captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation still active preserve PID/root '+$process.Id+' '+$root)};Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit();if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Scenes validation failed'}
}
if((Get-FileHash $source).Hash -ne $sourceHash){throw 'Original Stage9 fiction changed'};foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Original character changed'}}
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$second=Get-Content ($result+'.reopened.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$checks;engineVersion=$version;imageProvenance='test-fixture';fixtureSource=$source;sourceHash=$sourceHash;originalCharacterHashes=$hashes;noVideoEncoding=$true} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
