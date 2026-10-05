$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$sender=Join-Path $root '..\..\..\パイプ\Send-RigmCommand.ps1'
$conn=(Get-ChildItem -LiteralPath (Join-Path $root 'session\pipes') -Filter '*.control.json'|Select-Object -First 1).FullName
function Invoke-M([string]$command,[hashtable]$arguments=@{}) {
 $r=& $sender -ConnectionFile $conn -Command ('movie-'+$command) -ArgsJson ($arguments|ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 60000|ConvertFrom-Json -AsHashtable
 if(!$r.ok){throw ($r|ConvertTo-Json -Depth 8 -Compress)}
 return $r.data
}
function Wait-Preview {
 for($i=0;$i -lt 150;$i++) {
  $j=Invoke-M 'job-status'
  if($j.done){if($j.state -ne 'succeeded'){throw ($j|ConvertTo-Json -Depth 8 -Compress)};return $j}
  Start-Sleep -Milliseconds 200
 }
 throw 'Preview still running; inspect this job before starting another.'
}
$final=Join-Path $root '金髪アンドロイド-解説用-感情記号9種追加.rigm'
$signs=Get-Content -LiteralPath (Join-Path $root 'symbols.json') -Raw|ConvertFrom-Json -AsHashtable
Invoke-M 'update-project' @{title='感情記号9種・表示確認（無音）';character=$final;width=720;height=1280;fps=30}|Out-Null
Invoke-M 'import-script' @{text='narrator:感情記号を確認します。'}|Out-Null
$project=Invoke-M 'project';$cue=$project.cues[0].id
Invoke-M 'update-cue' @{id=$cue;pause=4.0;subtitle='';motion='still';parameters=@{eyeOpen=1;mouthOpen=0};acting=@{headGain=0;bodyGain=0;mouthMode='assets';blinkMode='assets';blinkPhase=0;fadeIn=0;fadeOut=0;variants=@()}}|Out-Null
$results=@()
New-Item -ItemType Directory -Path (Join-Path $root 'native-previews') -Force|Out-Null
foreach($s in $signs) {
 Invoke-M 'update-cue' @{id=$cue;acting=@{variants=@(@{groupId=$s.parentId;partId=$s.id})}}|Out-Null
 $path=Join-Path $root ('native-previews\symbol-'+$s.kind.ToString('00')+'.png')
 Invoke-M 'preview' @{time=0.5;path=$path}|Out-Null
 $job=Wait-Preview
 $results+=@{kind=$s.kind;name=$s.name;path=$path;job=$job;variant=@{groupId=$s.parentId;partId=$s.id}}
 Write-Output ('Preview succeeded: '+$s.kind+' '+$s.name)
}
$results|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $root 'native-preview-verification.json') -Encoding utf8
Invoke-M 'save' @{path=(Join-Path $root 'session\感情記号表示確認-無音.rigmovie')}|Out-Null
