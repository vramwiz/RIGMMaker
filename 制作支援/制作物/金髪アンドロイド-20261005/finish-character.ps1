$ErrorActionPreference='Stop'
$root=$PSScriptRoot;$sender=Join-Path $root '..\..\パイプ\Send-RigmCommand.ps1'
$conn=(Get-ChildItem -LiteralPath (Join-Path $root 'session\pipes') -Filter '*.control.json'|Select-Object -First 1).FullName
function Invoke-Rig([string]$command,[hashtable]$arguments=@{}) { $r=& $sender -ConnectionFile $conn -Command $command -ArgsJson ($arguments|ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 60000|ConvertFrom-Json -AsHashtable;return $r.data }
$bones=Get-Content -LiteralPath (Join-Path $root 'session\seed-bones.json') -Raw|ConvertFrom-Json -AsHashtable
$positions=@{'腰（下半身）'=@(4,-130);'上半身'=@(4,-375);'首'=@(4,-574);'頭'=@(4,-689);'左肩'=@(-149,-462);'右肩'=@(162,-462)}
$ops=@();foreach($b in $bones.items){$xy=$positions[$b.name];$ops+=@{command='update-bone';args=@{id=$b.id;x=$xy[0];y=$xy[1];paired=$false}}}
$head=($bones.items|Where-Object {$_.name -eq '頭'}).id;$upper=($bones.items|Where-Object {$_.name -eq '上半身'}).id
$assets=Get-Content -LiteralPath (Join-Path $root 'native-assets.json') -Raw|ConvertFrom-Json -AsHashtable
foreach($a in $assets){$bone=if($a.role -eq 'body'){$upper}else{$head};$ops+=@{command='bind-part';args=@{id=$a.id;boneId=$bone}}}
Invoke-Rig 'batch' @{operations=$ops}|Out-Null
Invoke-Rig 'mark-complete'|Out-Null
Invoke-Rig 'generate-mesh' @{grid=4;replaceExisting=$false}|Out-Null
Invoke-Rig 'mark-complete'|Out-Null
Invoke-Rig 'mark-complete'|Out-Null
$validated=Invoke-Rig 'validate' @{throughPage='preview';errorsOnly=$true;limit=50}
$validated|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'session\final-validation.json') -Encoding utf8
$assembled=Join-Path $root 'assembled.rigm'
Invoke-Rig 'save' @{path=$assembled}|Out-Null
$reg=Invoke-Rig 'app-register-character' @{path=$assembled;name='金髪アンドロイド・解説用（表情・口パク・ポーズ・感情）'}
$reg|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'registration.json') -Encoding utf8
$final=Join-Path $root '金髪アンドロイド-解説用.rigm';Copy-Item -LiteralPath $reg.path -Destination $final
Invoke-Rig 'status'|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'session\final-status.json') -Encoding utf8
Write-Output $reg.path
Write-Output $final
