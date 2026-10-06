param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$DataRoot=([IO.Path]::Combine([Environment]::GetFolderPath('MyDocuments'),'RIGMMaker')))
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptCasting-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptCasting.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
$source=Get-ChildItem -LiteralPath (Join-Path $DataRoot 'RIGM') -File -Filter '*.rigm' | Select-Object -First 1
if($null -eq $source){throw 'Existing registered RIGM required'}
$originalHash=(Get-FileHash $source.FullName).Hash
foreach($name in @('casting-guide.rigm','casting-question.rigm')){Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $root ('RIGM\'+$name))}
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null
$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-casting.json';$utf8=[Text.UTF8Encoding]::new($false)
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
function Read-Casting($pipe,$common){
 $all=@();$offset=0
 do{$part=Invoke-Pipe $pipe 'app-script-casting' ($common+@{offset=$offset});if(-not $part.ok){throw ('Casting read failed '+($part | ConvertTo-Json -Depth 8 -Compress))};$all+=@($part.data.rows);$offset=$part.data.nextOffset}while($part.data.hasMore)
 return ,$all
}
$checks=[Collections.Generic.List[string]]::new()
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-casting';if($phase -eq 1){$flag='--verify-script-casting-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$captured=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json';$request=$null
  if(Test-Path -LiteralPath $requestPath){try{$request=Read-SharedJson $requestPath}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json
   if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection identity mismatch'}
   $pipe=$connection.commandPipe;$status=Invoke-Pipe $pipe 'app-script-status' @{}
   if(-not $status.ok){throw 'Status unavailable'}
   $common=@{projectId=$status.data.projectId;revision=$status.data.revision}
   if($request.stage -in @('.review','.review2')){
    if($status.data.wizard.stage -ne 'review' -or $status.data.canAdvance){throw 'Pending review boundary invalid'}
    $review=Invoke-Pipe $pipe 'app-script-review' $common
    # Empty completed batch is a transport fixture, never a claim of semantic AI proofreading.
    $packet=$common+@{requestId=$review.data.requestId;fingerprint=$review.data.fingerprint;complete=$true;items=@()}
    $accepted=Invoke-Pipe $pipe 'app-script-submit-review' $packet
    if(-not $accepted.ok -or -not $accepted.data.canAdvance){throw ('Review receipt failed '+($accepted | ConvertTo-Json -Depth 8 -Compress))}
    $checks.Add('review receipt explicitly gates casting Next')
   }else{
    if($status.data.wizard.stage -ne 'casting' -or $status.data.canAdvance){throw 'Casting subtitle boundary invalid'}
    $rows=Read-Casting $pipe $common
    if($null -ne $status.data.wizard.casting.rows -or $null -ne $status.data.wizard.castingArchives -or @($status.data.wizard.scriptText.sections | Where-Object {$null -ne $_.text}).Count -gt 0){throw 'Status leaked unbounded source'}
    if($request.stage -eq '.pending'){
     if($rows.Count -ne 4 -or -not $rows[0].confirmed){throw 'Human assignment missing before actual pipe'}
     $cast=$status.data.wizard.casting
     $items=@($rows | Where-Object {-not $_.confirmed} | ForEach-Object {@{cueId=$_.cueId;role=2;reason='配役輸送fixture。意味のAI判定済みとは扱いません。'}})
     $packet=$common+@{requestId=$cast.requestId;fingerprint=$cast.fingerprint;complete=$true;items=$items}
     foreach($change in @(@{requestId='wrong'},@{fingerprint=('0'*64)},@{revision=($common.revision-1)},@{projectId='wrong'})){
      $invalid=@{}+$packet;foreach($key in $change.Keys){$invalid[$key]=$change[$key]}
      if((Invoke-Pipe $pipe 'app-script-submit-casting' $invalid).ok){throw 'Invalid casting identity accepted'}
      $checks.Add('casting identity rejected '+(@($change.Keys)[0]))
     }
     foreach($bad in @(@{cueId=$rows[0].cueId;role=2},@{cueId=$rows[1].cueId;role=0},@{cueId=$rows[1].cueId;role=10},@{cueId='unknown';role=2},$items[0])){
      $invalid=@{}+$packet;$invalid.items=@($items[0],$bad)
      if((Invoke-Pipe $pipe 'app-script-submit-casting' $invalid).ok){throw 'Invalid or confirmed casting row accepted'}
      if((Read-Casting $pipe $common)[1].role -ne 0){throw 'Rejected batch partially mutated'}
      $checks.Add('invalid or confirmed row batch rejected atomically')
     }
     $accepted=Invoke-Pipe $pipe 'app-script-submit-casting' $packet
     if(-not $accepted.ok){throw ('Casting submission failed '+($accepted | ConvertTo-Json -Depth 8 -Compress))}
     $after=Read-Casting $pipe @{projectId=$accepted.data.projectId;revision=$accepted.data.revision}
     if(-not $after[0].confirmed -or $after[0].role -ne 1 -or $after[1].role -ne 2 -or $after[1].confirmed -or $after[1].origin -ne 'ai'){throw 'Casting proposal overwrote human or confirmed itself'}
     if((Invoke-Pipe $pipe 'app-script-submit-casting' $packet).ok){throw 'Obsolete repeated casting accepted'}
     $oldRequest=$cast.requestId;$oldFingerprint=$cast.fingerprint
     $checks.Add('actual bounded pipe reads and unconfirmed AI proposals preserve human choice');$checks.Add('repeated obsolete result rejected')
    }elseif($request.stage -eq '.split'){
     if($rows.Count -ne 5 -or $rows[1].sceneId -ne $rows[2].sceneId){throw 'Split pipe view disagrees with GUI'}
     $invalid=$common+@{requestId=$oldRequest;fingerprint=$oldFingerprint;complete=$true;items=@()}
     if((Invoke-Pipe $pipe 'app-script-submit-casting' $invalid).ok){throw 'Old casting result accepted after split'}
     $checks.Add('old result rejected after speech boundary split')
    }elseif($request.stage -in @('.saved','.reopened')){
     if($rows.Count -ne 4 -or $rows[1].text -eq $rows[1].subtitle){throw 'Separate display and audio text lost'}
     $checks.Add('bounded saved and reopened casting keeps separate audio and subtitle text')
    }
   }
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
   $request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding utf8
   $captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned verification remains active, preserve PID/root '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Casting GUI verification failed'}
}
if((Get-FileHash $source.FullName).Hash -ne $originalHash){throw 'Original material changed'}
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$second=Get-Content ($result+'.reopened.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;exe=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$checks;originalPath=$source.FullName;originalHash=$originalHash;semanticFixture=($result+'.semantic-fixture.json')} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
