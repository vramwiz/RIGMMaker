$ErrorActionPreference='Stop'
$invoke=Join-Path $PSScriptRoot 'Invoke-Live.ps1'
$plan=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'generation-plan.json') -Raw -Encoding UTF8|ConvertFrom-Json
$requests=@()
foreach($row in $plan.rows){
 $s=& $invoke -Command app-script-status
 if($s.projectId -ne $plan.projectId){throw 'Active project changed'}
 $a=@{projectId=$s.projectId;revision=$s.revision;offset=($row.sceneNumber-1);limit=1}|ConvertTo-Json -Compress
 $page=& $invoke -Command app-script-scenes -ArgsJson $a
 $live=$page.rows[0]
 if($live.id -ne $row.sceneId -or $live.imageApproved -or $live.imagePrompt -or $live.image){throw ('Scene changed or contains existing work: '+$row.sceneNumber)}
 $a=@{projectId=$s.projectId;revision=$s.revision;sceneId=$row.sceneId;prompt=$row.prompt}|ConvertTo-Json -Compress
 $s=& $invoke -Command app-script-edit-scene -ArgsJson $a
 $a=@{projectId=$s.projectId;revision=$s.revision;sceneId=$row.sceneId}|ConvertTo-Json -Compress
 $s=& $invoke -Command app-script-request-scene-image -ArgsJson $a
 $a=@{projectId=$s.projectId;revision=$s.revision;offset=($row.sceneNumber-1);limit=1}|ConvertTo-Json -Compress
 $page=& $invoke -Command app-script-scenes -ArgsJson $a -OutputFile (Join-Path $PSScriptRoot ('requested-'+$row.sceneNumber+'.json'))
 $requests+=,$page.rows[0]
}
$requests | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'image-requests.json') -Encoding UTF8
$s=& $invoke -Command app-script-status
$a=@{projectId=$s.projectId;revision=$s.revision}|ConvertTo-Json -Compress
$saved=& $invoke -Command app-script-save -ArgsJson $a
@{requested=$requests.Count;revision=$saved.revision;projectId=$saved.projectId}
