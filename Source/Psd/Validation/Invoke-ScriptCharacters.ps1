param([Parameter(Mandatory=$true)][string]$ExecutablePath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptStage2-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
@{owner='RIGMMaker.ScriptStage2.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
# ユーザー素材は読み取り専用で、所有Tempへコピーして検証する。
$source='D:\Users\take6\RIGMMaker'
$sources=@('Characters\blonde-android-20261005.psdchar','RIGM\character-5F644440-BD54-4F76-A1C2-91E152D6516D.rigm','RIGM\character-701CDB41-B20C-40F1-82D3-FCC623EF6C3F.rigm')
$hashes=@{}
foreach($f in $sources){$inputPath=Join-Path $source $f;$hashes[$f]=(Get-FileHash $inputPath).Hash;$dest=Join-Path $root $f;New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null;Copy-Item -LiteralPath $inputPath -Destination $dest}
$outputDir=Join-Path $repo 'Win64\Validation\ScriptStage2'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$result=Join-Path $outputDir 'script-characters.json'
$exe=[IO.Path]::GetFullPath($ExecutablePath)
$utf8=[Text.UTF8Encoding]::new($false)
function Read-CaptureRequest([string]$Path){
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try {$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true);try {$reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}} finally {$stream.Dispose()}
}
function Invoke-OwnedPipe([string]$PipeName,[string]$Command,[hashtable]$Arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$PipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try {
  $client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
  $packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$Command;args=$Arguments} | ConvertTo-Json -Depth 8 -Compress
  $bytes=$utf8.GetBytes($packet);$client.Write($bytes,0,$bytes.Length);$client.Flush()
  $buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length)
  if(-not $read.Wait(5000)){throw 'Owned pipe timed out'}
  $utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
 } finally {$client.Dispose()}
}
$pipeChecks=@()
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-characters';if($phase -eq 1){$flag='--verify-script-characters-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(90);$captured=@{};$pipeCompleted=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json'
  if(Test-Path -LiteralPath $requestPath){
   $request=$null
   try {$request=Read-CaptureRequest $requestPath} catch [IO.IOException] {}
   if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
    if($request.stage -eq '.pipechars' -and -not $pipeCompleted.ContainsKey($request.token)){
     $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
     if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned pipe identity mismatch'}
     $status=Invoke-OwnedPipe $connection.commandPipe 'app-script-status' @{}
     if(-not $status.ok -or $status.data.wizard.stage -ne 'characters' -or $status.data.canAdvance){throw 'Unexpected character stage'}
     $catalog=Invoke-OwnedPipe $connection.commandPipe 'app-script-character-library' @{}
     if(-not $catalog.ok -or @($catalog.data.characters | Where-Object readyForScript).Count -ne 2){throw 'Completion catalog mismatch'}
     $first=$status.data.wizard.selectedCharacters[0].path
     $common=@{projectId=$status.data.projectId;revision=$status.data.revision}
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-stage' ($common+@{stage='placement'})
     if($invalid.ok){throw 'Unimplemented stage accepted'}
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-characters' ($common+@{paths=@('..\outside.rigm')})
     if($invalid.ok){throw 'Escaping path accepted'}
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-characters' ($common+@{paths=@($first,$first)})
     if($invalid.ok){throw 'Duplicate character accepted'}
     $unfinished=@($catalog.data.characters | Where-Object {-not $_.readyForScript})[0].path
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-characters' ($common+@{paths=@($unfinished)})
     if($invalid.ok){throw 'Incomplete character accepted'}
     $changed=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-characters' ($common+@{paths=@($first)})
     if(-not $changed.ok -or $changed.data.wizard.selectedCharacters.Count -ne 1 -or $changed.data.wizard.selectedCharacters[0].voiceBinding.speakerId -ne 'retained-test-speaker'){throw 'Shared selection or retained voice metadata mismatch'}
     $stale=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-characters' ($common+@{paths=@()})
     if($stale.ok){throw 'Stale revision accepted'}
     $saved=Invoke-OwnedPipe $connection.commandPipe 'app-script-save' @{projectId=$changed.data.projectId;revision=$changed.data.revision}
     if(-not $saved.ok -or $saved.data.modified -or $saved.data.wizard.charactersStatus -ne 'in-progress'){throw 'Save confirmation boundary failed'}
     $pipeChecks=@('actual catalog completion state','unimplemented stage rejected','path escape rejected','duplicate rejected','incomplete rejected','same GUI state changed with voice metadata retained','stale revision rejected','save without human confirmation')
     $pipeCompleted[$request.token]=$true
    }
    & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
    try {$request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8 -ErrorAction Stop} catch [IO.IOException] {Start-Sleep -Milliseconds 25;continue}
    $captured[$request.token]=$true
   }
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned check still running; retain PID/root: '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 50
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding UTF8 -ErrorAction SilentlyContinue;throw 'Owned character verification failed'}
 $expected=2;if($phase -eq 1){$expected=1};if($captured.Count -ne $expected){throw 'Owned captures missing'}
}
foreach($f in $sources){if((Get-FileHash (Join-Path $source $f)).Hash -ne $hashes[$f]){throw 'Original material changed externally during verification'}}
$first=Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
$second=Get-Content ($result+'.reopened.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($first.checks.Count -lt 18 -or $second.checks.Count -ne 4 -or $pipeChecks.Count -ne 8){throw 'Stage checks incomplete'}
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$pipeChecks;originalHashes=$hashes;captures=3;result=$result} | ConvertTo-Json -Depth 6 | Tee-Object -FilePath ($result+'.metadata.json')
