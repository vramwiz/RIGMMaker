param([Parameter(Mandatory)][string[]]$Keys)
$ErrorActionPreference='Stop'
$job=$PSScriptRoot;$invoke=Join-Path $job 'Invoke-Live.ps1'
$m=Get-Content -LiteralPath (Join-Path $job 'prompts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$requests=@(Get-Content -LiteralPath (Join-Path $job 'prepared-requests.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
foreach($key in $Keys){
  $a=@($m.assets|Where-Object key -eq $key)[0]
  $s=& $invoke -Command 'app-script-status'
  if($s.projectId -ne $m.projectId -or $s.resumeStage -ne 'scenes'){throw 'Project or stage changed'}
  $p=& $invoke -Command 'app-script-scenes' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision;offset=([int]$key-1);limit=1}|ConvertTo-Json -Compress)
  $r=@($p.rows)[0]
  if($r.id -ne $a.id -or $r.imageApproved -or $r.imagePrompt -ne $a.uiPrompt -or $r.displayMode -ne $a.expectedDisplayMode){throw ('Input changed: '+$key)}
  & $invoke -Command 'app-script-request-scene-image' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision;sceneId=$a.id}|ConvertTo-Json -Compress) | Out-Null
  $s=& $invoke -Command 'app-script-status'
  $p=& $invoke -Command 'app-script-scenes' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision;offset=([int]$key-1);limit=1}|ConvertTo-Json -Compress)
  $r=@($p.rows)[0]
  if($r.imageRequest.state -ne 'pending' -or -not $r.imageRequest.current){throw 'New request is not current'}
  $requests=@($requests|Where-Object key -ne $key)+@(@{key=$key;sceneId=$a.id;request=$r.imageRequest})
}
$requests|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $job 'prepared-requests.json') -Encoding UTF8
$s=& $invoke -Command 'app-script-status'
& $invoke -Command 'app-script-save' -ArgsJson (@{projectId=$s.projectId;revision=$s.revision}|ConvertTo-Json -Compress)|Out-Null
[pscustomobject]@{refreshed=$Keys;revision=$s.revision}
