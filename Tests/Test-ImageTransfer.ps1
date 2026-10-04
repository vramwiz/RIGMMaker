#requires -Version 7.0
param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$RunDirectory,
  [Parameter(Mandatory)][string]$SourcePng,[switch]$Full)
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$sender=Join-Path $repository '制作支援\パイプ\Send-RigmCommand.ps1'
$imageSender=Join-Path $repository '制作支援\パイプ\Send-RigmImage.ps1'
if(Test-Path -LiteralPath $RunDirectory){throw 'Use a new owned validation directory'}
New-Item -ItemType Directory -Path $RunDirectory | Out-Null
$pipes=Join-Path $RunDirectory 'Pipes';$settings=Join-Path $RunDirectory 'Settings'
New-Item -ItemType Directory -Path $pipes,$settings | Out-Null
$checks=[Collections.Generic.List[string]]::new();$latencies=[Collections.Generic.List[double]]::new()
$record=@{owned=$true;runDirectory=$RunDirectory;executable=$Executable;executableSha256=(Get-FileHash -LiteralPath $Executable).Hash;source=$SourcePng;sourceSha256=(Get-FileHash -LiteralPath $SourcePng).Hash;humanDesktopVerification=$false;remoteGenerationDeliveryVerified=$false;checks=$checks}
$runFile=Join-Path $RunDirectory 'run.json';$connection='';$process=$null
function Persist{$record|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $runFile -Encoding utf8BOM}
function Check([bool]$Value,[string]$Name){if(-not $Value){throw $Name};$checks.Add($Name);Write-Output ('PASS '+$Name)}
function Call([string]$Command,[hashtable]$Arguments=@{}){
  $timer=[Diagnostics.Stopwatch]::StartNew()
  $reply=& $sender -ConnectionFile $connection -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Depth 20 -Compress) -TimeoutMs 10000 | ConvertFrom-Json -AsHashtable
  $latencies.Add($timer.Elapsed.TotalMilliseconds)
  return $reply.data
}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{$null=& $Action}catch{$rejected=$true};Check $rejected $Name}
function StartTransfer([byte[]]$Bytes,[string]$Digest=''){
  if(-not $Digest){$Digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()}
  Call 'movie-image-transfer-begin' @{sceneId=$script:scene;byteCount=$Bytes.Length;sha256=$Digest;mimeType='image/png'}
}
function Chunk([string]$Id,[byte[]]$Bytes,[int]$Offset){
  $length=[Math]::Min(16384,$Bytes.Length-$Offset)
  Call 'movie-image-transfer-chunk' @{transferId=$Id;offset=$Offset;data=[Convert]::ToBase64String($Bytes,$Offset,$length)}
}
function Upload([string]$Id,[byte[]]$Bytes){for($offset=0;$offset -lt $Bytes.Length;$offset+=16384){$null=Chunk $Id $Bytes $offset};$null=Call 'movie-image-transfer-finish' @{transferId=$Id};WaitTransfer $Id}
function WaitTransfer([string]$Id){
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  do{$status=Call 'movie-image-transfer-status' @{transferId=$Id};if($status.state -notin @('receiving','validating') -and $status.workerExited){return $status};Start-Sleep -Milliseconds 30}while([DateTime]::UtcNow -lt $deadline)
  throw 'Transfer worker did not finish in 15 seconds'
}
try{
  $process=Start-Process -FilePath $Executable -ArgumentList @(('"--pipe-dir='+$pipes+'"'),('"--settings-dir='+$settings+'"'),('"--data-dir='+(Join-Path $RunDirectory 'Library')+'"')) -WindowStyle Hidden -PassThru
  $record.pid=$process.Id;Persist
  $deadline=[DateTime]::UtcNow.AddSeconds(20)
  do{$file=Get-ChildItem -LiteralPath $pipes -File -Filter ('RIGMMaker.'+$process.Id+'.*.json') | Select-Object -First 1;if($file){$connection=$file.FullName;break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
  if(-not $connection){throw 'Owned app did not publish its common pipe'}
  $record.connection=$connection;Persist
  $schema=Call 'movie-schema';Check ($schema.commands.ContainsKey('image-transfer-begin') -and $schema.commands.ContainsKey('image-transfer-adopt')) 'common movie schema exposes image transfer'
  $null=Call 'movie-import-script' @{text=('# PNG byte transfer fixture'+[Environment]::NewLine+'narrator: local named pipe image adoption verification')}
  $null=Call 'movie-composition-enable'
  $project=Call 'movie-project';$script:scene=$project.scenes[0].id
  $movie=Join-Path $RunDirectory 'transfer-fixture.rigmovie';$null=Call 'movie-save' @{path=$movie};$record.movie=$movie;Persist
  $before=Call 'movie-status';$movieHash=(Get-FileHash -LiteralPath $movie).Hash
  $bytes=[IO.File]::ReadAllBytes($SourcePng);Check ($bytes.Length -gt 60000) 'source PNG exceeds one pipe envelope'
  $t=StartTransfer $bytes;$id=$t.transferId;$record.transferId=$id;Persist
  Reject 'cannot adopt before verification' {Call 'movie-image-transfer-adopt' @{transferId=$id}}
  Reject 'finish rejects missing bytes' {Call 'movie-image-transfer-finish' @{transferId=$id}}
  Reject 'out of order chunk rejected' {Chunk $id $bytes 16384}
  Reject 'fractional offset rejected' {Call 'movie-image-transfer-chunk' @{transferId=$id;offset=0.5;data=[Convert]::ToBase64String($bytes,0,16384)}}
  Reject 'invalid base64 rejected' {Call 'movie-image-transfer-chunk' @{transferId=$id;offset=0;data='!!!='}}
  $a=Chunk $id $bytes 0;$b=Chunk $id $bytes 0
  Check ($a.nextOffset -eq 16384 -and $b.nextOffset -eq 16384) 'identical chunk retry is idempotent'
  $different=[byte[]]$bytes.Clone();$different[0]=$different[0] -bxor 1
  Reject 'different bytes at accepted offset rejected' {Chunk $id $different 0}
  $stateFile=Join-Path $RunDirectory 'sender-state.json'
  $ready=& $imageSender -ConnectionFile $connection -Path $SourcePng -SceneId $scene -TransferId $id -StateFile $stateFile -NoAdopt | ConvertFrom-Json -AsHashtable
  Check ($ready.state -eq 'ready' -and $ready.nextOffset -eq $bytes.Length) 'sender resumes from accepted offset and validates all bytes'
  Check ($ready.receivedBytes -eq $bytes.Length -and $ready.width -gt 0 -and $ready.height -gt 0) 'worker writes complete PNG and decodes dimensions'
  Check ((Get-FileHash -LiteralPath $ready.path).Hash -eq $record.sourceSha256) 'received asset is byte identical to source'
  Reject 'ready verified asset cannot change before adoption' {[IO.File]::WriteAllBytes($ready.path,[byte[]](1,2,3))}
  Check ([IO.Path]::GetFullPath($ready.path).StartsWith((Join-Path $RunDirectory 'transfer-fixture.assets\ReceivedImages\'),[StringComparison]::OrdinalIgnoreCase)) 'asset stored beside current saved project'
  $current=Call 'movie-status';$project=Call 'movie-project'
  Check (-not $current.modified -and $current.revision -eq $before.revision -and -not $project.scenes[0].image) 'ready image alone does not edit scene or revision'
  Check ((Get-FileHash -LiteralPath $movie).Hash -eq $movieHash) 'transfer never autosaves project'
  $lease=Call 'movie-edit-begin'
  Reject 'image begin respects current edit lease' {StartTransfer $bytes}
  Reject 'image adoption respects current edit lease' {Call 'movie-image-transfer-adopt' @{transferId=$id}}
  $null=Call 'movie-edit-end' @{editToken=$lease.editToken}
  $current=Call 'movie-status';$before.revision=$current.revision
  Reject 'stale revision cannot adopt' {Call 'movie-image-transfer-adopt' @{transferId=$id;revision=($current.revision-1)}}
  $adopted=Call 'movie-image-transfer-adopt' @{transferId=$id}
  $project=Call 'movie-project';$current=Call 'movie-status'
  Check ($adopted.adopted -and $current.modified -and $current.revision -eq $before.revision+1 -and $project.scenes[0].image -eq $ready.path) 'verified asset adoption atomically edits scene and marks unsaved'
  Check ((Get-FileHash -LiteralPath $movie).Hash -eq $movieHash) 'adoption does not autosave project'
  Reject 'completed transfer cannot be adopted twice' {Call 'movie-image-transfer-adopt' @{transferId=$id}}
  $null=Call 'movie-undo';$project=Call 'movie-project';Check (-not $project.scenes[0].image) 'undo restores prior scene image'
  $null=Call 'movie-redo';$project=Call 'movie-project';Check ($project.scenes[0].image -eq $ready.path) 'redo restores adopted image'
  $null=Call 'movie-save';$null=Call 'movie-open' @{path=$movie};$project=Call 'movie-project';$current=Call 'movie-status'
  $savedSceneImage=$project.scenes[0].image;$savedAsset=Join-Path $RunDirectory $savedSceneImage
  Check (-not $current.modified -and $project.scenes[0].id -eq $scene -and (Get-FileHash -LiteralPath $savedAsset).Hash -eq $record.sourceSha256) 'explicit save and reopen preserve adopted bytes and scene'
  $null=Call 'movie-open-ui';$null=Call 'movie-seek' @{time=0}
  $capture=& (Join-Path $PSScriptRoot 'Capture-OwnedProduct.ps1') -RunFile $runFile -Name 'adopted-image-ui' | ConvertFrom-Json -AsHashtable
  Check ($capture.windowPid -eq $process.Id -and $capture.visible) 'native GUI capture belongs to owned test app'
  $record.capture=$capture.path
  $savedHash=(Get-FileHash -LiteralPath $movie).Hash
  $auto=& $imageSender -ConnectionFile $connection -Path $SourcePng -SceneId $scene | ConvertFrom-Json -AsHashtable
  Check ($auto.adopted -and (Call 'movie-status').modified -and (Get-FileHash -LiteralPath $movie).Hash -eq $savedHash) 'sender default adopts image without saving project'
  $saved=& $imageSender -ConnectionFile $connection -Path $SourcePng -SceneId $scene -SaveProject | ConvertFrom-Json -AsHashtable
  Check ($saved.adopted -and $saved.projectSaved -and -not $saved.modified -and -not (Call 'movie-status').modified) 'explicit sender SaveProject persists adoption'
  Reject 'NoAdopt and SaveProject cannot silently conflict' {& $imageSender -ConnectionFile $connection -Path $SourcePng -SceneId $scene -NoAdopt -SaveProject}
  if($Full){
    Reject 'unknown transfer id rejected' {Call 'movie-image-transfer-status' @{transferId=[guid]::NewGuid().ToString()}}
    Reject 'oversize declared image rejected' {Call 'movie-image-transfer-begin' @{sceneId=$scene;byteCount=33554433;sha256=$ready.sha256;mimeType='image/png'}}
    Reject 'destination traversal input rejected' {Call 'movie-image-transfer-begin' @{sceneId=$scene;byteCount=$bytes.Length;sha256=$ready.sha256;mimeType='image/png';path='..\outside.png'}}
    Reject 'unsupported mime type rejected' {Call 'movie-image-transfer-begin' @{sceneId=$scene;byteCount=$bytes.Length;sha256=$ready.sha256;mimeType='image/jpeg'}}
    Reject 'unknown scene rejected' {Call 'movie-image-transfer-begin' @{sceneId='absent-scene';byteCount=$bytes.Length;sha256=$ready.sha256;mimeType='image/png'}}
    $cancel=StartTransfer $bytes;$null=Chunk $cancel.transferId $bytes 0;$null=Call 'movie-image-transfer-cancel' @{transferId=$cancel.transferId};$cancelled=WaitTransfer $cancel.transferId
    Check ($cancelled.state -eq 'cancelled') 'incomplete transfer cancels on worker'
    Check (-not (Test-Path -LiteralPath (Join-Path $env:TEMP ('RIGM-image-'+$process.Id+'-'+$cancel.transferId+'.partial')))) 'cancelled staging file removed'
    $one=StartTransfer $bytes;$two=StartTransfer $bytes
    Reject 'active transfer concurrency limit enforced' {StartTransfer $bytes}
    foreach($item in @($one,$two)){$null=Call 'movie-image-transfer-cancel' @{transferId=$item.transferId};$null=WaitTransfer $item.transferId}
    $bad=StartTransfer $bytes ('0'*64);$failed=Upload $bad.transferId $bytes
    Check ($failed.state -eq 'failed' -and $failed.error -like '*SHA-256*' -and -not $failed.path) 'hash mismatch cannot publish asset'
    $invalid=[byte[]]::new(50);$bad=StartTransfer $invalid;$failed=Upload $bad.transferId $invalid
    Check ($failed.state -eq 'failed' -and $failed.error -like '*PNG*') 'non PNG with valid hash rejected'
    $crc=[byte[]]$bytes.Clone();$crc[29]=$crc[29] -bxor 1;$bad=StartTransfer $crc;$failed=Upload $bad.transferId $crc
    Check ($failed.state -eq 'failed' -and -not $failed.path) 'PNG CRC corruption rejected'
    $large=[byte[]]$bytes.Clone();$large[16]=0;$large[17]=0;$large[18]=32;$large[19]=1;$bad=StartTransfer $large;$failed=Upload $bad.transferId $large
    Check ($failed.state -eq 'failed' -and $failed.error -like '*8192*') 'oversize decoded PNG rejected before decoder'
    $truncated=[byte[]]$bytes[0..($bytes.Length-2)];$bad=StartTransfer $truncated;$failed=Upload $bad.transferId $truncated
    Check ($failed.state -eq 'failed' -and -not $failed.path) 'truncated PNG cannot publish'
    $again=StartTransfer $bytes;$again=Upload $again.transferId $bytes
    Check ($again.state -eq 'ready' -and $again.path -eq $ready.path) 'existing identical asset reused'
    $null=Call 'movie-image-transfer-cancel' @{transferId=$again.transferId}
    Reject 'cancelled ready transfer cannot adopt' {Call 'movie-image-transfer-adopt' @{transferId=$again.transferId}}
    Check (Test-Path -LiteralPath $ready.path) 'cancel preserves already validated asset'
    $again=StartTransfer $bytes;$again=Upload $again.transferId $bytes
    $second=Join-Path $RunDirectory 'other-fixture.rigmovie';$other=[IO.File]::ReadAllText($movie)|ConvertFrom-Json -AsHashtable;$other.projectId=[guid]::NewGuid().ToString();$other.scenes[0].image=$ready.path
    $other|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $second -Encoding utf8BOM
    $null=Call 'movie-open' @{path=$second}
    Reject 'transfer cannot adopt into another project' {Call 'movie-image-transfer-adopt' @{transferId=$again.transferId}}
    $null=Call 'movie-open' @{path=$movie}
    $unchanged=Call 'movie-project';$current=Call 'movie-status'
    Check (-not $current.modified -and $unchanged.scenes[0].image -eq $savedSceneImage) 'all rejected cancelled and failed transfers preserve saved scene'
    $corrupt=[byte[]](1,2,3,4);[IO.File]::WriteAllBytes($ready.path,$corrupt)
    $bad=StartTransfer $bytes;$failed=Upload $bad.transferId $bytes
    Check ($failed.state -eq 'failed' -and $failed.error -like '*not be overwritten*' -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($ready.path)) -eq [Convert]::ToBase64String($corrupt)) 'existing corrupt asset rejected and preserved'
    $directory=Split-Path $ready.path;$preserved=$directory+'-preserved';$target=Join-Path $RunDirectory 'ReparseTarget'
    Move-Item -LiteralPath $directory -Destination $preserved;New-Item -ItemType Directory -Path $target | Out-Null
    try{
      New-Item -ItemType Junction -Path $directory -Target $target | Out-Null
      $bad=StartTransfer $bytes;$failed=Upload $bad.transferId $bytes
      Check ($failed.state -eq 'failed' -and $failed.error -like '*reparse point*' -and @(Get-ChildItem -LiteralPath $target -Force).Count -eq 0) 'destination junction rejected without writing through link'
    }finally{
      if(([IO.File]::GetAttributes($directory) -band [IO.FileAttributes]::ReparsePoint) -eq 0){throw 'Expected owned junction before removal'}
      [IO.Directory]::Delete($directory);Move-Item -LiteralPath $preserved -Destination $directory
    }
    Check ((Get-FileHash -LiteralPath $savedAsset).Hash -eq $record.sourceSha256) 'failed destination checks preserve saved scene asset'
  }
  $record.maxCommandLatencyMs=($latencies|Measure-Object -Maximum).Maximum
  $record.commandCount=$latencies.Count
  Check ($record.maxCommandLatencyMs -lt 3000) 'common pipe remains responsive during transfer and verification'
  $record.success=$true;$record.checkCount=$checks.Count;$record.finalAsset=$savedAsset;$record.finalAssetSha256=(Get-FileHash -LiteralPath $savedAsset).Hash
}catch{$record.success=$false;$record.error=$_.Exception.Message;throw}
finally{
  Persist
  if($process -and -not $process.HasExited){
    # Only our isolated fixture may be saved/closed. Never terminate any user app.
    if($connection){try{$null=Call 'movie-save'}catch{}}
    $record.normalCloseRequested=$process.CloseMainWindow();$record.closedNormally=$process.WaitForExit(5000);Persist
  }
}
$record|ConvertTo-Json -Depth 12
