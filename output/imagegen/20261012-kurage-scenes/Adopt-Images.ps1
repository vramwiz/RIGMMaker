param([Parameter(Mandatory)][string[]]$Keys)
$ErrorActionPreference='Stop'
$job=$PSScriptRoot
$invoke=Join-Path $job 'Invoke-Live.ps1'
$manifest=Get-Content -LiteralPath (Join-Path $job 'prompts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$requests=@(Get-Content -LiteralPath (Join-Path $job 'prepared-requests.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$exchange='C:\Users\zan12\Documents\RIGMMaker\Exchange\20261012-kurage-scenes'
New-Item -ItemType Directory -Force -Path $exchange | Out-Null
foreach($key in $Keys){
  $asset=@($manifest.assets | Where-Object key -eq $key)[0]
  $request=@($requests | Where-Object key -eq $key)[0]
  if($null -eq $asset -or $null -eq $request){throw ('Unknown asset: '+$key)}
  $s=& $invoke -Command 'app-script-status'
  if($s.projectId -ne $manifest.projectId -or $s.resumeStage -ne 'scenes'){throw 'Current project or stage changed'}
  $offset=0;if($asset.key -ne 'background'){$offset=[int]$asset.key-1}
  $page=& $invoke -Command 'app-script-scenes' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}|ConvertTo-Json -Compress)
  if($asset.key -eq 'background'){$row=$page.background}else{$row=@($page.rows)[0]}
  $expectedPrompt=$asset.prompt
  if($null -ne $asset.uiPrompt){$expectedPrompt=$asset.uiPrompt}
  $samePrompt=($row.imagePrompt -replace "`r`n","`n") -eq ($expectedPrompt -replace "`r`n","`n")
  if($row.id -ne $asset.id -or $row.imageApproved -or -not $samePrompt -or $row.imageRequest.state -ne 'pending' -or $row.imageRequest.requestId -ne $request.request.requestId){throw ('Current request changed: '+$key)}
  $source=Join-Path $job $asset.filename
  $target=Join-Path $exchange $asset.filename
  Copy-Item -LiteralPath $source -Destination $target
  $sha=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
  & $invoke -Command 'app-script-adopt-scene-image' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision;sceneId=$asset.id;requestId=$request.request.requestId;path=('Exchange/20261012-kurage-scenes/'+$asset.filename);sha256=$sha;provenance='external-generated'} | ConvertTo-Json -Compress) | Out-Null
  $s=& $invoke -Command 'app-script-status'
  & $invoke -Command 'app-script-save' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision}|ConvertTo-Json -Compress) | Out-Null
  $page=& $invoke -Command 'app-script-scenes' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}|ConvertTo-Json -Compress)
  if($asset.key -eq 'background'){$row=$page.background}else{$row=@($page.rows)[0]}
  $savedSha=(Get-FileHash -LiteralPath $row.imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if($savedSha -ne $sha -or $row.imageRequest.state -ne 'adopted'){throw ('Image verification failed: '+$key)}
  $record=@{key=$key;sceneId=$asset.id;requestId=$request.request.requestId;revision=$s.revision;workspacePath=$source;exchangePath=$target;managedPath=$row.imagePath;sha256=$sha;imageApproved=$row.imageApproved;requestState=$row.imageRequest.state}
  $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $job ('delivery-'+$key+'.json')) -Encoding UTF8
  [pscustomobject]$record
}
