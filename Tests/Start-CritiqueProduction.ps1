#requires -Version 7.0
param(
  [ValidateSet('anime','manga')][string]$Work,
  [string]$ProjectDirectory,
  [string]$RunDirectory,
  [string]$SourceMovie,
  [string]$RigFile,
  [string]$RigInspection,
  [string]$ScriptFile,
  [string]$Executable
)
$ErrorActionPreference='Stop'
foreach($path in @($SourceMovie,$RigFile,$RigInspection,$ScriptFile,$Executable)){
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw ('Missing production input: '+$path)}
}
if((Test-Path -LiteralPath $ProjectDirectory) -or (Test-Path -LiteralPath $RunDirectory)){
  throw 'Use new project/run directories; existing works and jobs will not be overwritten'
}
$repository=Split-Path -Parent $PSScriptRoot
$sender=(Get-ChildItem -LiteralPath $repository -Recurse -File -Filter 'Send-RigmCommand.ps1' |
  Where-Object {-not $_.FullName.StartsWith((Join-Path $repository 'Win64'),[StringComparison]::OrdinalIgnoreCase)} |
  Select-Object -First 1).FullName
if(-not $sender){throw 'Current common-pipe sender is missing'}
$source=[IO.File]::ReadAllText($SourceMovie) | ConvertFrom-Json -AsHashtable
$inspection=[IO.File]::ReadAllText($RigInspection) | ConvertFrom-Json -AsHashtable
$script=[IO.File]::ReadAllText($ScriptFile) | ConvertFrom-Json -AsHashtable
$sourceBase=Split-Path -Parent $SourceMovie
function Resolved([string]$Path){
  if(-not $Path){return ''}
  if([IO.Path]::IsPathRooted($Path)){return [IO.Path]::GetFullPath($Path)}
  return [IO.Path]::GetFullPath((Join-Path $sourceBase $Path))
}
$sourceHash=(Get-FileHash -LiteralPath $SourceMovie -Algorithm SHA256).Hash
$rigHash=(Get-FileHash -LiteralPath $RigFile -Algorithm SHA256).Hash
New-Item -ItemType Directory -Path $ProjectDirectory,$RunDirectory -ErrorAction Stop | Out-Null
$baseName=if($Work -eq 'anime'){'星灯り郵便局-批評制作例'}else{'雨町の地図屋-おすすめ制作例'}
$moviePath=Join-Path $ProjectDirectory ($baseName+'.rigmovie')
$exportDirectory=Join-Path $ProjectDirectory 'Exports'
New-Item -ItemType Directory -Path $exportDirectory -ErrorAction Stop | Out-Null
$mp4=Join-Path $exportDirectory ($baseName+'.mp4')
$actor=@{
  id='kiritan';name='東北きりたん';file=$RigFile;speaker='narrator';initialPosition='right'
  x=1480;y=90;width=400;height=730;visible=$true;rigSafe=$true
  allowGeneratedExpressions=$false;expressions=$inspection.expressions
}
$sceneIds=@('intro','appeal','concerns','closing','verdict')
$sceneTitles=@('導入','魅力','気になる点','向いている人','総評')
$sceneDescriptions=if($Work -eq 'anime'){
  @('海辺の夜間郵便局を舞台にした架空アニメの批評例。','手紙と町の灯りが、人との距離を変えていく。','静かな場面の目的と、展開の変化に注目。','気持ちをゆっくり追う物語との相性を考える。','五点満点の架空評価例。実在作品の点数ではありません。')
}else{
  @('雨の町の地図職人を描く架空マンガのおすすめ例。','手描きの地図とコマの流れが伝える気持ち。','相談の結末、背景の密度、各話の変化に注目。','町の細部と、暮らしの小さな選択を読む。','五点満点の架空評価例。実在作品の点数ではありません。')
}
$scenes=@()
for($i=0;$i -lt $sceneIds.Count;$i++){
  $image=''
  if($Work -eq 'anime'){$image=Resolved $source.scenes[[Math]::Min($i,3)].image}
  $scene=@{id=$sceneIds[$i];title=($sceneTitles[$i]+'｜架空作品の制作例');description=$sceneDescriptions[$i];image=$image;imagePrompt='';padding=0;animation=@{}}
  if($i -eq 4){$scene.chart=$script.chart}
  $scenes+=$scene
}
$cues=@()
for($i=0;$i -lt $script.cues.Count;$i++){
  $item=$script.cues[$i]
  $scene=$item.scene
  if($i -eq 12){$scene='closing'}
  $variants=@()
  $poseName=''
  if($i -in @(3,13)){$poseName='手のひらで紹介'}
  if(($Work -eq 'anime' -and $i -eq 5) -or ($Work -eq 'manga' -and $i -eq 4)){$poseName='左上を指さす'}
  if($poseName){
    $layer=$inspection.layers | Where-Object {$_.name.TrimStart('*') -eq $poseName -and $_.role -eq 'body'} | Select-Object -First 1
    if(-not $layer){throw ('The real PSD pose is missing: '+$poseName)}
    $variants+=@{groupId=$layer.parentId;partId=$layer.id}
  }
  $cues+=@{
    id=$item.id;scene=$scene;speaker='narrator';text=$item.text;subtitle=$item.subtitle
    emotion=$item.emotion;expression='neutral';motion='idle';background='';voiceStyleId=108
    pause=$item.pause;waveFile='';labFile='';audioKey='';audioSeconds=0;parameters=@{}
    acting=@{mouthMode='assets';blinkMode='assets';mouthGain=1;lipLead=0;blinkStrength=1;blinkInterval=4;blinkDuration=0.16;blinkPhase=0.73;headGain=0.18;bodyGain=0.08;imageAttention='auto';onset=0;duration=-1;fadeIn=0.15;fadeOut=0.15;variants=$variants}
  }
}
$project=@{
  format='RIGM-MOVIE';formatVersion=1;projectId=[guid]::NewGuid().ToString('N')
  title=$script.title;character=$RigFile;engineUrl=$script.voice.engineUrl
  ffmpeg=$source.ffmpeg;outputPreset='fullhd';width=1920;height=1080;fps=30;encodeProfile='balanced'
  outputTarget=$mp4;backgroundColor=3154456;revision=1
  layout='theme';lDirection='right';themeBackground=if($Work -eq 'anime'){Resolved $source.themeBackground}else{''}
  speakers=@(@{id='narrator';name='東北きりたん';styleId=108;speed=$script.voice.speed;pitch=0;intonation=1;volume=1})
  characters=@($actor);scenes=$scenes;cues=$cues;workflow=@{stage='script'}
}
$inputPath=Join-Path $RunDirectory 'production-input.json'
[IO.File]::WriteAllText($inputPath,($project | ConvertTo-Json -Depth 40),[Text.UTF8Encoding]::new($true))
Copy-Item -LiteralPath $ScriptFile -Destination (Join-Path $ProjectDirectory '制作台本.json') -ErrorAction Stop
[IO.File]::WriteAllText((Join-Path $ProjectDirectory 'ナレーション台本.txt'),(($script.cues | ForEach-Object {$_.text}) -join [Environment]::NewLine),[Text.UTF8Encoding]::new($true))
$pipes=Join-Path $RunDirectory 'Pipes'
$settings=Join-Path $RunDirectory 'Settings'
New-Item -ItemType Directory -Path $pipes,$settings -ErrorAction Stop | Out-Null
$previousSettings=$env:RIGMMAKER_SETTINGS_DIR
try{
  $env:RIGMMAKER_SETTINGS_DIR=$settings
  $process=Start-Process -FilePath $Executable -ArgumentList @(('"--pipe-dir='+$pipes+'"'),('"--settings-dir='+$settings+'"'),('"--data-dir='+(Join-Path $RunDirectory 'Library')+'"')) -WindowStyle Hidden -PassThru
}finally{$env:RIGMMAKER_SETTINGS_DIR=$previousSettings}
$record=@{
  work=$Work;pid=$process.Id;owned=$true;startedUtc=[DateTime]::UtcNow.ToString('o')
  executable=$Executable;executableSha256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
  sourceMovie=$SourceMovie;sourceMovieSha256=$sourceHash;rig=$RigFile;rigSha256=$rigHash
  runDirectory=$RunDirectory;projectDirectory=$ProjectDirectory;movie=$moviePath;output=$mp4
  sender=$sender;connection='';audioJobId='';voiceStyleId=108;cueCount=$cues.Count
  imageReady=($Work -eq 'anime');stage='starting owned product instance';humanDesktopVerification=$false
}
$runFile=Join-Path $RunDirectory 'run.json'
function Persist{$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $runFile -Encoding utf8BOM}
Persist
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do{
  $connection=Get-ChildItem -LiteralPath $pipes -File -Filter '*.json' | Where-Object {$_.Name.StartsWith('RIGMMaker.'+$process.Id+'.')} | Select-Object -First 1
  if($connection){break}
  if($process.HasExited){throw ('Owned product instance exited: '+$process.ExitCode)}
  Start-Sleep -Milliseconds 100
}while([DateTime]::UtcNow -lt $deadline)
if(-not $connection){throw 'Owned product instance did not publish its common-pipe connection'}
$record.connection=$connection.FullName;Persist
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $sender -ConnectionFile $record.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$reply=Invoke-Product 'movie-import-script' @{path=$inputPath;format='json'}
if($reply.cueCount -ne 18){throw 'Product did not import all eighteen production cues'}
$null=Invoke-Product 'movie-save' @{path=$moviePath}
$null=Invoke-Product 'movie-open-ui'
$job=Invoke-Product 'movie-audio-generate' @{directory=(Join-Path $ProjectDirectory 'GeneratedAudio')}
$record.audioJobId=$job.jobId;$record.stage='real VOICEVOX audio generation running'
Persist
$record | ConvertTo-Json -Depth 10
