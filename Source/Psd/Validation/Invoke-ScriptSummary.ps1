#requires -Version 7.0
param([Parameter(Mandatory)][string]$ExecutablePath,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$FixtureDataRoot)
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8
$relative=(Get-Content (Join-Path $FixtureDataRoot 'fixture-project.txt') -Raw -Encoding utf8).Trim();$source=Join-Path $FixtureDataRoot $relative;$fixture=Get-Content $source -Raw -Encoding utf8 | ConvertFrom-Json
if($fixture.title -ne 'Codex実往復用：架空の星空観測所' -or $fixture.scriptWizard.stage -ne 'summary'){throw 'Owned completed scene fiction required'}
$sourceHash=(Get-FileHash $source).Hash;$hashes=@{};$root=Join-Path $env:TEMP ('RIGMMaker-ScriptSummary-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptSummary.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
foreach($character in $fixture.scriptWizard.selectedCharacters){if($character.path -notin @('RIGM\casting-guide.rigm','RIGM\casting-question.rigm')){throw 'Owned character required'};$original=Join-Path $FixtureDataRoot $character.path;$hashes[$original]=(Get-FileHash $original).Hash;Copy-Item -LiteralPath $original -Destination (Join-Path $root $character.path)}
$target=Join-Path $root $relative;New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null;Get-ChildItem -LiteralPath (Split-Path $source) -Force | Copy-Item -Destination (Split-Path $target) -Recurse;$relative | Set-Content (Join-Path $root 'fixture-project.txt') -Encoding utf8
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null;$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-summary.json';$utf8=[Text.UTF8Encoding]::new($false);$checks=[Collections.Generic.List[string]]::new();$records=[Collections.Generic.List[object]]::new()
function Invoke-Pipe([string]$name,[string]$command,[hashtable]$arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{$client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message;$packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$command;args=$arguments};$bytes=$utf8.GetBytes(($packet | ConvertTo-Json -Depth 12 -Compress));if($bytes.Length -gt 60000){throw 'Pipe packet too large'};$client.Write($bytes,0,$bytes.Length);$client.Flush();$buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length);if(-not $read.Wait(6000)){throw 'Owned pipe timeout'};$reply=$utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json;$records.Add(@{command=$command;args=$arguments;response=$reply});return $reply
 }finally{$client.Dispose()}
}
function Require-Ok($r){if(-not $r.ok){throw ('Pipe failed '+($r | ConvertTo-Json -Depth 8 -Compress))};return $r.data}
function Current($pipe){$s=Require-Ok (Invoke-Pipe $pipe 'app-script-status' @{});return @{projectId=$s.projectId;revision=$s.revision}}
function Read-Capture([string]$path){$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8);try{$content=$reader.ReadToEnd()}finally{$reader.Dispose()};return ($content | ConvertFrom-Json)}
$version=Invoke-RestMethod 'http://127.0.0.1:50022/version' -TimeoutSec 5;if($version -ne '0.25.2'){throw 'Expected existing engine differs'}
for($phase=0;$phase -lt 3;$phase++){
 $flag='--verify-script-summary';if($phase -gt 0){$flag='--verify-script-summary-reopen'};$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(150);$captured=@{}
 while(-not $process.HasExited){
  $request=$null;if(Test-Path ($result+'.capture-request.json')){try{$request=Read-Capture ($result+'.capture-request.json')}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json;if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned connection differs'};$pipe=$connection.commandPipe;$common=Current $pipe;$summary=Require-Ok (Invoke-Pipe $pipe 'app-script-summary' $common)
   if($request.stage -eq '.editing'){
    foreach($command in @('app-script-set-summary','app-script-complete-summary','app-script-next','app-script-new')){if((Invoke-Pipe $pipe $command ($common+@{draft=$summary.data.draft})).ok){throw 'Human edit lock bypassed'};$checks.Add('human summary lock rejects '+$command)}
   }elseif($request.stage -eq '.pipe'){
    $before=$summary | ConvertTo-Json -Depth 12 -Compress
    foreach($change in @(@{revision=($common.revision-1)},@{projectId='wrong'},@{text=('あ'*2001)},@{text=('A'+[char]1)},@{role=10},@{role=1.5},@{minimum=0},@{kind='fake'})){
     $draft=$summary.data.draft | ConvertTo-Json -Depth 8 | ConvertFrom-Json;$a=$common+@{draft=$draft};foreach($key in $change.Keys){if($key -in @('revision','projectId')){$a[$key]=$change[$key]}else{$draft.$key=$change[$key]}}
     if((Invoke-Pipe $pipe 'app-script-set-summary' $a).ok){throw 'Invalid summary accepted'};$after=Require-Ok (Invoke-Pipe $pipe 'app-script-summary' $common);if(($after | ConvertTo-Json -Depth 12 -Compress) -ne $before){throw 'Invalid summary changed state'};$checks.Add('invalid summary atomically rejects '+(@($change.Keys)[0]))
    }
    $draft=@{text=('あ'*2000);subtitle=('あ'*3000);reading=('あ'*2000);role=1;kind='radar';title='確認用の人間入力値';minimum='0';maximum='5';items=@(@{label='確認A';value='2'},@{label='確認B';value='3'},@{label='確認C';value='4'})}
    Require-Ok (Invoke-Pipe $pipe 'app-script-set-summary' ($common+@{draft=$draft})) | Out-Null;$read=Require-Ok (Invoke-Pipe $pipe 'app-script-summary' (Current $pipe));if($read.data.draft.text.Length -ne 2000 -or $read.data.draft.subtitle.Length -ne 3000 -or $read.data.draft.reading.Length -ne 2000){throw 'Maximum human text truncated'};$checks.Add('maximum Japanese summary text subtitle reading roundtrip stays bounded')
    $common=Current $pipe;$draft.text='架空の確認作品だけの総評です。';$draft.subtitle='字幕は独立した確認表示';$draft.reading='かくうのかくにんさくひんだけのそうひょうです。';Require-Ok (Invoke-Pipe $pipe 'app-script-set-summary' ($common+@{draft=$draft})) | Out-Null;$checks.Add('real pipe applies explicitly fictional human input')
    if((Invoke-Pipe $pipe 'app-script-set-summary' ($common+@{draft=$summary.data.draft})).ok){throw 'Old draft overwrote newer human input'};$checks.Add('stale revision cannot overwrite accepted human draft')
   }elseif($request.stage -eq '.saved'){
    if($null -ne $summary.data.appliedDraft -or $null -ne $summary.data.archivedCue -or $null -ne $summary.data.archivedScene -or $null -ne $summary.cue.text){throw 'Pipe duplicated long archived human text'};$checks.Add('materialized and archived summary read omits duplicate long source fields')
   }elseif($request.stage -notin @('.chart','.voice','.saved','.reopened')){throw 'Unknown summary capture'}
   $records | ConvertTo-Json -Depth 18 | Set-Content ($result+'.pipe-transcript.json') -Encoding utf8
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png');$request.token | Set-Content ($result+'.capture-ack.txt') -Encoding utf8;$captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation active preserve PID/root '+$process.Id+' '+$root)};Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit();if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Summary validation failed'}
 if($phase -gt 0){Copy-Item -LiteralPath ($result+'.closing.json') -Destination ($result+'.phase'+$phase+'.json')}
}
if((Get-FileHash $source).Hash -ne $sourceHash){throw 'Original scene fiction changed'};foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Original character changed'}}
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$middle=Get-Content ($result+'.phase1.json') -Raw -Encoding utf8 | ConvertFrom-Json;$last=Get-Content ($result+'.phase2.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;guiChecks=$first.checks.Count;voiceRestartChecks=$middle.checks.Count;closingRestartChecks=$last.checks.Count;pipeChecks=$checks;engineVersion=$version;fixtureSource=$source;sourceHash=$sourceHash;originalCharacterHashes=$hashes;noVideoEncoding=$true} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
