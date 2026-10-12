param([Parameter(Mandatory)][int]$SceneNumber,[Parameter(Mandatory)][string]$GeneratedPath)
$ErrorActionPreference='Stop'
$invoke=Join-Path $PSScriptRoot 'Invoke-Live.ps1'
$plan=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'generation-plan.json') -Raw -Encoding UTF8|ConvertFrom-Json
$row=$plan.rows|Where-Object {$_.sceneNumber -eq $SceneNumber}
$original=Get-Content -LiteralPath (Join-Path $PSScriptRoot ('requested-'+$SceneNumber+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
$s=& $invoke -Command app-script-status
if($s.projectId -ne $plan.projectId){throw 'Active project changed'}
$a=@{projectId=$s.projectId;revision=$s.revision;offset=($SceneNumber-1);limit=1}|ConvertTo-Json -Compress
$page=& $invoke -Command app-script-scenes -ArgsJson $a
$current=$page.rows[0]
if($current.id -ne $row.sceneId -or $current.imageApproved -or $current.imageRequest.state -ne 'pending' -or -not $current.imageRequest.current -or $current.imageRequest.requestId -ne $original.rows[0].imageRequest.requestId -or $current.imageRequest.fingerprint -ne $original.rows[0].imageRequest.fingerprint){throw 'Scene image request changed; preserve generated file and re-read'}
$workspace=Join-Path $PSScriptRoot $row.output
if(Test-Path -LiteralPath $workspace){throw 'Workspace output already exists'}
Copy-Item -LiteralPath $GeneratedPath -Destination $workspace
$hash=(Get-FileHash -LiteralPath $workspace -Algorithm SHA256).Hash.ToLowerInvariant()
$exchange=Join-Path $s.pipes.dataRoot ('Exchange\generated-20261012-'+$SceneNumber+'-'+$hash.Substring(0,12)+'.png')
if(Test-Path -LiteralPath $exchange){throw 'Exchange output already exists'}
Copy-Item -LiteralPath $workspace -Destination $exchange
$a=@{projectId=$s.projectId;revision=$s.revision;sceneId=$row.sceneId;requestId=$current.imageRequest.requestId;path=$exchange;sha256=$hash;provenance='external-generated'}|ConvertTo-Json -Compress
$s=& $invoke -Command app-script-adopt-scene-image -ArgsJson $a -OutputFile (Join-Path $PSScriptRoot ('adopted-status-'+$SceneNumber+'.json'))
$a=@{projectId=$s.projectId;revision=$s.revision;offset=($SceneNumber-1);limit=1}|ConvertTo-Json -Compress
$page=& $invoke -Command app-script-scenes -ArgsJson $a -OutputFile (Join-Path $PSScriptRoot ('verified-'+$SceneNumber+'.json'))
$managed=$page.rows[0].imagePath
if(-not $managed -or -not(Test-Path -LiteralPath $managed)){throw 'Managed image not found'}
if((Get-FileHash -LiteralPath $managed -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash){throw 'Managed image hash mismatch'}
if($page.rows[0].imageRequest.state -ne 'adopted'){throw 'Adoption state mismatch'}
$receipt=@{sceneNumber=$SceneNumber;sceneId=$row.sceneId;requestId=$current.imageRequest.requestId;generatedPath=$GeneratedPath;workspacePath=$workspace;exchangePath=$exchange;managedPath=$managed;sha256=$hash;revision=$s.revision;humanApproved=$page.rows[0].imageApproved;verified=$true;sentAt=[DateTime]::UtcNow.ToString('o')}
$receipt|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $PSScriptRoot ('receipt-'+$SceneNumber+'.json')) -Encoding UTF8
$s=& $invoke -Command app-script-status
$a=@{projectId=$s.projectId;revision=$s.revision}|ConvertTo-Json -Compress
$null=& $invoke -Command app-script-save -ArgsJson $a
$receipt|Select-Object sceneNumber,verified,revision,humanApproved,managedPath
