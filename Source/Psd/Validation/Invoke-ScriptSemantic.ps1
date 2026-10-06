param([Parameter(Mandatory)][string]$ExecutablePath,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$FixtureProject,[Parameter(Mandatory)][string]$FixtureDataRoot)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$fixture=Get-Content -LiteralPath $FixtureProject -Raw -Encoding utf8 | ConvertFrom-Json
if($fixture.title -ne 'Codex実往復用：架空の星空観測所' -or $fixture.scriptWizard.stage -ne 'review'){throw 'Explicit Codex fictional review fixture required'}
$root=Join-Path $env:TEMP ('RIGMMaker-ScriptSemantic-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'RIGM') -Force | Out-Null
@{owner='RIGMMaker.ScriptSemantic.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding utf8
$hashes=@{};$sourceHash=(Get-FileHash $FixtureProject).Hash
foreach($c in $fixture.scriptWizard.selectedCharacters){
 if($c.path -notin @('RIGM\casting-guide.rigm','RIGM\casting-question.rigm')){throw 'Owned fictional character identity mismatch'}
 $source=Join-Path $FixtureDataRoot $c.path;$hashes[$source]=(Get-FileHash $source).Hash;Copy-Item -LiteralPath $source -Destination (Join-Path $root $c.path)
}
$relative='Projects\'+$fixture.projectId+'\project.rigmovie';$target=Join-Path $root $relative
New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null;Copy-Item -LiteralPath $FixtureProject -Destination $target
$relative | Set-Content (Join-Path $root 'fixture-project.txt') -Encoding utf8
$output=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $output -Force | Out-Null
$root | Set-Content (Join-Path $output 'owned-root.txt') -Encoding utf8
$exe=[IO.Path]::GetFullPath($ExecutablePath);$result=Join-Path $output 'script-semantic.json';$utf8=[Text.UTF8Encoding]::new($false)
$records=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[string]]::new()
function Invoke-Pipe([string]$name,[string]$command,[hashtable]$arguments){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{
  $client.Connect(3000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
  $packet=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$command;args=$arguments};$bytes=$utf8.GetBytes(($packet | ConvertTo-Json -Depth 12 -Compress))
  if($bytes.Length -gt 60000){throw 'Pipe request too large'};$client.Write($bytes,0,$bytes.Length);$client.Flush()
  $buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length);if(-not $read.Wait(6000)){throw 'Owned pipe timeout'}
  $response=$utf8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
  $records.Add(@{time=[DateTime]::UtcNow.ToString('o');request=$packet;response=$response});return $response
 }finally{$client.Dispose()}
}
function Require-Ok($r){if(-not $r.ok){throw ('Pipe failed '+($r | ConvertTo-Json -Depth 8 -Compress))};return $r.data}
function Read-Rows($pipe,$command,$common){$rows=@();$offset=0;do{$part=Require-Ok (Invoke-Pipe $pipe $command ($common+@{offset=$offset}));$rows+=@($part.rows);$offset=$part.nextOffset}while($part.hasMore);return ,$rows}
function Read-SharedJson($path){
 $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try{$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true);try{$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}}finally{$stream.Dispose()}
}
$expected=@{
 '架空の星空観測所へようこそ。今日は夜空を描く準備をします。'=@{path='RIGM\casting-guide.rigm';reason='観測所への歓迎と今回の制作内容を説明する導入なので案内役を提案。'}
 '星を見る前に、明かりを消してもいいですか。'=@{path='RIGM\casting-question.rigm';reason='観測前の行動について許可を尋ねるセリフなので質問役を提案。'}
 'はい。足元を確認してから、小さなランプを消しましょう。'=@{path='RIGM\casting-guide.rigm';reason='直前の質問に答え、安全な手順を案内する応答なので案内役を提案。'}
 '空の色は何色に塗ればいいですか。'=@{path='RIGM\casting-question.rigm';reason='描画に使う色を尋ねるセリフなので質問役を提案。'}
 'この架空の絵では、濃い青から紫へゆっくり変わる空を描きましょう。'=@{path='RIGM\casting-guide.rigm';reason='色の質問へ具体的な描画方針を説明しているため案内役を提案。'}
 '描けた星空を、最後に一緒に眺めましょう。'=@{path='RIGM\casting-guide.rigm';reason='制作の締めくくりへ参加者を案内するセリフなので案内役を提案。'}
}
$reviewPacket=$null;$castPacket=$null
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-script-semantic';if($phase -eq 1){$flag='--verify-script-semantic-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$captured=@{}
 while(-not $process.HasExited){
  $request=$null;$requestPath=$result+'.capture-request.json'
  if(Test-Path $requestPath){try{$request=Read-SharedJson $requestPath}catch [IO.IOException]{}}
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   $connection=Get-Content (Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')) -Raw -Encoding utf8 | ConvertFrom-Json
   if($connection.pid -ne $process.Id -or $connection.dataRoot -ne $root){throw 'Owned pipe connection identity mismatch'}
   $pipe=$connection.commandPipe;$status=Require-Ok (Invoke-Pipe $pipe 'app-script-status' @{});$common=@{projectId=$status.projectId;revision=$status.revision}
   switch($request.stage){
    '.review-proposal' {
     $texts=@{};foreach($section in @('opening','body','closing')){$texts[$section]=(Require-Ok (Invoke-Pipe $pipe 'app-script-text' ($common+@{section=$section}))).text}
     $review=Require-Ok (Invoke-Pipe $pipe 'app-script-review' $common)
     if($texts.body.Substring(7,2) -ne '明り' -or $review.state -ne 'requested'){throw 'Fresh original review anchor differs'}
     # 本文を読んだ親AIの提案。表記の任意提案であり、アプリ内の疑似AI生成ではない。
     $reviewPacket=$common+@{requestId=$review.requestId;fingerprint=$review.fingerprint;items=@(@{id='semantic-akari';section='body';offset=7;original='明り';proposed='明かり';reason='一般的な送り仮名「明かり」に統一する表記上の提案。原文も意味は通じるため任意採用。'});complete=$true}
     $accepted=Require-Ok (Invoke-Pipe $pipe 'app-script-submit-review' $reviewPacket)
     $pending=Require-Ok (Invoke-Pipe $pipe 'app-script-review' @{projectId=$accepted.projectId;revision=$accepted.revision})
     if($pending.items.Count -ne 1 -or $pending.items[0].decision -ne 'pending'){throw 'Semantic review proposal not pending'}
     $checks.Add('parent AI content proposal delivered with fresh request fingerprint and UTF16 anchor')
    }
    '.review-adopted' {
     $review=Require-Ok (Invoke-Pipe $pipe 'app-script-review' $common);$body=Require-Ok (Invoke-Pipe $pipe 'app-script-text' ($common+@{section='body'}))
     if($review.items[0].decision -ne 'ai' -or $body.text.Substring(7,3) -ne '明かり'){throw 'GUI adoption not visible through real pipe'}
     if((Invoke-Pipe $pipe 'app-script-submit-review' $reviewPacket).ok){throw 'Obsolete semantic review overwrote accepted correction'}
     $checks.Add('GUI spelling adoption read back and old AI result rejected')
    }
    '.casting-proposal' {
     $cast=Require-Ok (Invoke-Pipe $pipe 'app-script-casting' $common);$rows=Read-Rows $pipe 'app-script-casting' $common
     if($rows.Count -ne 6 -or $cast.state -ne 'requested'){throw 'Fresh semantic casting differs'}
     $proposals=@();$seen=@{}
     foreach($row in $rows){
      if(-not $expected.ContainsKey($row.text) -or $seen.ContainsKey($row.text)){throw 'Unreviewed or duplicate utterance'};$seen[$row.text]=$true;$choice=$expected[$row.text]
      $roles=@($cast.roles | Where-Object {$_.active -and $_.path -eq $choice.path});if($roles.Count -ne 1){throw 'Actual character path unresolved'}
      $source=Require-Ok (Invoke-Pipe $pipe 'app-script-text' ($common+@{section=$row.section}));if($source.text.Substring($row.offset,$row.length) -ne $row.text){throw 'Cue source anchor differs'}
      $proposals+=@{cueId=$row.cueId;role=$roles[0].number;reason=$choice.reason}
     }
     $castPacket=$common+@{requestId=$cast.requestId;fingerprint=$cast.fingerprint;items=$proposals;complete=$true}
     $accepted=Require-Ok (Invoke-Pipe $pipe 'app-script-submit-casting' $castPacket)
     $pending=Read-Rows $pipe 'app-script-casting' @{projectId=$accepted.projectId;revision=$accepted.revision}
     foreach($row in $pending){if($row.origin -ne 'ai' -or $row.confirmed){throw 'Pipe silently confirmed semantic casting'}}
     $checks.Add('six content-based roles resolve actual paths cueIds and source anchors and remain unconfirmed')
    }
    '.casting-adopted' {
     $cast=Require-Ok (Invoke-Pipe $pipe 'app-script-casting' $common);$rows=Read-Rows $pipe 'app-script-casting' $common
     foreach($row in $rows){
      if(-not $row.confirmed -or $row.origin -ne 'ai'){throw 'GUI Enter acceptance missing'}
      $roles=@($cast.roles | Where-Object {$_.active -and $_.number -eq $row.role})
      if($roles.Count -ne 1 -or $roles[0].path -ne $expected[$row.text].path){throw 'GUI acceptance changed semantic role mapping'}
     }
     if((Invoke-Pipe $pipe 'app-script-submit-casting' $castPacket).ok){throw 'Old semantic casting overwritten GUI decisions'}
     $checks.Add('six GUI Enter acceptances read back and old casting result rejected')
    }
    {$_ -in '.subtitles','.reopened'} {
     $rows=Read-Rows $pipe 'app-script-subtitles' $common
     if($status.wizard.stage -ne 'subtitles' -or $rows.Count -ne 6){throw 'Saved subtitle handoff missing'}
     foreach($row in $rows){
      if($row.subtitle -ne $row.voiceText -or -not $expected.ContainsKey($row.voiceText)){throw 'Subtitle voice boundary differs'}
      $roles=@($status.wizard.casting.roles | Where-Object {$_.active -and $_.number -eq $row.role})
      if($roles.Count -ne 1 -or $roles[0].path -ne $expected[$row.voiceText].path){throw 'Saved subtitle semantic role differs'}
     }
     $checks.Add('six accepted semantic speeches and independent subtitles read at '+$request.stage)
    }
    default {throw ('Unknown owned capture '+$request.stage)}
   }
   $records | ConvertTo-Json -Depth 20 | Set-Content ($result+'.pipe-transcript.json') -Encoding utf8
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
   $request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding utf8;$captured[$request.token]=$true
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation remains active preserve PID/root '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 40
 }
 $process.WaitForExit();if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding utf8 -ErrorAction SilentlyContinue;throw 'Semantic GUI validation failed'}
}
if((Get-FileHash $FixtureProject).Hash -ne $sourceHash){throw 'Original fictional source changed'}
foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Original registered copy changed'}}
$records | ConvertTo-Json -Depth 20 | Set-Content ($result+'.pipe-transcript.json') -Encoding utf8
$first=Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json;$second=Get-Content ($result+'.reopened.json') -Raw -Encoding utf8 | ConvertFrom-Json
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;sourceHash=$sourceHash;source=$FixtureProject;originalCharacterHashes=$hashes;guiChecks=$first.checks.Count;restartChecks=$second.checks.Count;pipeChecks=$checks;semanticSource='parent AI read the Codex fictional text and supplied optional spelling and conversational-role proposals; no application dummy AI';acceptance='explicitly authorized GUI adoption only in copied fictional fixture'} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath ($result+'.metadata.json')
