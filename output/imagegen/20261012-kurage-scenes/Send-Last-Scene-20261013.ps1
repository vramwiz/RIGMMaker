$ErrorActionPreference='Stop'
$job=$PSScriptRoot
$invoke=Join-Path $job 'Invoke-Live.ps1'
$projectId='{B0D28F94-242A-41D0-A527-882802487812}'
$sceneId='{7A3A2780-1869-4865-8386-5C4815D0FC18}'
$source=Join-Path $job 'thumbnail-logo.png'
$sha=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -ne '61d88ed15b36c160ad99676e610b827fe7f37baa72cffeb387e71cb025883ce4'){throw 'Accepted image changed'}
function Status {
  $s=& $invoke -Command 'app-script-status'
  if($s.projectId -ne $projectId -or $s.resumeStage -ne 'scenes'){throw 'Current project or stage changed'}
  $s
}
function Command([string]$Name,$Payload){& $invoke -Command $Name -ArgsJson ($Payload|ConvertTo-Json -Depth 30 -Compress)}
$s=Status
$page=Command 'app-script-scenes' @{projectId=$projectId;revision=$s.revision;offset=13;limit=1}
$row=@($page.rows)[0]
if($row.id -ne $sceneId -or $row.imageApproved -or $row.imagePath -or $row.imagePrompt -or $row.displayMode -ne 'none'){throw 'Last scene input changed'}
$prompt='ユーザーが採用したタイトルロゴ付き画像を最後に表示する。「漫画 男子校のくらげ先生」の大きなロゴ、くらげ先生・男子生徒・東北きりたん。きりたんは指さしポーズ。ロゴ背面は濃紺の図形。'
Command 'app-script-edit-scene' @{projectId=$projectId;revision=$s.revision;sceneId=$sceneId;prompt=$prompt;displayMode='image'} | Out-Null
$s=Status
Command 'app-script-request-scene-image' @{projectId=$projectId;revision=$s.revision;sceneId=$sceneId} | Out-Null
$s=Status
$page=Command 'app-script-scenes' @{projectId=$projectId;revision=$s.revision;offset=13;limit=1}
$row=@($page.rows)[0]
if($row.id -ne $sceneId -or $row.imageApproved -or -not $row.imageRequest.current -or $row.imageRequest.state -ne 'pending' -or $row.imagePrompt -ne $prompt){throw 'New image request changed'}
$request=$row.imageRequest
$request|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $job 'last-scene-request-20261013.json') -Encoding UTF8
$exchange='C:\Users\zan12\Documents\RIGMMaker\Exchange\20261012-kurage-scenes\thumbnail-logo.png'
Copy-Item -LiteralPath $source -Destination $exchange
Command 'app-script-adopt-scene-image' @{projectId=$projectId;revision=$s.revision;sceneId=$sceneId;requestId=$request.requestId;path='Exchange/20261012-kurage-scenes/thumbnail-logo.png';sha256=$sha;provenance='external-generated'} | Out-Null
$s=Status
Command 'app-script-select-scene' @{projectId=$projectId;revision=$s.revision;sceneId=$sceneId} | Out-Null
$s=Status
Command 'app-script-save' @{projectId=$projectId;revision=$s.revision} | Out-Null
$s=Status
$page=Command 'app-script-scenes' @{projectId=$projectId;revision=$s.revision;offset=13;limit=1}
$page|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $job 'last-scene-after-20261013.json') -Encoding UTF8
$row=@($page.rows)[0]
if($row.id -ne $sceneId -or $row.displayMode -ne 'image' -or -not $row.imagePath -or $row.imageRequest.state -ne 'adopted'){throw 'Image not adopted'}
$savedSha=(Get-FileHash -LiteralPath $row.imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if($savedSha -ne $sha){throw 'Saved image hash mismatch'}
$before=Get-Content -LiteralPath (Join-Path $job 'project-before-last-scene-20261013.rigmovie') -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $s.path -Raw -Encoding UTF8|ConvertFrom-Json
if(($before.cues|ConvertTo-Json -Depth 50 -Compress) -ne ($after.cues|ConvertTo-Json -Depth 50 -Compress)){throw 'Cue or audio fields changed'}
$record=@{date='2026-10-13';projectId=$projectId;revision=$s.revision;sceneId=$sceneId;sceneTitle=$row.title;sceneNumber=14;workspacePath=$source;exchangePath=$exchange;managedPath=$row.imagePath;sha256=$sha;requestId=$request.requestId;requestState=$row.imageRequest.state;displayMode=$row.displayMode;imageApproved=$row.imageApproved;projectModified=$s.modified;allCuesAndAudioFieldsUnchanged=$true;dedicatedThumbnailImage=$page.thumbnail.imagePath;dedicatedThumbnailSourcesReady=$page.thumbnail.sourcesReady}
$record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $job 'last-scene-delivery-20261013.json') -Encoding UTF8
$record
