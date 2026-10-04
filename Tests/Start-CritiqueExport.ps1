#requires -Version 7.0
param([Parameter(Mandatory)][string]$RunFile)
$ErrorActionPreference='Stop'
$run=[IO.File]::ReadAllText($RunFile) | ConvertFrom-Json -AsHashtable
if(-not $run.imageReady -and -not $run.provisional){throw 'Finish the intended scene images before publishing a production video'}
if($run.exportJobId){throw 'This production already has an export job; inspect it instead of starting a duplicate'}
if(Test-Path -LiteralPath $run.output){throw 'Existing production output is protected'}
function Invoke-Product([string]$Command,[hashtable]$Arguments=@{}){
  $reply=& $run.sender -ConnectionFile $run.connection -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Depth 40 -Compress) -TimeoutMs 30000 | ConvertFrom-Json -AsHashtable
  if(-not $reply.ok){throw ('Product command failed: '+$Command)}
  return $reply.data
}
$preparation=Invoke-Product 'movie-preparation'
if(-not $preparation.canExport){throw ('Actual product diagnosis blocks output: '+($preparation | ConvertTo-Json -Depth 20 -Compress))}
$job=Invoke-Product 'movie-export' @{path=$run.output}
$run.exportJobId=$job.jobId;$run.stage='actual full-HD MP4 export running'
$run | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $RunFile -Encoding utf8BOM
$job | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run.runDirectory 'export-start.json') -Encoding utf8BOM
$job | Select-Object jobId,kind,state,total,output | ConvertTo-Json
