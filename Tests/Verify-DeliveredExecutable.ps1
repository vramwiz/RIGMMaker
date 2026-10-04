#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$DeliveryReport,
  [Parameter(Mandatory)][string]$ProductionRun,
  [Parameter(Mandatory)][string]$RunDirectory
)
$ErrorActionPreference='Stop'
$delivery=[IO.File]::ReadAllText($DeliveryReport) | ConvertFrom-Json -AsHashtable
$source=[IO.File]::ReadAllText($ProductionRun) | ConvertFrom-Json -AsHashtable
if(-not $delivery.success -or (Get-FileHash -LiteralPath $delivery.launchExecutable -Algorithm SHA256).Hash -ne $delivery.sha256){throw 'Delivered executable is not verified'}
if(Test-Path -LiteralPath $RunDirectory){throw 'Use a new verification directory'}
$before=(Get-FileHash -LiteralPath $source.movie -Algorithm SHA256).Hash
New-Item -ItemType Directory -Path $RunDirectory -ErrorAction Stop | Out-Null
$pipes=Join-Path $RunDirectory 'Pipes';$settings=Join-Path $RunDirectory 'Settings'
New-Item -ItemType Directory -Path $pipes,$settings -ErrorAction Stop | Out-Null
$previousSettings=$env:RIGMMAKER_SETTINGS_DIR
try{
  $env:RIGMMAKER_SETTINGS_DIR=$settings
  $process=Start-Process -FilePath $delivery.launchExecutable -ArgumentList @(('"--pipe-dir='+$pipes+'"'),('"--settings-dir='+$settings+'"'),('"--data-dir='+(Join-Path $RunDirectory 'Library')+'"')) -WindowStyle Hidden -PassThru
}finally{$env:RIGMMAKER_SETTINGS_DIR=$previousSettings}
$run=@{pid=$process.Id;owned=$true;executable=$delivery.launchExecutable;executableSha256=$delivery.sha256;movie=$source.movie;movieSha256=$before;runDirectory=$RunDirectory;sender=$source.sender;connection='';humanDesktopVerification=$false}
$runFile=Join-Path $RunDirectory 'run.json'
function Persist{$run | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $runFile -Encoding utf8BOM}
Persist
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do{
  $connection=Get-ChildItem -LiteralPath $pipes -File -Filter '*.json' | Where-Object {$_.Name.StartsWith('RIGMMaker.'+$process.Id+'.')} | Select-Object -First 1
  if($connection){break}
  if($process.HasExited){throw 'Delivered executable exited during startup'}
  Start-Sleep -Milliseconds 100
}while([DateTime]::UtcNow -lt $deadline)
if(-not $connection){throw 'Delivered executable did not publish its pipe'}
$run.connection=$connection.FullName;Persist
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$null=Invoke-Product 'app-open-work' @{path=$source.movie}
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do{$status=Invoke-Product 'movie-status';if(-not $status.busy){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
if($status.busy -or $status.modified){throw 'Delivered executable did not open the saved production cleanly'}
$workflow=Invoke-Product 'movie-workflow-status'
if($workflow.currentStage -ne 'complete' -or -not $workflow.results.videoCurrent){throw 'Delivered executable cannot resume the completed production'}
& (Join-Path $PSScriptRoot 'Capture-OwnedProduct.ps1') -RunFile $runFile -Name 'delivered-root-startup'
$status | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $RunDirectory 'status.json') -Encoding utf8BOM
$workflow | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $RunDirectory 'workflow.json') -Encoding utf8BOM
if((Get-FileHash -LiteralPath $source.movie -Algorithm SHA256).Hash -ne $before){throw 'Opening the saved production modified it'}
# Close only this owned, saved, idle instance through its normal main-window close path.
$process.Refresh();$requested=$process.CloseMainWindow();$deadline=[DateTime]::UtcNow.AddSeconds(10)
do{$process.Refresh();if($process.HasExited){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
$run.success=$true;$run.workflowStage=$workflow.currentStage;$run.productionUnchanged=$true
$run.normalCloseRequested=$requested;$run.closedNormally=$process.HasExited;$run.completedUtc=[DateTime]::UtcNow.ToString('o');Persist
$run | ConvertTo-Json -Depth 8
