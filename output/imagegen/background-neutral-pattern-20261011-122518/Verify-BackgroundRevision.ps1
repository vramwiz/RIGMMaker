#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$sessionRoot = $PSScriptRoot
$projectId = '{C36C2A85-DD8A-4DDE-8A7D-D5072CF41A98}'
$dataRoot = 'C:\Users\zan12\Documents\RIGMMaker'
$sender = 'D:\DelphiProg\RIGMMaker\Win64\Working\Research-20261011\Invoke-RigmWorkspace.ps1'
$connectionFile = Join-Path $dataRoot 'Exchange/workspace-13364.json'
function Invoke-Pipe([string]$Command,[hashtable]$Arguments,[string]$FileName) {
    $json = $Arguments | ConvertTo-Json -Depth 32 -Compress
    $parameters = @{ConnectionFile=$connectionFile;Command=$Command;ArgsJson=$json;TimeoutMs=15000}
    if ($FileName) { $parameters.OutFile = Join-Path $sessionRoot $FileName }
    (& $sender @parameters | ConvertFrom-Json).data
}
$before = @(Get-Content -LiteralPath (Join-Path $sessionRoot 'scene-rows-before.json') -Raw | ConvertFrom-Json)
$status = Invoke-Pipe 'app-script-status' @{} 'status-before-save.json'
if ($status.projectId -ne $projectId) { throw 'Active project changed.' }
$rows = [Collections.Generic.List[object]]::new()
$offset = 0
do {
    $page = Invoke-Pipe 'app-script-scenes' @{projectId=$projectId;revision=$status.revision;offset=$offset} ('verified-page-{0:00}.json' -f $offset)
    if ($offset -eq 0) { $background = $page.background; $rows.Add($background) }
    foreach ($row in $page.rows) { $rows.Add($row) }
    $offset = $page.nextOffset
} while ($page.hasMore)
$preserved = 0
foreach ($original in ($before | Where-Object id -ne 'common-background')) {
    $current = @($rows | Where-Object id -eq $original.id)[0]
    if (-not $current) { throw 'A confirmed scene disappeared.' }
    foreach ($property in @('imageApproved','imageApprovalKey','imageEditEpoch','image','title','imagePrompt','description','imageFeedback','displayMode')) {
        if (($original.$property | ConvertTo-Json -Depth 16 -Compress) -ne ($current.$property | ConvertTo-Json -Depth 16 -Compress)) { throw "Confirmed item changed: $($original.title), $property" }
    }
    $preserved++
}
$delivery = Get-Content -LiteralPath (Join-Path $sessionRoot 'delivery-00-verified.json') -Raw | ConvertFrom-Json
if ($background.imageRequest.requestId -ne $delivery.requestId -or $background.imageRequest.state -ne 'adopted' -or -not $background.imageRequest.current) { throw 'Background adoption verification failed.' }
$saved = Invoke-Pipe 'app-script-save' @{projectId=$projectId;revision=$status.revision} 'save-response.json'
$finalStatus = Invoke-Pipe 'app-script-status' @{} 'status-after-save.json'
if ($finalStatus.projectId -ne $projectId -or $finalStatus.modified) { throw 'Save verification failed.' }
$finalPage = Invoke-Pipe 'app-script-scenes' @{projectId=$projectId;revision=$finalStatus.revision;offset=0} 'background-after-save.json'
$path = $finalPage.background.imagePath
if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $dataRoot $path }
$hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $delivery.sha256) { throw 'Saved background hash mismatch.' }
$projectPath = $finalStatus.path.Replace('\\','\')
if (-not [IO.File]::ReadAllText($projectPath).Contains($hash)) { throw 'Saved project missing new background.' }
$generated = Get-Content -LiteralPath (Join-Path $sessionRoot 'generation-record.json') -Raw | ConvertFrom-Json
$bytes = [IO.File]::ReadAllBytes($delivery.sourcePath)
$width = [int]([uint64]$bytes[16]*16777216+[uint64]$bytes[17]*65536+[uint64]$bytes[18]*256+[uint64]$bytes[19])
$height = [int]([uint64]$bytes[20]*16777216+[uint64]$bytes[21]*65536+[uint64]$bytes[22]*256+[uint64]$bytes[23])
$manifest = [ordered]@{format='RIGMMaker.BackgroundRevision';createdAt=[DateTimeOffset]::Now.ToString('o');mode='built-in imagegen';projectId=$projectId;sceneId='common-background';requestId=$delivery.requestId;requestedPrompt=$finalPage.background.imagePrompt;finalPrompt=$generated.prompt;references=$generated.references;originalPath=$generated.originalPath;localPath=$delivery.sourcePath;managedPath=$path;sha256=$hash;width=$width;height=$height;requestedWidth=1920;requestedHeight=1080;requestState=$finalPage.background.imageRequest.state;humanApproved=$finalPage.background.imageApproved;humanApprovalOperations=0;confirmedItemsPreserved=$preserved;visualInspection='passed: neutral low-contrast geometric pattern only; no people, recognizable objects, setting, food, lettering or thematic imagery';saved=$true;stage=$finalStatus.wizard.stage}
$manifest | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $sessionRoot 'manifest.json') -Encoding utf8
$learningRoot = 'D:\DelphiProg\RIGMMaker\制作支援\学習記録\RIGM\20261011-manga-scene-images'
[IO.Directory]::CreateDirectory($learningRoot) | Out-Null
Copy-Item -LiteralPath (Join-Path $sessionRoot 'manifest.json') -Destination (Join-Path $learningRoot ('learning_record-' + (Split-Path $sessionRoot -Leaf) + '.json'))
[pscustomobject]@{saved=$true;confirmedItemsPreserved=$preserved;requestState=$manifest.requestState;humanApproved=$manifest.humanApproved;stage=$manifest.stage;image=$path;manifest=(Join-Path $sessionRoot 'manifest.json')} | ConvertTo-Json
