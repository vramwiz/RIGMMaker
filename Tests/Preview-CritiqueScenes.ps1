#requires -Version 7.0
param([Parameter(Mandatory)][string]$RunFile)
$ErrorActionPreference='Stop'
$run=[IO.File]::ReadAllText($RunFile) | ConvertFrom-Json -AsHashtable
$audio=[IO.File]::ReadAllText((Join-Path $run.runDirectory 'audio-results.json')) | ConvertFrom-Json -AsHashtable
if(-not $audio.success){throw 'Complete and verify the real speech first'}
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
function Wait-Job([string]$JobId,[string]$Scope='main'){
  $deadline=[DateTime]::UtcNow.AddSeconds(40)
  do{
    $arguments=if($Scope -eq 'diagnostics'){@{scope=$Scope}}else{@{jobId=$JobId}}
    $job=Invoke-Product 'movie-job-status' $arguments
    if($job.done){break}
    Start-Sleep -Milliseconds 100
  }while([DateTime]::UtcNow -lt $deadline)
  if(-not $job.done -or $job.state -ne 'succeeded'){throw ('Product job did not succeed: '+($job | ConvertTo-Json -Compress))}
  return $job
}
$diagnostics=Invoke-Product 'movie-diagnostics-refresh'
$null=Wait-Job '' 'diagnostics'
$preparation=Invoke-Product 'movie-preparation'
$preparation | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'diagnostics-preparation.json') -Encoding utf8BOM
if(-not $preparation.canPreview){throw 'Real product diagnosis blocks the production preview'}
$project=Invoke-Product 'movie-project' @{limit=100}
$directory=Join-Path $run.projectDirectory 'Previews'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$previews=@()
$scenes=if($run.imageReady -or $run.provisional){$project.scenes}else{@($project.scenes | Where-Object {$_.id -eq 'verdict'})}
foreach($scene in $scenes){
  $cue=$audio.cues | Where-Object {$_.scene -eq $scene.id} | Select-Object -First 1
  if(-not $cue){throw ('Scene has no real speech: '+$scene.id)}
  $suffix=if($run.provisional){'-provisional'}elseif($run.imageReady){''}else{'-before-images'}
  $target=Join-Path $directory ($scene.id+$suffix+'.png')
  if(Test-Path -LiteralPath $target){throw 'Choose new preview names; existing production previews are protected'}
  $time=[double]$cue.start+0.8
  $job=Invoke-Product 'movie-preview' @{time=$time;path=$target}
  $finished=Wait-Job $job.jobId
  if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'Product preview PNG is missing'}
  $previews+=@{scene=$scene.id;cue=$cue.id;emotion=$cue.emotion;time=$time;path=$target;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;job=$finished}
}
$previews | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'previews.json') -Encoding utf8BOM
$null=& (Join-Path $PSScriptRoot 'Advance-CritiqueWorkflow.ps1') -RunFile $RunFile
$previews | ForEach-Object {[pscustomobject]@{scene=$_.scene;time=$_.time;path=$_.path}} | ConvertTo-Json -Depth 5
