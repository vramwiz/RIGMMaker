$ErrorActionPreference='Stop'
$invoke=Join-Path $PSScriptRoot 'Invoke-Live.ps1'
$expected='{0C6B3396-4F42-46DE-8A5F-EF3A0DD84AEF}'
function State { & $invoke -Command 'movie-status' }
$state=State
if($state.projectId -ne $expected -or $state.busy -or $state.playing){throw 'Unexpected current project or busy state'}
$path=$state.fileName
Copy-Item -LiteralPath $path -Destination (Join-Path $PSScriptRoot 'project-disk-before-save.rigmovie')
$state | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'status-before.json') -Encoding UTF8
# Save through the existing app command to retain all unsaved input before reading the current cues.
& $invoke -Command 'movie-save' -ArgsJson (@{projectId=$expected;revision=$state.revision} | ConvertTo-Json -Compress) | Out-Null
$state=State
if($state.projectId -ne $expected -or $state.fileName -ne $path){throw 'Current project changed'}
Copy-Item -LiteralPath $path -Destination (Join-Path $PSScriptRoot 'project-live-before.rigmovie')
$project=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
$summaryId=$project.scriptWizard.summaryData.sceneId
$cues=@($project.cues | Where-Object {$_.scene -eq $summaryId})
if($cues.Count -ne 6 -or @($cues | Where-Object {$_.subtitle -ne ''}).Count){throw 'Summary contents changed; keep current subtitles'}
foreach($cue in $cues){
    $state=State
    if($state.projectId -ne $expected -or $state.busy -or $state.playing){throw 'Project changed or user began playback'}
    $args=@{projectId=$expected;revision=$state.revision;id=$cue.id;subtitle=$cue.text}
    & $invoke -Command 'movie-update-subtitle' -ArgsJson ($args | ConvertTo-Json -Depth 5 -Compress) -OutputFile (Join-Path $PSScriptRoot ('subtitle-reply-'+$cue.id.Trim('{}')+'.json')) | Out-Null
}
$state=State
& $invoke -Command 'movie-save' -ArgsJson (@{projectId=$expected;revision=$state.revision} | ConvertTo-Json -Compress) | Out-Null
Copy-Item -LiteralPath $path -Destination (Join-Path $PSScriptRoot 'project-live-after.rigmovie')
$state=State
$state | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'status-after.json') -Encoding UTF8
[pscustomobject]@{projectId=$state.projectId;revision=$state.revision;modified=$state.modified;summarySubtitlesRestored=$cues.Count;time=$state.time}
