#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$ConnectionFile,
  [Parameter(Mandatory)][string]$Path,
  [Parameter(Mandatory)][string]$SceneId,
  [string]$TransferId,
  [string]$StateFile,
  [string]$EditToken,
  [switch]$NoAdopt,
  [switch]$SaveProject
)
$ErrorActionPreference='Stop'
if($NoAdopt -and $SaveProject){throw 'SaveProject requires adoption; omit NoAdopt'}
$sender=Join-Path $PSScriptRoot 'Send-RigmCommand.ps1'
$file=[IO.File]::Open([IO.Path]::GetFullPath($Path),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
function Call([string]$Command,[hashtable]$Arguments=@{}){
  if($EditToken){$Arguments.editToken=$EditToken}
  $reply=& $sender -ConnectionFile $ConnectionFile -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Depth 15 -Compress) -TimeoutMs 10000 | ConvertFrom-Json -AsHashtable
  return $reply.data
}
function Persist([hashtable]$Status){
  if($StateFile){
    @{connectionFile=$ConnectionFile;sourcePath=[IO.Path]::GetFullPath($Path);sceneId=$SceneId;transferId=$Status.transferId;sha256=$Status.sha256;byteCount=$Status.byteCount;nextOffset=$Status.nextOffset;state=$Status.state} |
      ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StateFile -Encoding utf8BOM
  }
}
try{
  if($file.Length -lt 1 -or $file.Length -gt 33554432){throw 'PNG must be 1..32 MiB'}
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($file)).ToLowerInvariant()
  $file.Position=0
  if($TransferId){$status=Call 'movie-image-transfer-status' @{transferId=$TransferId}}
  else{$status=Call 'movie-image-transfer-begin' @{sceneId=$SceneId;byteCount=$file.Length;sha256=$hash;mimeType='image/png'}}
  if($status.sha256 -ne $hash -or $status.byteCount -ne $file.Length -or $status.sceneId -ne $SceneId){throw 'Resume source differs from the existing transfer'}
  $TransferId=$status.transferId;Persist $status
  $projectId=$status.projectId
  $buffer=[byte[]]::new(16384)
  while($status.state -eq 'receiving' -and $status.nextOffset -lt $file.Length){
    $offset=[long]$status.nextOffset;$file.Position=$offset
    $count=$file.Read($buffer,0,[Math]::Min($buffer.Length,$file.Length-$offset))
    $payload=[Convert]::ToBase64String($buffer,0,$count)
    for($attempt=0;$attempt -lt 6;$attempt++){
      try{
        $status=Call 'movie-image-transfer-chunk' @{transferId=$TransferId;projectId=$projectId;offset=$offset;data=$payload}
        break
      }catch{
        if($attempt -eq 5){throw}
        # A timed-out acknowledgement may already have accepted the bytes.
        Start-Sleep -Milliseconds 100
        $status=Call 'movie-image-transfer-status' @{transferId=$TransferId;projectId=$projectId}
        if($status.nextOffset -eq $offset+$count){break}
        if($status.state -ne 'receiving' -or $status.nextOffset -ne $offset){throw 'Transfer cannot resume at the expected offset'}
      }
    }
    Persist $status
    Write-Progress -Activity 'RIGM PNG pipe transfer' -Status ($status.acceptedBytes.ToString()+'/'+$file.Length) -PercentComplete ([int](100*$status.acceptedBytes/$file.Length))
  }
  $status=Call 'movie-image-transfer-finish' @{transferId=$TransferId;projectId=$projectId}
  $deadline=[DateTime]::UtcNow.AddSeconds(60)
  while($status.state -in @('receiving','validating') -and [DateTime]::UtcNow -lt $deadline){
    Start-Sleep -Milliseconds 100
    $status=Call 'movie-image-transfer-status' @{transferId=$TransferId;projectId=$projectId}
  }
  Persist $status
  if($status.state -ne 'ready'){throw ('Image transfer did not become ready: '+$status.state+' '+$status.error)}
  if(-not $NoAdopt){
    $status=Call 'movie-image-transfer-adopt' @{transferId=$TransferId;projectId=$projectId}
    if(-not $status.adopted){throw 'Verified image was not adopted'}
    if($SaveProject){$saved=Call 'movie-save' @{projectId=$projectId};$status.modified=$saved.modified;$status.projectSaved=$true}
  }
  Persist $status
  Write-Progress -Activity 'RIGM PNG pipe transfer' -Completed
  $status | ConvertTo-Json -Depth 8
}finally{$file.Dispose()}
