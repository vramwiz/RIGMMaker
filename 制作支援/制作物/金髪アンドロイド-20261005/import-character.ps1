param([switch]$Resume)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$sender=Join-Path $root '..\..\パイプ\Send-RigmCommand.ps1'
$conn=(Get-ChildItem -LiteralPath (Join-Path $root 'session\pipes') -Filter '*.control.json' | Select-Object -First 1).FullName
function Invoke-Rig([string]$command,[hashtable]$arguments=@{}) {
 $result=& $sender -ConnectionFile $conn -Command $command -ArgsJson ($arguments|ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 60000 | ConvertFrom-Json -AsHashtable
 if(-not $result.ok){throw ('Command failed: '+$command)}
 return $result.data
}
$assets=Get-Content -LiteralPath (Join-Path $root 'assets-manifest-trimmed.json') -Raw | ConvertFrom-Json -AsHashtable
function All-Parts { $page=Invoke-Rig 'document' @{section='parts';limit=50};$items=@($page.items);for($offset=50;$offset -lt $page.total;$offset+=50){$items+=@( (Invoke-Rig 'document' @{section='parts';offset=$offset;limit=50}).items )};return $items }
$parts=All-Parts
if(-not $Resume -and $parts.Count -ne 1){throw 'This importer starts only on the isolated original-image document.'}
$groups=@{}
if(-not $Resume){
$original=$parts[0].id
Invoke-Rig 'update-layer' @{id=$original;name='比較用・元画像';role='reference';referenceOnly=$true;visible=$false;locked=$true} | Out-Null
foreach($name in @('体','後ろ髪','顔色','眉','目','口','髪','感情記号')) {
 $g=Invoke-Rig 'add-group' @{name=$name};$groups[$name]=$g.selectedId
}
$groups|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'native-groups.json') -Encoding utf8
$operations=@()
foreach($a in $assets) {$operations+=@{command='import-png';args=@{path=(Join-Path $root $a.file);parentId=$groups[$a.group];name=$a.name;role=$a.role;x=$a.centerX;y=$a.centerY}}}
Invoke-Rig 'batch' @{operations=$operations} | Out-Null
$parts=All-Parts
}else{foreach($p in $parts){if($p.kind -eq 'group'){$groups[$p.name]=$p.id}}}
$operations=@()
foreach($a in $assets) {
 $part=$parts|Where-Object { $_.parentId -eq $groups[$a.group] -and $_.name -eq $a.name }|Select-Object -First 1
 if(-not $part){throw ('Missing imported part: '+$a.group+'/'+$a.name)}
 $a.id=$part.id;$a.parentId=$part.parentId
 $operations+=@{command='update-layer';args=@{id=$a.id;visible=[bool]$a.visible;role=$a.role;tags=('android,narrator,'+$a.group);x=$a.centerX;y=$a.centerY}}
}
foreach($name in @('体','後ろ髪','顔色','眉','目','口','髪','感情記号')){$operations+=@{command='set-parent';args=@{id=$groups[$name];parentId='';index=0}}}
Invoke-Rig 'batch' @{operations=$operations} | Out-Null
$assets|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $root 'native-assets.json') -Encoding utf8
$groups|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'native-groups.json') -Encoding utf8
$validation=Invoke-Rig 'validate' @{throughPage='layer';errorsOnly=$true;limit=50}
$validation|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'session\layer-validation.json') -Encoding utf8
Invoke-Rig 'mark-complete' | Out-Null
Invoke-Rig 'document' @{section='bones';limit=50}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'session\seed-bones.json') -Encoding utf8
Write-Output ('Imported '+$assets.Count+' images in '+$groups.Count+' groups; advanced to bones.')
