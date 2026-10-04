#requires -Version 7.0
param([Parameter(Mandatory)][string]$RunFile)
$ErrorActionPreference='Stop'
$run=[IO.File]::ReadAllText($RunFile) | ConvertFrom-Json -AsHashtable
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
for($stage=0;$stage -lt 6;$stage++){
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  do{
    $workflow=Invoke-Product 'movie-workflow-status'
    if(-not $workflow.busy){break}
    Start-Sleep -Milliseconds 100
  }while([DateTime]::UtcNow -lt $deadline)
  if($workflow.currentStage -eq 'export'){break}
  if(-not $workflow.canNext){throw ('Real product blocks workflow advance: '+($workflow | ConvertTo-Json -Depth 15 -Compress))}
  $null=Invoke-Product 'movie-workflow-next'
}
if($workflow.currentStage -ne 'export'){throw 'Production workflow did not reach export'}
$null=Invoke-Product 'movie-save' @{path=$run.movie}
$workflow=Invoke-Product 'movie-workflow-status'
$workflow | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'workflow-before-export.json') -Encoding utf8BOM
$run.stage=if($run.imageReady){'five real scene previews complete; ready for output review'}else{'real speech and chart complete; manga scene images still pending'}
$run | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $RunFile -Encoding utf8BOM
$workflow | Select-Object currentStage,ready,canRun,results | ConvertTo-Json -Depth 5
