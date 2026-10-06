param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptStage3-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
@{owner='RIGMMaker.ScriptStage3.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$source='D:\Users\take6\RIGMMaker'
$sources=@('Characters\blonde-android-20261005.psdchar','RIGM\character-5F644440-BD54-4F76-A1C2-91E152D6516D.rigm','RIGM\character-701CDB41-B20C-40F1-82D3-FCC623EF6C3F.rigm')
$hashes=@{}
foreach($f in $sources){$p=Join-Path $source $f;$hashes[$f]=(Get-FileHash $p).Hash;$dest=Join-Path $root $f;New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null;Copy-Item -LiteralPath $p -Destination $dest}
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null
$result=Join-Path $output 'script-layout.json';$exe=[IO.Path]::GetFullPath($ExecutablePath);$utf8=[Text.UTF8Encoding]::new($false)
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
 $flag='--verify-script-layout';if($phase -eq 1){$flag='--verify-script-layout-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(90);$captured=@{};$pipeCompleted=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json'
  if(Test-Path -LiteralPath $requestPath){
   $request=$null;try {$request=Read-CaptureRequest $requestPath} catch [IO.IOException] {}
   if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
    if($request.stage -eq '.pipe' -and -not $pipeCompleted.ContainsKey($request.token)){
     $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
     if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned pipe identity mismatch'}
     $status=Invoke-OwnedPipe $connection.commandPipe 'app-script-status' @{}
     if(-not $status.ok -or $status.data.wizard.stage -ne 'layout' -or $status.data.canAdvance -or $status.data.layoutGuide.coordinateSpace -ne 'ratio'){throw 'Unexpected layout state'}
     $common=@{projectId=$status.data.projectId;revision=$status.data.revision}
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-stage' ($common+@{stage='placement'})
     if($invalid.ok){throw 'Stage four accepted'}
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-layout' ($common+@{choice='unknown'})
     if($invalid.ok){throw 'Invalid layout accepted'}
     $invalid=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-layout' ($common+@{choice='theme';backgroundTone='unknown'})
     if($invalid.ok){throw 'Invalid background accepted'}
     $changed=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-layout' ($common+@{choice='theme';backgroundTone='blue'})
     if(-not $changed.ok -or $changed.data.wizard.selectedCharacters.Count -ne 2 -or -not $changed.data.modified -or $changed.data.wizard.layoutStatus -ne 'in-progress'){throw 'Shared layout update mismatch'}
     $stale=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-layout' ($common+@{choice='l-left'})
     if($stale.ok){throw 'Stale revision accepted'}
     $saved=Invoke-OwnedPipe $connection.commandPipe 'app-script-save' @{projectId=$changed.data.projectId;revision=$changed.data.revision}
     if(-not $saved.ok -or $saved.data.modified -or $saved.data.wizard.layoutStatus -ne 'in-progress'){throw 'Save confirmation boundary failed'}
     $pipeChecks=@('same shared layout state and ratio guide','stage four rejected','invalid layout rejected','invalid background rejected','multiple selections preserved on change','stale revision rejected','save without human confirmation')
     $pipeCompleted[$request.token]=$true
    }
    & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
    try {$request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8 -ErrorAction Stop} catch [IO.IOException] {Start-Sleep -Milliseconds 25;continue}
    $captured[$request.token]=$true
   }
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned layout check still running; retain PID/root: '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 50
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding UTF8 -ErrorAction SilentlyContinue;throw 'Owned layout verification failed'}
 $expected=4;if($phase -eq 1){$expected=1};if($captured.Count -ne $expected){throw 'Owned layout captures missing'}
}
foreach($f in $sources){if((Get-FileHash (Join-Path $source $f)).Hash -ne $hashes[$f]){throw 'Original material changed externally'}}
$first=Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
$second=Get-Content ($result+'.reopened.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($first.checks.Count -lt 15 -or $second.checks.Count -lt 5 -or $pipeChecks.Count -ne 7){throw 'Stage three checks incomplete'}
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$pipeChecks;originalHashes=$hashes;captures=5;result=$result} | ConvertTo-Json -Depth 6 | Tee-Object -FilePath ($result+'.metadata.json')
