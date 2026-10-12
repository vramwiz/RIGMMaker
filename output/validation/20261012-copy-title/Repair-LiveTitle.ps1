$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$invoke=Join-Path $PSScriptRoot '../../imagegen/20261012-scene-images/Invoke-Live.ps1'
$expected='{0C6B3396-4F42-46DE-8A5F-EF3A0DD84AEF}'
function Read-State { & $invoke -Command 'app-script-status' }
function Send-Change($command,$extra) {
    $state=Read-State
    if($state.projectId -ne $expected){throw 'Active project changed'}
    $args=@{projectId=$state.projectId;revision=$state.revision}
    foreach($key in $extra.Keys){$args[$key]=$extra[$key]}
    & $invoke -Command $command -ArgsJson ($args | ConvertTo-Json -Depth 60 -Compress) -OutputFile (Join-Path $PSScriptRoot ($command+'-reply.json'))
}
$state=Read-State
if($state.projectId -ne $expected -or $state.modified -or $state.wizard.stage -ne 'scenes'){throw 'Unexpected active state; keep input intact'}
Copy-Item -LiteralPath $state.path -Destination (Join-Path $PSScriptRoot 'project-immediately-before.rigmovie')
$originalStage=$state.wizard.stage
$args=@{projectId=$state.projectId;revision=$state.revision} | ConvertTo-Json -Compress
$closing=& $invoke -Command 'app-script-closing' -ArgsJson $args
if($closing.closing.draft.title -ne 'それは、降り積もる雪のような。'){throw 'Closing title already changed'}
Send-Change 'app-script-set-stage' @{stage='closing'} | Out-Null
$state=Read-State
$closing=& $invoke -Command 'app-script-closing' -ArgsJson (@{projectId=$state.projectId;revision=$state.revision} | ConvertTo-Json -Compress)
$closing.closing.draft.title=$state.title
Send-Change 'app-script-set-closing' @{draft=$closing.closing.draft} | Out-Null
Send-Change 'app-script-complete-closing' @{} | Out-Null
Send-Change 'app-script-set-stage' @{stage=$originalStage} | Out-Null
$state=Read-State
$state | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'status-after-repair.json') -Encoding UTF8
Copy-Item -LiteralPath $state.path -Destination (Join-Path $PSScriptRoot 'project-after.rigmovie')
[pscustomobject]@{projectId=$state.projectId;revision=$state.revision;title=$state.title;stage=$state.wizard.stage;modified=$state.modified;voiceReady=$state.voiceReady;scenesReady=$state.scenesReady}
