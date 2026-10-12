$ErrorActionPreference='Stop'
$job=$PSScriptRoot;$invoke=Join-Path $job 'Invoke-Live.ps1'
$projectId='{B0D28F94-242A-41D0-A527-882802487812}'
$source=Join-Path $job 'thumbnail-logo.png'
$sha=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -ne '61d88ed15b36c160ad99676e610b827fe7f37baa72cffeb387e71cb025883ce4'){throw 'Accepted thumbnail bytes changed'}
function Status {
  $s=& $invoke -Command 'app-script-status'
  if($s.projectId -ne $projectId -or $s.resumeStage -ne 'scenes'){throw 'Current project or stage changed'}
  $s
}
function Command([string]$Name,$Payload){& $invoke -Command $Name -ArgsJson ($Payload|ConvertTo-Json -Depth 50 -Compress)}
$s=Status
$page=Command 'app-script-scenes' @{projectId=$projectId;revision=$s.revision;offset=0;limit=1}
if(-not $page.thumbnail.sourcesReady -or $page.thumbnail.imageApproved -or $page.thumbnail.imagePath -or $page.thumbnail.logoText -ne '漫画　男子校のくらげ先生'){throw 'Thumbnail state changed'}
Command 'app-script-save' @{projectId=$projectId;revision=$s.revision}|Out-Null
$s=Status
Copy-Item -LiteralPath $s.path -Destination (Join-Path $job 'project-before-thumbnail-20261013.rigmovie')
Command 'app-script-request-scene-image' @{projectId=$projectId;revision=$s.revision;sceneId='thumbnail'}|Out-Null
$s=Status
$page=Command 'app-script-scenes' @{projectId=$projectId;revision=$s.revision;offset=0;limit=1}
$thumb=$page.thumbnail;$request=$thumb.imageRequest
if(-not $thumb.sourcesReady -or $thumb.imageApproved -or $request.state -ne 'pending' -or -not $request.current -or $request.sceneId -ne 'thumbnail'){throw 'Thumbnail request is not current'}
$request|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $job 'thumbnail-request-20261013.json') -Encoding UTF8
$exchange='C:\Users\zan12\Documents\RIGMMaker\Exchange\20261012-kurage-scenes\thumbnail-logo.png'
Copy-Item -LiteralPath $source -Destination $exchange
Command 'app-script-adopt-scene-image' @{projectId=$projectId;revision=$s.revision;sceneId='thumbnail';requestId=$request.requestId;path='Exchange/20261012-kurage-scenes/thumbnail-logo.png';sha256=$sha;provenance='external-generated'}|Out-Null
$s=Status
Command 'app-script-select-scene' @{projectId=$projectId;revision=$s.revision;sceneId='thumbnail'}|Out-Null
$s=Status
Command 'app-script-save' @{projectId=$projectId;revision=$s.revision}|Out-Null
$s=Status
$page=Command 'app-script-scenes' @{projectId=$projectId;revision=$s.revision;offset=0;limit=1}
$page|ConvertTo-Json -Depth 60|Set-Content -LiteralPath (Join-Path $job 'thumbnail-after-20261013.json') -Encoding UTF8
$thumb=$page.thumbnail
if($thumb.imageRequest.state -ne 'adopted' -or -not $thumb.imagePath){throw 'Thumbnail was not adopted'}
if((Get-FileHash -LiteralPath $thumb.imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha){throw 'Saved thumbnail hash mismatch'}
$before=Get-Content -LiteralPath (Join-Path $job 'project-before-thumbnail-20261013.rigmovie') -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $s.path -Raw -Encoding UTF8|ConvertFrom-Json
if(($before.cues|ConvertTo-Json -Depth 60 -Compress) -ne ($after.cues|ConvertTo-Json -Depth 60 -Compress)){throw 'Cue, subtitle or audio fields changed'}
if(($before.scenes|ConvertTo-Json -Depth 60 -Compress) -ne ($after.scenes|ConvertTo-Json -Depth 60 -Compress)){throw 'Normal scene or approval state changed'}
$record=@{date='2026-10-13';projectId=$projectId;revision=$s.revision;sceneId='thumbnail';workspacePath=$source;exchangePath=$exchange;managedPath=$thumb.imagePath;sha256=$sha;requestId=$request.requestId;requestState=$thumb.imageRequest.state;imageApproved=$thumb.imageApproved;sourcesReady=$thumb.sourcesReady;projectModified=$s.modified;allCuesSubtitlesAndAudioUnchanged=$true;allNormalScenesAndApprovalsUnchanged=$true;selectedScene=$page.selectedScene}
$record|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $job 'thumbnail-delivery-20261013.json') -Encoding UTF8
$prepared=Get-Content -LiteralPath (Join-Path $job 'thumbnail-prepared.json') -Raw -Encoding UTF8|ConvertFrom-Json
$prepared.adopted=$true;$prepared.sourcesReady=$true;$prepared.revision=$s.revision
$prepared|Add-Member -NotePropertyName deliveryRecord -NotePropertyValue (Join-Path $job 'thumbnail-delivery-20261013.json') -Force
$prepared|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $job 'thumbnail-prepared.json') -Encoding UTF8
$record
