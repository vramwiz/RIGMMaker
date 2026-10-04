#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$PreviousRunFile,
  [Parameter(Mandatory)][string]$Executable,
  [Parameter(Mandatory)][string]$RunDirectory
)
$ErrorActionPreference='Stop'
$old=[IO.File]::ReadAllText($PreviousRunFile) | ConvertFrom-Json -AsHashtable
if(-not $old.owned -or $old.work -ne 'manga' -or $old.imageReady){throw 'This helper prepares only the owned manga awaiting images'}
if(Test-Path -LiteralPath $RunDirectory){throw 'Use a new run directory'}
$moviePath=Join-Path $old.projectDirectory '雨町の地図屋-画像未反映暫定版.rigmovie'
$output=Join-Path $old.projectDirectory 'Exports\雨町の地図屋-画像未反映暫定版.mp4'
if((Test-Path -LiteralPath $moviePath) -or (Test-Path -LiteralPath $output)){throw 'Existing provisional project/output is protected'}
$sourceHash=(Get-FileHash -LiteralPath $old.movie -Algorithm SHA256).Hash
New-Item -ItemType Directory -Path $RunDirectory -ErrorAction Stop | Out-Null
$pipes=Join-Path $RunDirectory 'Pipes';$settings=Join-Path $RunDirectory 'Settings'
New-Item -ItemType Directory -Path $pipes,$settings -ErrorAction Stop | Out-Null
$previousSettings=$env:RIGMMAKER_SETTINGS_DIR
try{
  $env:RIGMMAKER_SETTINGS_DIR=$settings
  $process=Start-Process -FilePath $Executable -ArgumentList @(('"--pipe-dir='+$pipes+'"'),('"--settings-dir='+$settings+'"'),('"--data-dir='+(Join-Path $RunDirectory 'Library')+'"')) -WindowStyle Hidden -PassThru
}finally{$env:RIGMMAKER_SETTINGS_DIR=$previousSettings}
$run=$old.Clone();$run.pid=$process.Id;$run.executable=$Executable;$run.executableSha256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
$run.movie=$moviePath;$run.output=$output;$run.provisional=$true;$run.imageReady=$false
$run.provisionalSource=$old.movie;$run.provisionalSourceSha256=$sourceHash
$run.previousRunFile=$PreviousRunFile;$run.runDirectory=$RunDirectory;$run.connection='';$run.exportJobId='';$run.audioJobId=''
$run.savedSpeechReusedWithoutGeneration=$true;$run.startedUtc=[DateTime]::UtcNow.ToString('o');$run.stage='preparing explicitly labeled provisional manga'
$runFile=Join-Path $RunDirectory 'run.json'
function Persist{$run | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $runFile -Encoding utf8BOM}
Persist
Copy-Item -LiteralPath (Join-Path $old.runDirectory 'audio-results.json') -Destination (Join-Path $RunDirectory 'audio-results.json') -ErrorAction Stop
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do{
  $connection=Get-ChildItem -LiteralPath $pipes -File -Filter '*.json' | Where-Object {$_.Name.StartsWith('RIGMMaker.'+$process.Id+'.')} | Select-Object -First 1
  if($connection){break}
  if($process.HasExited){throw 'Owned provisional instance exited'}
  Start-Sleep -Milliseconds 100
}while([DateTime]::UtcNow -lt $deadline)
if(-not $connection){throw 'Owned provisional pipe is missing'}
$run.connection=$connection.FullName;Persist
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$null=Invoke-Product 'app-open-work' @{path=$old.movie}
$project=Invoke-Product 'movie-project' @{limit=100}
if(@($project.scenes | Where-Object {$_.image}).Count){throw 'Expected image-free manga, preserving image-backed works instead'}
$null=Invoke-Product 'movie-update-project' @{title='雨町の地図屋｜画像未反映の暫定版・架空作品';outputTarget=$output}
foreach($scene in $project.scenes){
  $null=Invoke-Product 'movie-update-scene' @{id=$scene.id;title=($scene.title+'｜画像未反映の暫定版');description=('画像未反映の暫定版です。'+$scene.description)}
}
$cue=$project.cues[0]
$null=Invoke-Product 'movie-update-cue' @{id=$cue.id;subtitle=('【画像未反映の暫定版】'+[Environment]::NewLine+$cue.subtitle)}
$null=Invoke-Product 'movie-save' @{path=$moviePath}
$null=Invoke-Product 'movie-open' @{path=$moviePath}
$run.stage='provisional saved with real speech; export has not started';Persist
& (Join-Path $PSScriptRoot 'Preview-CritiqueScenes.ps1') -RunFile $runFile
if((Get-FileHash -LiteralPath $old.movie -Algorithm SHA256).Hash -ne $sourceHash){throw 'Original image-pending manga changed'}
$runFile
