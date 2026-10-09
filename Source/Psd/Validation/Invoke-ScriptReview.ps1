param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$DataRoot=([IO.Path]::Combine([Environment]::GetFolderPath('MyDocuments'),'RIGMMaker')))
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptReview-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptReview.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
$sources=@(Get-ChildItem -LiteralPath (Join-Path $DataRoot 'RIGM') -File -Filter '*.rigm' | Select-Object -First 1)
if($sources.Count -eq 0){throw 'An existing registered RIGM is required; do not invent take6 paths'}
$hashes=@{}
foreach($source in $sources){$hashes[$source.FullName]=(Get-FileHash $source.FullName).Hash;Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $root ('RIGM\'+$source.Name))}
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null
$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-review.json';$utf8=[Text.UTF8Encoding]::new($false)
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
$checks=[Collections.Generic.List[string]]::new()
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-review';if($phase -eq 1){$flag='--verify-script-review-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$captured=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json';$request=$null
  if(Test-Path -LiteralPath $requestPath){try{$request=Read-SharedJson $requestPath}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json
   if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection identity mismatch'}
   $pipe=$connection.commandPipe;$status=Invoke-Pipe $pipe 'app-script-status' @{}
   if(-not $status.ok -or $status.data.wizard.stage -ne 'review' -or $status.data.canAdvance){throw 'Review stage boundary invalid'}
   $common=@{projectId=$status.data.projectId;revision=$status.data.revision}
   if($request.stage -in @('.requested','.fresh')){
    $review=Invoke-Pipe $pipe 'app-script-review' $common
    $body=Invoke-Pipe $pipe 'app-script-text' ($common+@{section='body'})
    if(-not $review.ok -or -not $body.ok -or $review.data.state -ne 'requested'){throw 'Codex read contract failed'}
    $packet=$common+@{requestId=$review.data.requestId;fingerprint=$review.data.fingerprint;complete=$true}
    if($request.stage -eq '.requested'){
     # Explicit transport fixtures: these suggestions test UI behavior; the app never generates them.
     $items=@(
      @{id='weather';section='body';offset=3;original='晴れです';proposed='よく晴れています';reason='検証用の言い換え案。事実確認済みとは扱いません。'},
      @{id='repeat';section='body';offset=12;original='語語';proposed='語';reason='同じ語の重複を削る提案。'},
      @{id='overlap';section='body';offset=3;original='晴れ';proposed='快晴';reason='重なった指摘の失効確認用。'},
      @{id='last';section='body';offset=22;original='最後の行です。';proposed='説明は以上です。';reason='締めの言い換え案。人の修正・保留確認用。'},
      @{id='phrase';section='body';offset=10;original='同じ';proposed='同じ';reason='未確定の指摘を残した編集失効確認用。'}
     )
     foreach($change in @(@{requestId='wrong'},@{fingerprint=('0'*64)},@{revision=($common.revision-1)})){
      $invalid=@{}+$packet;$invalid.items=$items;foreach($key in $change.Keys){$invalid[$key]=$change[$key]}
      if((Invoke-Pipe $pipe 'app-script-submit-review' $invalid).ok){throw 'Invalid request identity accepted'}
     }
     $invalid=@{}+$packet;$invalid.items=@($items[0],@{id='bad';section='body';offset=0;original='古い原稿';proposed='変更';reason='invalid'})
     if((Invoke-Pipe $pipe 'app-script-submit-review' $invalid).ok){throw 'Invalid anchor accepted'}
     if((Invoke-Pipe $pipe 'app-script-review' $common).data.count -ne 0){throw 'Failed batch partially mutated canonical items'}
     $invalid=@{}+$packet;$invalid.items=@($items[0],$items[0]);if((Invoke-Pipe $pipe 'app-script-submit-review' $invalid).ok){throw 'Duplicate IDs accepted'}
     $checks.Add('request ID mismatch rejected');$checks.Add('fingerprint mismatch rejected');$checks.Add('stale revision rejected');$checks.Add('anchor mismatch atomically rejected');$checks.Add('duplicate IDs rejected')
    }else{
     $oldPacket=@{}+$packet;$oldPacket.requestId=$originalRequestId;$oldPacket.items=@()
     if((Invoke-Pipe $pipe 'app-script-submit-review' $oldPacket).ok){throw 'Old result accepted after human edit'}
     $items=@(@{id='fresh';section='body';offset=0;original='今日は';proposed='本日は';reason='新しい原稿だけに対する検証用提案。'})
     $checks.Add('old Codex result rejected after human edit')
    }
    $packet.items=$items;$accepted=Invoke-Pipe $pipe 'app-script-submit-review' $packet
    if(-not $accepted.ok){throw ('Actual submission failed: '+($accepted | ConvertTo-Json -Depth 8 -Compress))}
    if($request.stage -eq '.requested'){$originalRequestId=$review.data.requestId}
    $newCommon=@{projectId=$accepted.data.projectId;revision=$accepted.data.revision}
    $all=@();$offset=0
    do{$part=Invoke-Pipe $pipe 'app-script-review' ($newCommon+@{offset=$offset});if(-not $part.ok){throw 'Bounded review read failed'};$all+=@($part.data.items);$offset=$part.data.nextOffset}while($part.data.hasMore)
    if($all.Count -ne $items.Count -or $null -ne $accepted.data.wizard.review.items){throw 'Review pagination or summary unbounded'}
    if((Invoke-Pipe $pipe 'app-script-submit-review' $packet).ok){throw 'Repeated obsolete submission accepted'}
    $checks.Add('actual pipe reads source and submits anchored proposals');$checks.Add('bounded review pagination');$checks.Add('duplicate result rejected')
   }elseif($request.stage -eq '.editing'){
    if($status.data.textEditing){throw 'Review input unexpectedly locked communication'}
    $stale=@{projectId=$common.projectId;revision=($common.revision-1)}
    if((Invoke-Pipe $pipe 'app-script-request-review' $stale).ok){throw 'Stale review revision accepted'}
    $checks.Add('review input is unlocked and stale revision is rejected')
    if(-not (Invoke-Pipe $pipe 'app-script-text' ($common+@{section='body'})).ok){throw 'Read during human editing failed'}
    $checks.Add('source readable during human review edit')
   }
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
   $request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding utf8
   $captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned verification remains active, preserve PID/root '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Review GUI verification failed'}
}
foreach($source in $sources){if((Get-FileHash $source.FullName).Hash -ne $hashes[$source.FullName]){throw 'Original material changed'} }
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$second=Get-Content ($result+'.reopened.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;exe=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$checks;originalHashes=$hashes} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
