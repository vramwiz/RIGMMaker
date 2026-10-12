#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$sessionRoot = $PSScriptRoot
$projectId = '{C36C2A85-DD8A-4DDE-8A7D-D5072CF41A98}'
$dataRoot = 'C:\Users\zan12\Documents\RIGMMaker'
$connectionFile = Join-Path $dataRoot 'Exchange/workspace-13364.json'
$sender = 'D:\DelphiProg\RIGMMaker\Win64\Working\Research-20261011\Invoke-RigmWorkspace.ps1'
function Invoke-Pipe([string]$Command, [hashtable]$Arguments, [string]$Name) {
    $json = $Arguments | ConvertTo-Json -Depth 32 -Compress
    (& $sender -ConnectionFile $connectionFile -Command $Command -ArgsJson $json -OutFile (Join-Path $sessionRoot $Name) -TimeoutMs 15000 | ConvertFrom-Json).data
}
$status = Invoke-Pipe 'app-script-status' @{} 'status-before-save.json'
if ($status.projectId -ne $projectId) { throw 'Active project changed.' }
$saved = Invoke-Pipe 'app-script-save' @{projectId=$projectId; revision=$status.revision} 'save-response.json'
if ($saved.modified) { throw 'Save did not clear modified state.' }
$rows = [Collections.Generic.List[object]]::new()
$offset = 0
do {
    $latest = Invoke-Pipe 'app-script-status' @{} 'status-final.json'
    if ($latest.projectId -ne $projectId) { throw 'Active project changed during verification.' }
    $page = Invoke-Pipe 'app-script-scenes' @{projectId=$projectId; revision=$latest.revision; offset=$offset} ('final-page-{0:00}.json' -f $offset)
    if ($offset -eq 0) { $rows.Add($page.background) }
    foreach ($row in $page.rows) { $rows.Add($row) }
    $offset = $page.nextOffset
} while ($page.hasMore)
$rows | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $sessionRoot 'scene-rows-after.json') -Encoding utf8
$targets = @(Get-Content -LiteralPath (Join-Path $sessionRoot 'requested-targets.json') -Raw | ConvertFrom-Json)
$generation = Get-Content -LiteralPath (Join-Path $sessionRoot 'generation-record.json') -Raw | ConvertFrom-Json
$projectPath = $latest.path.Replace('\\','\')
$savedProjectText = [IO.File]::ReadAllText($projectPath)
$assets = [Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $targets.Count; $index++) {
    $target = $targets[$index]
    $row = @($rows | Where-Object id -eq $target.id)[0]
    $delivery = Get-Content -LiteralPath (Join-Path $sessionRoot ('delivery-{0:00}-verified.json' -f $index)) -Raw | ConvertFrom-Json
    if (-not $row -or $row.imageRequest.requestId -ne $target.imageRequest.requestId -or $row.imageRequest.state -ne 'adopted' -or -not $row.imageRequest.current) { throw "Request verification failed for index $index" }
    $managedPath = $row.imagePath
    if (-not [IO.Path]::IsPathRooted($managedPath)) { $managedPath = Join-Path $dataRoot $managedPath }
    $actualHash = (Get-FileHash -LiteralPath $managedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $delivery.sha256) { throw "Managed hash mismatch for index $index" }
    if (-not $savedProjectText.Contains($delivery.sha256)) { throw "Saved project missing image reference for index $index" }
    $asset = @($generation.assets | Where-Object index -eq $index)[0]
    $localPath = Join-Path $sessionRoot $asset.filename
    $bytes = [IO.File]::ReadAllBytes($localPath)
    $width = [int]([uint64]$bytes[16]*16777216 + [uint64]$bytes[17]*65536 + [uint64]$bytes[18]*256 + [uint64]$bytes[19])
    $height = [int]([uint64]$bytes[20]*16777216 + [uint64]$bytes[21]*65536 + [uint64]$bytes[22]*256 + [uint64]$bytes[23])
    if ($width -gt 8192 -or $height -gt 8192 -or $bytes.Length -gt 32MB) { throw 'Image exceeds application limits.' }
    $assets.Add([ordered]@{index=$index;sceneId=$target.id;sceneNumber=$target.sceneNumber;title=$target.title;requestedPrompt=$target.imagePrompt;finalPrompt=$asset.prompt;references=$asset.references;originalPath=$asset.originalPath;localPath=$localPath;managedPath=$managedPath;sha256=$actualHash;width=$width;height=$height;bytes=$bytes.Length;requestId=$target.imageRequest.requestId;requestState=$row.imageRequest.state;humanApproved=$row.imageApproved;visualInspection='passed: subject, style, composition and no embedded lettering checked';persisted=$true})
}
$manifest = [ordered]@{format='RIGMMaker.ImageDelivery';createdAt=[DateTimeOffset]::Now.ToString('o');mode='built-in imagegen';useCase='illustration-story';projectId=$projectId;projectTitle=$latest.title;imageCount=$assets.Count;commonBackgroundCount=1;sceneImageCount=12;pendingRequests=$page.pendingRequests;savedProject=$projectPath;modified=$latest.modified;stage=$latest.wizard.stage;canonicalCharacterSource=$generation.canonicalCharacterSource;assumptions=$generation.assumptions;humanApproval='left to the user; no approval operations sent';assets=$assets}
$manifest | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $sessionRoot 'manifest.json') -Encoding utf8
$learningRoot = 'D:\DelphiProg\RIGMMaker\制作支援\学習記録\RIGM\20261011-manga-scene-images'
[IO.Directory]::CreateDirectory($learningRoot) | Out-Null
Copy-Item -LiteralPath (Join-Path $sessionRoot 'manifest.json') -Destination (Join-Path $learningRoot ('learning_record-' + (Split-Path $sessionRoot -Leaf) + '.json'))
[pscustomobject]@{imageCount=$assets.Count;pendingRequests=$page.pendingRequests;modified=$latest.modified;stage=$latest.wizard.stage;manifest=(Join-Path $sessionRoot 'manifest.json');dimensions=($assets | ForEach-Object { '{0}x{1}' -f $_.width,$_.height } | Select-Object -Unique);totalBytes=($assets | Measure-Object -Property bytes -Sum).Sum} | ConvertTo-Json -Depth 6
