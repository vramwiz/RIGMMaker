#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $root 'Win64\Validation\IsolatedSettings\Run-MovieSenderValidation'
$directory=Join-Path $root ('Win64\Validation\MovieSender\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$hostDirectory=Join-Path $directory 'Sender'
New-Item -ItemType Directory -Path $hostDirectory -Force | Out-Null
$exe=Join-Path $directory 'RigmTests.exe'
Copy-Item -LiteralPath (Join-Path $root 'Win64\Validation\RigmTests.exe') -Destination $exe
$hostProcess=Start-Process -FilePath $exe -ArgumentList '--pipe-host' -WindowStyle Hidden -PassThru
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name);Write-Output ('PASS: '+$Name)}
try {
  $ready=Join-Path $hostDirectory 'ready.txt';$deadline=[DateTime]::UtcNow.AddSeconds(10)
  while(-not (Test-Path -LiteralPath $ready) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 20}
  if(-not (Test-Path -LiteralPath $ready)){throw 'Independent sender host did not become ready'}
  $connection=(Get-Content -LiteralPath $ready -Raw).Trim()
  $sender=Join-Path $root '制作支援\パイプ\Send-RigmCommand.ps1'
  function Invoke-Movie([string]$Name,[hashtable]$Arguments=@{}){
    & $sender -ConnectionFile $connection -Command $Name -ArgsJson ($Arguments | ConvertTo-Json -Depth 32 -Compress) | ConvertFrom-Json
  }
  $before=Invoke-Movie 'status'
  $schema=Invoke-Movie 'movie-schema'
  Check ($schema.ok -and @($schema.data.commands.PSObject.Properties).Count -eq 64) 'PowerShell sender obtains all movie command schemas'
  $initial=Invoke-Movie 'movie-status'
  $preparation=Invoke-Movie 'movie-preparation'
  Check ($preparation.ok -and $preparation.data.readOnly -and $preparation.data.nextCommand -eq 'movie-import-script') 'sender obtains machine-readable initial preparation without mutation'
  $null=Invoke-Movie 'movie-diagnostics-refresh'
  $null=Invoke-Movie 'movie-job-cancel' @{scope='diagnostics'}
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  do {$diagnostic=Invoke-Movie 'movie-job-status' @{scope='diagnostics'};if($diagnostic.data.done){break};Start-Sleep -Milliseconds 20}while([DateTime]::UtcNow -lt $deadline)
  Check ($diagnostic.ok -and $diagnostic.data.done) 'sender starts and cancels independent diagnosis through scoped job commands'
  $unchanged=Invoke-Movie 'movie-status'
  Check ($unchanged.data.projectId -eq $initial.data.projectId -and $unchanged.data.revision -eq $initial.data.revision -and -not $unchanged.data.modified) 'sender diagnosis preserves production identity revision and unsaved state'
  $import=Invoke-Movie 'movie-import-script' @{text='narrator:This is original sender test dialogue.'}
  Check ($import.ok -and $import.data.cueCount -eq 1 -and $import.data.modified) 'sender injects movie project identity and revision for script import'
  $target=Join-Path $directory 'intended-new-output.avi'
  $settings=Invoke-Movie 'movie-update-project' @{character='@sample';width=320;height=180;fps=10;outputTarget=$target}
  Check ($settings.ok -and $settings.data.revision -gt $import.data.revision) 'sender edits movie settings through existing common pipe'
  $seek=Invoke-Movie 'movie-seek' @{time=0.1}
  Check ($seek.ok -and $seek.data.time -eq 0.1) 'sender seeks movie timeline independently of RIGM preview pose'
  $path=Join-Path $directory 'preview.png';$null=Invoke-Movie 'movie-preview' @{time=0.1;path=$path}
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  do {$job=Invoke-Movie 'movie-job-status';if($job.data.done){break};Start-Sleep -Milliseconds 20}while([DateTime]::UtcNow -lt $deadline)
  Check ($job.data.state -eq 'succeeded' -and $job.data.collected -and (Test-Path -LiteralPath $path)) 'sender receives completed collected snapshot preview and PNG'
  $project=Join-Path $directory 'sender.rigmovie';$saved=Invoke-Movie 'movie-save' @{path=$project}
  Check ($saved.ok -and -not $saved.data.modified -and (Test-Path -LiteralPath $project)) 'sender explicitly saves production project'
  $opened=Invoke-Movie 'movie-open' @{path=$project}
  Check ($opened.ok -and -not $opened.data.modified -and $opened.data.time -eq 0) 'sender reopens production project clean at zero'
  $openedProject=Invoke-Movie 'movie-project'
  Check ($openedProject.data.outputTarget -eq $target) 'sender save reopen retains configured new output target'
  $rejected=$false
  try {$null=Invoke-Movie 'movie-update-project' @{projectId=$opened.data.projectId;revision=-1;title='stale'}}catch{$rejected=$true}
  Check $rejected 'sender preserves explicit stale movie revision for application rejection'
  $argsPath=Join-Path $directory 'cue.json';@{text='narrator:Argument file import.'} | ConvertTo-Json -Compress | Set-Content -LiteralPath $argsPath -Encoding utf8
  $fromFile=& $sender -ConnectionFile $connection -Command movie-import-script -ArgsFile $argsPath | ConvertFrom-Json
  Check ($fromFile.ok -and $fromFile.data.cueCount -eq 1) 'sender supports movie arguments from UTF8 file'
  $after=Invoke-Movie 'status'
  Check ($after.data.documentId -eq $before.data.documentId -and $after.data.revision -eq $before.data.revision -and $after.data.pipes.commandPipe -eq $before.data.pipes.commandPipe) 'sender movie operations preserve original RIGM revision and common pipe'
  @{success=$true;passed=$checks.Count;directory=$directory;checks=$checks.ToArray()} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'Win64\Validation\movie-sender-results.json') -Encoding utf8
}finally{
  Set-Content (Join-Path $hostDirectory 'stop.txt') 'stop'
  $hostProcess.WaitForExit(5000) | Out-Null
  $hostProcess.Dispose()
}
