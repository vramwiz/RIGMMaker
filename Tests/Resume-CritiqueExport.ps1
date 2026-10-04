#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$PreviousRunFile,
  [Parameter(Mandatory)][string]$Executable,
  [Parameter(Mandatory)][string]$RunDirectory
)
$ErrorActionPreference='Stop'
$old=[IO.File]::ReadAllText($PreviousRunFile) | ConvertFrom-Json -AsHashtable
if(-not $old.owned -or -not $old.imageReady){throw 'Only an owned production with finished images can resume'}
if(Test-Path -LiteralPath $RunDirectory){throw 'Use a new run directory to preserve previous job evidence'}
if(Test-Path -LiteralPath $old.output){throw 'Existing final output is protected'}
if(-not (Test-Path -LiteralPath $Executable -PathType Leaf)){throw 'Verified corrected executable is missing'}
if((Get-FileHash -LiteralPath $old.sourceMovie -Algorithm SHA256).Hash -ne $old.sourceMovieSha256){throw 'Original work changed'}
if((Get-FileHash -LiteralPath $old.rig -Algorithm SHA256).Hash -ne $old.rigSha256){throw 'Prepared rig changed'}
$movie=[IO.File]::ReadAllText($old.movie) | ConvertFrom-Json -AsHashtable
if(@($movie.cues | Where-Object {-not $_.waveFile -or -not $_.labFile}).Count){throw 'Saved real speech must already exist'}
New-Item -ItemType Directory -Path $RunDirectory -ErrorAction Stop | Out-Null
$pipes=Join-Path $RunDirectory 'Pipes';$settings=Join-Path $RunDirectory 'Settings'
New-Item -ItemType Directory -Path $pipes,$settings -ErrorAction Stop | Out-Null
$previousSettings=$env:RIGMMAKER_SETTINGS_DIR
try{
  $env:RIGMMAKER_SETTINGS_DIR=$settings
  $process=Start-Process -FilePath $Executable -ArgumentList @(('"--pipe-dir='+$pipes+'"'),('"--settings-dir='+$settings+'"'),('"--data-dir='+(Join-Path $RunDirectory 'Library')+'"')) -WindowStyle Hidden -PassThru
}finally{$env:RIGMMAKER_SETTINGS_DIR=$previousSettings}
$run=$old.Clone();$run.Remove('failure');$run.previousRunFile=$PreviousRunFile
$run.pid=$process.Id;$run.executable=$Executable;$run.executableSha256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
$run.runDirectory=$RunDirectory;$run.connection='';$run.exportJobId='';$run.audioJobId=''
$run.savedSpeechReusedWithoutGeneration=$true;$run.startedUtc=[DateTime]::UtcNow.ToString('o');$run.stage='corrected owned product opening saved production'
$runFile=Join-Path $RunDirectory 'run.json'
function Persist{$run | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $runFile -Encoding utf8BOM}
Persist
foreach($name in @('audio-results.json','previews.json')){
  $source=Join-Path $old.runDirectory $name
  if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $RunDirectory $name) -ErrorAction Stop}
}
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do{
  $connection=Get-ChildItem -LiteralPath $pipes -File -Filter '*.json' | Where-Object {$_.Name.StartsWith('RIGMMaker.'+$process.Id+'.')} | Select-Object -First 1
  if($connection){break}
  if($process.HasExited){throw 'Corrected owned product exited before publishing its pipe'}
  Start-Sleep -Milliseconds 100
}while([DateTime]::UtcNow -lt $deadline)
if(-not $connection){throw 'Corrected owned product did not publish its pipe'}
$run.connection=$connection.FullName;Persist
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$null=Invoke-Product 'app-open-work' @{path=$run.movie}
$null=Invoke-Product 'movie-diagnostics-refresh'
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do{
  # The form may start its preview after collecting diagnosis; consult the retained diagnostic state.
  $preparation=Invoke-Product 'movie-preparation'
  $current=Invoke-Product 'movie-status'
  if($preparation.diagnosticsCurrent -and -not $current.busy){break}
  Start-Sleep -Milliseconds 100
}while([DateTime]::UtcNow -lt $deadline)
if(-not $preparation.diagnosticsCurrent -or $current.busy){throw 'Saved production diagnosis did not finish'}
$preparation | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $RunDirectory 'preparation-before-export.json') -Encoding utf8BOM
if($preparation.audioPending -ne 0 -or -not $preparation.canExport){throw 'Saved production cannot export with its existing real speech'}
$workflow=Invoke-Product 'movie-workflow-status'
$workflow | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $RunDirectory 'workflow-before-export.json') -Encoding utf8BOM
$run.stage='corrected product ready; real speech reused';Persist
& (Join-Path $PSScriptRoot 'Start-CritiqueExport.ps1') -RunFile $runFile
$runFile
