param()
$ErrorActionPreference='Stop'
$job=$PSScriptRoot
$invoke=Join-Path $job 'Invoke-Live.ps1'
$manifest=Get-Content -LiteralPath (Join-Path $job 'prompts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$baseline=@(Get-Content -LiteralPath (Join-Path $job 'all-scenes.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
function Live([string]$Command,$ArgsObject){
  & $invoke -Command $Command -ArgsJson ($ArgsObject | ConvertTo-Json -Depth 50 -Compress)
}
foreach($asset in $manifest.assets){
  $s=& $invoke -Command 'app-script-status'
  if($s.projectId -ne $manifest.projectId -or $s.resumeStage -ne 'scenes'){throw 'Current project or stage changed'}
  $offset=0
  if($asset.key -ne 'background'){$offset=[int]$asset.key-1}
  $page=Live 'app-script-scenes' @{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}
  if($asset.key -eq 'background'){$row=$page.background}else{$row=@($page.rows)[0]; if($row.id -ne $baseline[$offset].id){throw 'Scene identity changed'}; if(($row.sourceCues | ConvertTo-Json -Depth 20 -Compress) -ne ($baseline[$offset].sourceCues | ConvertTo-Json -Depth 20 -Compress)){throw 'Script cues changed'}}
  if($row.imageApproved -or $row.imagePrompt -or $row.imageFeedback -or $row.imagePath){throw ('Existing scene input changed: '+$asset.key)}
  $asset | Add-Member -NotePropertyName id -NotePropertyValue $row.id -Force
  Live 'app-script-edit-scene' @{projectId=$s.projectId;revision=$s.revision;sceneId=$row.id;prompt=$asset.prompt;displayMode='image'} | Out-Null
}
$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $job 'prompts.json') -Encoding UTF8
$s=& $invoke -Command 'app-script-status'
Live 'app-script-request-unapproved-images' @{projectId=$s.projectId;revision=$s.revision} | Out-Null
$s=& $invoke -Command 'app-script-status'
Live 'app-script-save' @{projectId=$s.projectId;revision=$s.revision} | Out-Null
$requests=@()
foreach($asset in $manifest.assets){
  $s=& $invoke -Command 'app-script-status'
  $offset=0;if($asset.key -ne 'background'){$offset=[int]$asset.key-1}
  $page=Live 'app-script-scenes' @{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}
  if($asset.key -eq 'background'){$row=$page.background}else{$row=@($page.rows)[0]}
  if($row.id -ne $asset.id -or $row.imageRequest.state -ne 'pending'){throw ('Request not pending: '+$asset.key)}
  $requests+=@{key=$asset.key;sceneId=$row.id;request=$row.imageRequest}
}
$requests | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $job 'prepared-requests.json') -Encoding UTF8
[pscustomobject]@{prepared=$requests.Count;projectId=$manifest.projectId;revision=$s.revision}
