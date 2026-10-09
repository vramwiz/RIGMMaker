#requires -Version 7.0
param([Parameter(Mandatory)][string]$ExecutablePath,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$FixtureDataRoot)
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8
$relative=(Get-Content (Join-Path $FixtureDataRoot 'fixture-project.txt') -Raw -Encoding utf8).Trim();$source=Join-Path $FixtureDataRoot $relative;$fixture=Get-Content $source -Raw -Encoding utf8 | ConvertFrom-Json
if($fixture.title -ne 'Codex実往復用：架空の星空観測所' -or $fixture.scriptWizard.stage -ne 'closing'){throw 'Owned completed scene fiction required'}
$sourceHash=(Get-FileHash $source).Hash;$hashes=@{};$root=Join-Path $env:TEMP ('RIGMMaker-ScriptClosing-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptClosing.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
foreach($character in $fixture.scriptWizard.selectedCharacters){if($character.path -notin @('RIGM\casting-guide.rigm','RIGM\casting-question.rigm')){throw 'Owned character required'};$original=Join-Path $FixtureDataRoot $character.path;$hashes[$original]=(Get-FileHash $original).Hash;Copy-Item -LiteralPath $original -Destination (Join-Path $root $character.path)}
$target=Join-Path $root $relative;New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null;Get-ChildItem -LiteralPath (Split-Path $source) -Force | Copy-Item -Destination (Split-Path $target) -Recurse;$relative | Set-Content (Join-Path $root 'fixture-project.txt') -Encoding utf8
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null;$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-closing.json';$utf8=[Text.UTF8Encoding]::new($false);$checks=[Collections.Generic.List[string]]::new();$records=[Collections.Generic.List[object]]::new()
function Invoke-Pipe([string]$name,[string]$command,[hashtable]$arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{$client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message;$packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$command;args=$arguments};$bytes=$utf8.GetBytes(($packet | ConvertTo-Json -Depth 12 -Compress));if($bytes.Length -gt 60000){throw 'Pipe packet too large'};$client.Write($bytes,0,$bytes.Length);$client.Flush();$buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length);if(-not $read.Wait(6000)){throw 'Owned pipe timeout'};$reply=$utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json;$records.Add(@{command=$command;args=$arguments;response=$reply});return $reply
 }finally{$client.Dispose()}
}
function Require-Ok($r){if(-not $r.ok){throw ('Pipe failed '+($r | ConvertTo-Json -Depth 8 -Compress))};return $r.data}
function Current($pipe){$s=Require-Ok (Invoke-Pipe $pipe 'app-script-status' @{});return @{projectId=$s.projectId;revision=$s.revision}}
function Read-Capture([string]$path){$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8);try{$content=$reader.ReadToEnd()}finally{$reader.Dispose()};return ($content | ConvertFrom-Json)}
for($phase=0;$phase -lt 3;$phase++){
 $flag='--verify-script-closing';if($phase -gt 0){$flag='--verify-script-closing-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$captured=@{}
 while(-not $process.HasExited){
  $request=$null;if(Test-Path ($result+'.capture-request.json')){try{$request=Read-Capture ($result+'.capture-request.json')}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json
   if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection differs'};$pipe=$connection.commandPipe
   if($request.stage -in @('.editing','.pipe','.adopt')){
    $common=Current $pipe;$closing=Require-Ok (Invoke-Pipe $pipe 'app-script-closing' $common)
    if($request.stage -eq '.editing'){
     $status=Require-Ok (Invoke-Pipe $pipe 'app-script-status' @{})
     if($status.textEditing){throw 'Closing input unexpectedly locked communication'}
     $stale=@{projectId=$common.projectId;revision=($common.revision-1)}
     if((Invoke-Pipe $pipe 'app-script-set-closing' $stale).ok){throw 'Stale closing revision accepted'}
     $checks.Add('closing input is unlocked and stale revision is rejected')
    }elseif($request.stage -eq '.pipe'){
     $before=$closing | ConvertTo-Json -Depth 12 -Compress
     foreach($change in @(@{revision=($common.revision-1)},@{projectId='wrong'},@{title=('あ'*129)},@{endChoice='fake'},@{endSeconds=1})){
      $draft=$closing.closing.draft | ConvertTo-Json -Depth 10 | ConvertFrom-Json;$a=$common+@{draft=$draft}
      foreach($key in $change.Keys){if($key -in @('revision','projectId')){$a[$key]=$change[$key]}else{$draft.$key=$change[$key]}}
      if((Invoke-Pipe $pipe 'app-script-set-closing' $a).ok){throw 'Invalid ending accepted'};$after=Require-Ok (Invoke-Pipe $pipe 'app-script-closing' $common);if(($after | ConvertTo-Json -Depth 12 -Compress) -ne $before){throw 'Invalid ending changed state'};$checks.Add('invalid closing atomically rejects '+(@($change.Keys)[0]))
     }
     if((Invoke-Pipe $pipe 'app-script-adopt-closing-image' ($common+@{kind='endImage';path='missing.png'})).ok){throw 'Missing image adopted'};$checks.Add('missing image cannot fabricate adoption')
     $image=$fixture.scenes[0].image
     foreach($kind in @('representative','endImage','thumbnailImage')){Require-Ok (Invoke-Pipe $pipe 'app-script-adopt-closing-image' ((Current $pipe)+@{kind=$kind;path=((Split-Path $relative)+'\'+$image)})) | Out-Null}
     $closing=Require-Ok (Invoke-Pipe $pipe 'app-script-closing' (Current $pipe));$valid=$closing.closing.draft | ConvertTo-Json -Depth 10 | ConvertFrom-Json;$valid.endSeconds='5';$valid.thumbnailSeconds='2';$valid.title='採用した既存画像：架空の確認作品'
     foreach($case in @('incomplete','outside','overlap')){
      $draft=$valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
      if($case -eq 'incomplete'){$draft.endSeconds='-'}elseif($case -eq 'outside'){$draft.rect.x='1.1'}else{$draft.rect.x=$draft.reserved[0].x;$draft.rect.y=$draft.reserved[0].y}
      Require-Ok (Invoke-Pipe $pipe 'app-script-set-closing' ((Current $pipe)+@{draft=$draft})) | Out-Null
      $common=Current $pipe;$before=Require-Ok (Invoke-Pipe $pipe 'app-script-closing' $common);if((Invoke-Pipe $pipe 'app-script-complete-closing' $common).ok){throw 'Invalid geometry confirmed'};$after=Require-Ok (Invoke-Pipe $pipe 'app-script-closing' $common)
      if(($before | ConvertTo-Json -Depth 12 -Compress) -ne ($after | ConvertTo-Json -Depth 12 -Compress)){throw 'Failed completion changed accepted draft'};$checks.Add('confirmation rejects '+$case+' and retains raw human draft')
     }
     $old=Current $pipe;Require-Ok (Invoke-Pipe $pipe 'app-script-set-closing' ($old+@{draft=$valid})) | Out-Null
     if((Invoke-Pipe $pipe 'app-script-set-closing' ($old+@{draft=$closing.closing.draft})).ok){throw 'Old draft overwrote accepted newer draft'};$checks.Add('stale human/AI result cannot overwrite newer closing input')
    }
   }
   $records | ConvertTo-Json -Depth 18 | Set-Content ($result+'.pipe-transcript.json') -Encoding utf8
   $windowClass='TRigmWizardMainForm';if($request.stage -eq '.dialog'){$windowClass='TRigmMovieEndingDialog'}
   & (Join-Path $PSScriptRoot 'Capture-ClosingWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png') -WindowClass $windowClass
   $request.token | Set-Content ($result+'.capture-ack.txt') -Encoding utf8;$captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation active preserve PID/root '+$process.Id+' '+$root)};Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit();if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Closing validation failed'}
 $report=$result+'.phasereopen.json';if($phase -eq 0){$report=$result+'.phaseinitial.json'};Copy-Item -LiteralPath $report -Destination ($result+'.phase'+$phase+'.json')
}
if((Get-FileHash $source).Hash -ne $sourceHash){throw 'Original summary fiction changed'};foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Original character changed'}}
$guiChecks=0;for($phase=0;$phase -lt 3;$phase++){$guiChecks+=(Get-Content ($result+'.phase'+$phase+'.json') -Raw -Encoding utf8 | ConvertFrom-Json).checks.Count}
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$guiChecks;pipeChecks=$checks;fixtureSource=$source;sourceHash=$sourceHash;originalCharacterHashes=$hashes;noVideoEncoding=$true} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
