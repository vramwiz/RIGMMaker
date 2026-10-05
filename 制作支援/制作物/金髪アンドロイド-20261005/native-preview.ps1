$ErrorActionPreference='Stop'
$root=$PSScriptRoot;$sender=Join-Path $root '..\..\パイプ\Send-RigmCommand.ps1'
$conn=(Get-ChildItem -LiteralPath (Join-Path $root 'session\pipes') -Filter '*.control.json'|Select-Object -First 1).FullName
function Invoke-M([string]$command,[hashtable]$arguments=@{}) {$r=& $sender -ConnectionFile $conn -Command ('movie-'+$command) -ArgsJson ($arguments|ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 60000|ConvertFrom-Json -AsHashtable;return $r.data}
function Wait-Job { for($i=0;$i -lt 100;$i++) {$j=Invoke-M 'job-status';if($j.done){if($j.state -ne 'succeeded'){throw ($j|ConvertTo-Json -Depth 8 -Compress)};return $j};Start-Sleep -Milliseconds 200};throw 'Preview still running; inspect the existing job before starting another.' }
$final=Join-Path $root '金髪アンドロイド-解説用.rigm'
Invoke-M 'update-project' @{title='金髪アンドロイド・素材動作確認（無音）';character=$final;width=720;height=1280;fps=30}|Out-Null
Invoke-M 'import-script' @{text="narrator:素材の目パチと口形を確認します。"}|Out-Null
$project=Invoke-M 'project';$project|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $root 'session\preview-project.json') -Encoding utf8
$cue=$project.cues[0].id
Invoke-M 'update-cue' @{id=$cue;pause=4.0;subtitle='';motion='still';acting=@{headGain=0;bodyGain=0;mouthMode='assets';blinkMode='assets';blinkPhase=0;fadeIn=0;fadeOut=0}}|Out-Null
$results=@()
foreach($item in @(@{name='native-normal';eye=1.0;mouth=0.0},@{name='native-blink-closed';eye=0.0;mouth=0.0},@{name='native-talking';eye=1.0;mouth=1.0})) {
 Invoke-M 'update-cue' @{id=$cue;parameters=@{eyeOpen=$item.eye;mouthOpen=$item.mouth}}|Out-Null
 $path=Join-Path $root ($item.name+'.png');Invoke-M 'preview' @{time=0.5;path=$path}|Out-Null
 $j=Wait-Job;$results+=@{name=$item.name;path=$path;job=$j}
}
Invoke-M 'update-cue' @{id=$cue;parameters=@{mouthOpen=0}}|Out-Null
$path=Join-Path $root 'native-automatic-blink.png';Invoke-M 'preview' @{time=0.08;path=$path}|Out-Null;$results+=@{name='native-automatic-blink';path=$path;job=(Wait-Job)}
$results|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $root 'native-preview-verification.json') -Encoding utf8
Write-Output ('Native previews succeeded: '+$results.Count)
