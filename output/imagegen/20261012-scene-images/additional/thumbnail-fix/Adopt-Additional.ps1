param([Parameter(Mandatory)][ValidateSet('background','summary','thumbnail')][string]$Key,[Parameter(Mandatory)][string]$GeneratedPath)
$ErrorActionPreference='Stop'
$invoke='D:\DelphiProg\RIGMMaker\output\imagegen\20261012-scene-images\Invoke-Live.ps1'
$original=Get-Content -LiteralPath (Join-Path $PSScriptRoot ('requested-'+$Key+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
$s=& $invoke -Command app-script-status
if($s.projectId -ne '{0C6B3396-4F42-46DE-8A5F-EF3A0DD84AEF}'){throw 'Active project changed'}
$offset=if($Key -eq 'summary'){9}else{0}
$a=@{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}|ConvertTo-Json -Compress
$p=& $invoke -Command app-script-scenes -ArgsJson $a
$current=switch($Key){'background'{$p.background};'summary'{$p.rows[0]};'thumbnail'{$p.thumbnail}}
if($current.id -ne $original.id -or $current.imageApproved -or $current.imageRequest.state -ne 'pending' -or -not $current.imageRequest.current -or $current.imageRequest.requestId -ne $original.imageRequest.requestId -or $current.imageRequest.fingerprint -ne $original.imageRequest.fingerprint){throw 'Image request changed; keep generated file and re-read'}
$workspace=Join-Path $PSScriptRoot ($Key+'.png')
if(Test-Path -LiteralPath $workspace){throw 'Output already exists'}
Copy-Item -LiteralPath $GeneratedPath -Destination $workspace
$hash=(Get-FileHash -LiteralPath $workspace -Algorithm SHA256).Hash.ToLowerInvariant()
$exchange=Join-Path $s.pipes.dataRoot ('Exchange\generated-additional-20261012-'+$Key+'-'+$hash.Substring(0,12)+'.png')
if(Test-Path -LiteralPath $exchange){throw 'Exchange output already exists'}
Copy-Item -LiteralPath $workspace -Destination $exchange
$a=@{projectId=$s.projectId;revision=$s.revision;sceneId=$current.id;requestId=$current.imageRequest.requestId;path=$exchange;sha256=$hash;provenance='external-generated'}|ConvertTo-Json -Compress
$s=& $invoke -Command app-script-adopt-scene-image -ArgsJson $a
$a=@{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}|ConvertTo-Json -Compress
$p=& $invoke -Command app-script-scenes -ArgsJson $a -OutputFile (Join-Path $PSScriptRoot ('verified-'+$Key+'.json'))
$result=switch($Key){'background'{$p.background};'summary'{$p.rows[0]};'thumbnail'{$p.thumbnail}}
if(-not $result.imagePath -or (Get-FileHash -LiteralPath $result.imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash -or $result.imageRequest.state -ne 'adopted'){throw 'Managed image verification failed'}
$receipt=@{key=$Key;sceneId=$result.id;requestId=$current.imageRequest.requestId;generatedPath=$GeneratedPath;workspacePath=$workspace;exchangePath=$exchange;managedPath=$result.imagePath;sha256=$hash;revision=$s.revision;humanApproved=$result.imageApproved;verified=$true;sentAt=[DateTime]::UtcNow.ToString('o')}
$receipt|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $PSScriptRoot ('receipt-'+$Key+'.json')) -Encoding UTF8
$s=& $invoke -Command app-script-status
$a=@{projectId=$s.projectId;revision=$s.revision}|ConvertTo-Json -Compress
$null=& $invoke -Command app-script-save -ArgsJson $a
$receipt|Select-Object key,verified,revision,humanApproved,managedPath

