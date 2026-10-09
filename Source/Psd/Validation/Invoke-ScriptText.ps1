param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptStage5-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
@{owner='RIGMMaker.ScriptStage5.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$source='D:\Users\take6\RIGMMaker'
$sources=@('Characters\blonde-android-20261005.psdchar','RIGM\character-5F644440-BD54-4F76-A1C2-91E152D6516D.rigm','RIGM\character-701CDB41-B20C-40F1-82D3-FCC623EF6C3F.rigm')
$hashes=@{}
foreach($f in $sources){$p=Join-Path $source $f;$hashes[$f]=(Get-FileHash $p).Hash;$dest=Join-Path $root $f;New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null;Copy-Item -LiteralPath $p -Destination $dest}
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null
$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding UTF8
$result=Join-Path $output 'script-text.json';$exe=[IO.Path]::GetFullPath($ExecutablePath);$utf8=[Text.UTF8Encoding]::new($false)
function Read-CaptureRequest([string]$Path){
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try {$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true);try {$reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}} finally {$stream.Dispose()}
}
function Invoke-OwnedPipe([string]$PipeName,[string]$Command,[hashtable]$Arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$PipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try {
  $client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
  $packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$Command;args=$Arguments} | ConvertTo-Json -Depth 8 -Compress
  $bytes=$utf8.GetBytes($packet);if($bytes.Length -gt 60000){throw 'Test request exceeds pipe limit'};$client.Write($bytes,0,$bytes.Length);$client.Flush()
  $buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length)
  if(-not $read.Wait(5000)){throw 'Owned pipe timed out'}
  $utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
 } finally {$client.Dispose()}
}
$pipeChecks=@()
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-text';if($phase -eq 1){$flag='--verify-script-text-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$captured=@{};$pipeCompleted=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json'
  if(Test-Path -LiteralPath $requestPath){
   $request=$null;try {$request=Read-CaptureRequest $requestPath} catch [IO.IOException] {}
   if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
    & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
    if($request.stage -in @('.long','.editing','.pipe') -and -not $pipeCompleted.ContainsKey($request.token)){
     $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
     if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned pipe identity mismatch'}
     $status=Invoke-OwnedPipe $connection.commandPipe 'app-script-status' @{}
     if(-not $status.ok -or $status.data.wizard.stage -ne 'text' -or $status.data.resumeStage -ne 'text' -or $status.data.canAdvance){throw 'Text stage pipe boundary mismatch'}
     $common=@{projectId=$status.data.projectId;revision=$status.data.revision}
     if($request.stage -eq '.long'){
      if($status.data.textEditing -or $utf8.GetByteCount(($status | ConvertTo-Json -Depth 20 -Compress)) -gt 60000){throw 'Text summary or editing state invalid'}
      if($null -ne $status.data.wizard.scriptText.sections[1].text){throw 'Status unexpectedly includes unbounded raw text'}
      $all='';$offset=0;$pages=0
      do {
       $part=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' ($common+@{section='body';offset=$offset;limit=4096})
       if(-not $part.ok -or $part.data.offset -ne $offset -or $part.data.revision -ne $common.revision){throw 'Chunk read failed'}
       $all+=$part.data.text;$offset=$part.data.nextOffset;$pages++
      } while($part.data.hasMore)
      $emoji=[char]0xD83D+[string][char]0xDE00
      if($pages -lt 3 -or $all -ne (('文'*8191)+$emoji+"`r`n長文末尾")){throw 'Long text or surrogate chunk corrupted'}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' ($common+@{section='body';offset=8192;limit=1})
      if($invalid.ok){throw 'Surrogate middle offset accepted'}
      $changed=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' ($common+@{section='body';offset=$all.Length;removeCount=0;text='追記。'})
      if(-not $changed.ok){throw 'Long text patch failed'}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' ($common+@{section='body';offset=0})
      if($invalid.ok){throw 'Inconsistent old read revision accepted'}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' @{projectId=[guid]::NewGuid().ToString();section='body'}
      if($invalid.ok){throw 'Different read project accepted'}
      $pipeChecks+=@('bounded status for long text','three-page long text and surrogate preservation','surrogate middle offset rejected','long section tail patch','old read revision rejected','different read project rejected')
     } elseif($request.stage -eq '.editing'){
      if($status.data.textEditing){throw 'Text input unexpectedly locked communication'}
      foreach($section in @('opening','body','closing')){
       $read=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' ($common+@{section=$section})
       if(-not $read.ok -or $read.data.text.Length -eq 0){throw 'Read during typing failed'}
      }
      $text=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' ($common+@{section='body'})
      $accepted=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' ($common+@{section='body';text=$text.data.text})
      if(-not $accepted.ok){throw 'Focused text input rejected current pipe update'}
      $stale=@{projectId=$common.projectId;revision=($common.revision-1);section='body';text='競合'}
      if((Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' $stale).ok){throw 'Stale text revision accepted'}
      $pipeChecks+=@('all sections readable during typing','current text update accepted without leaving input','stale text revision rejected')
     } else {
      if($status.data.textEditing){throw 'Input complete did not unlock'}
      $read=Invoke-OwnedPipe $connection.commandPipe 'app-script-text' ($common+@{section='body'})
      $changed=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' ($common+@{section='body';offset=$read.data.length;removeCount=0;text="`r`nパイプから追記しました。"})
      if(-not $changed.ok -or $changed.data.revision -le $common.revision){throw 'Text patch did not update shared revision'}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' ($common+@{section='body';text='古い版'})
      if($invalid.ok){throw 'Stale write revision accepted'}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' @{projectId=[guid]::NewGuid().ToString();revision=$changed.data.revision;section='body';text='別作品'}
      if($invalid.ok){throw 'Wrong project accepted'}
      $newCommon=@{projectId=$changed.data.projectId;revision=$changed.data.revision}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' ($newCommon+@{section='unknown';text='不明'})
      if($invalid.ok){throw 'Unknown section accepted'}
      $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-text' ($newCommon+@{section='body';text=('文'*4097)})
      if($invalid.ok){throw 'Oversized pipe text accepted'}
      $saved=Invoke-OwnedPipe $connection.commandPipe 'app-script-save' $newCommon
      if(-not $saved.ok -or $saved.data.modified -or $saved.data.resumeStage -ne 'text'){throw 'Text draft save failed'}
      $disk=Get-Content $saved.data.path -Raw -Encoding UTF8 | ConvertFrom-Json
      if($disk.scriptWizard.stage -ne 'text' -or $disk.scriptWizard.scriptText.sections.Count -ne 3 -or $disk.characters.Count -gt 0){throw 'Text saved wrong state'}
      $pipeChecks+=@('text patch updates shared GUI state','stale write revision rejected','different project rejected','unknown section rejected','oversized pipe text rejected','save retains text destination and no production')
     }
     $pipeCompleted[$request.token]=$true
    }
    try {$request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8 -ErrorAction Stop} catch [IO.IOException] {Start-Sleep -Milliseconds 25;continue}
    $captured[$request.token]=$true
   }
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned text check still running; retain PID/root: '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 50
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding UTF8 -ErrorAction SilentlyContinue;throw 'Owned text verification failed'}
 $expected=4;if($phase -eq 1){$expected=1};if($captured.Count -ne $expected){throw 'Owned text captures missing'}
}
foreach($f in $sources){if((Get-FileHash (Join-Path $source $f)).Hash -ne $hashes[$f]){throw 'Original material changed externally'}}
$first=Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
$second=Get-Content ($result+'.reopened.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($first.checks.Count -lt 25 -or $second.checks.Count -lt 8 -or $pipeChecks.Count -ne 17){throw 'Stage five checks incomplete'}
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$pipeChecks;originalHashes=$hashes;captures=5;result=$result} | ConvertTo-Json -Depth 6 | Tee-Object -FilePath ($result+'.metadata.json')
