param([Parameter(Mandatory=$true)][string]$ExecutablePath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptStage1-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
@{owner='RIGMMaker.ScriptStage1.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$outputDir=Join-Path $repo 'Win64\Validation\ScriptStage1'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$result=Join-Path $outputDir 'script-title.json'
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
  if(-not $read.Wait(5000)){throw 'Owned workspace pipe response timed out'}
  $utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
 } finally {$client.Dispose()}
}
$pipeChecks=@()
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-title';if($phase -eq 1){$flag='--verify-script-title-reopen'}
 $arguments=@('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"'))
 $process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(90);$captured=@{};$pipeCompleted=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json'
  if(Test-Path -LiteralPath $requestPath){
   $request=$null
   try {$request=Read-CaptureRequest $requestPath} catch [IO.IOException] {}
   if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
    if($request.stage -eq '.pipe' -and -not $pipeCompleted.ContainsKey($request.token)){
     $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
     if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned pipe identity mismatch'}
     $status=Invoke-OwnedPipe $connection.commandPipe 'app-script-status' @{}
     if(-not $status.ok -or -not $status.data.hasProject -or $status.data.canAdvance){throw 'Unexpected script stage status'}
     $changed=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-title' @{projectId=$status.data.projectId;revision=$status.data.revision;title='AIの題名案'}
     if(-not $changed.ok -or $changed.data.title -ne 'AIの題名案'){throw 'Pipe title update failed'}
     $stale=Invoke-OwnedPipe $connection.commandPipe 'app-script-set-title' @{projectId=$status.data.projectId;revision=$status.data.revision;title='古い応答'}
     if($stale.ok){throw 'Stale pipe revision was accepted'}
     $saved=Invoke-OwnedPipe $connection.commandPipe 'app-script-save' @{projectId=$changed.data.projectId;revision=$changed.data.revision}
     if(-not $saved.ok -or $saved.data.modified -or $saved.data.wizard.titleStatus -ne 'in-progress'){throw 'Pipe save or human confirmation boundary failed'}
     $page=Invoke-OwnedPipe $connection.commandPipe 'app-status' @{}
     if(-not $page.ok -or $page.data.page -ne 'create' -or $page.data.openDocuments -ne 0){throw 'Pipe escaped title stage'}
     $pipeChecks+=@('actual named pipe reads current title stage','pipe updates shared GUI title','stale revision rejected','pipe saves without human confirmation','title page and zero movie sessions preserved')
     $pipeCompleted[$request.token]=$true
    }
    & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
    try {$request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8 -ErrorAction Stop} catch [IO.IOException] {Start-Sleep -Milliseconds 25;continue}
    $captured[$request.token]=$true
   }
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned stage check still running; retain PID/root: '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 50
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding UTF8 -ErrorAction SilentlyContinue;throw 'Owned stage verification failed'}
 $expected=3;if($phase -eq 1){$expected=1}
 if($captured.Count -ne $expected){throw 'Owned stage captures missing'}
}
$first=Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
$second=Get-Content ($result+'.reopened.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($first.checks.Count -lt 20 -or $second.checks.Count -lt 3 -or $pipeChecks.Count -ne 5){throw 'Stage checks incomplete'}
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$pipeChecks;captures=4;result=$result;method='owned native GUI controls, actual workspace named pipe, fresh process restart'} | ConvertTo-Json -Depth 6 | Tee-Object -FilePath ($result+'.metadata.json')
