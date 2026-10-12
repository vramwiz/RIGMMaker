#requires -Version 7.0
param([Parameter(Mandatory)][int]$TargetIndex, [Parameter(Mandatory)][string]$ImagePath)
$ErrorActionPreference = 'Stop'
$sessionRoot = $PSScriptRoot
$projectId = '{C36C2A85-DD8A-4DDE-8A7D-D5072CF41A98}'
$connectionFile = 'C:\Users\zan12\Documents\RIGMMaker\Exchange\workspace-13364.json'
$sender = 'D:\DelphiProg\RIGMMaker\Win64\Working\Research-20261011\Invoke-RigmWorkspace.ps1'
$target = @(Get-Content -LiteralPath (Join-Path $sessionRoot 'requested-targets.json') -Raw | ConvertFrom-Json)[$TargetIndex]
function Invoke-Pipe([string]$Command, [hashtable]$Arguments) {
    $json = $Arguments | ConvertTo-Json -Depth 32 -Compress
    (& $sender -ConnectionFile $connectionFile -Command $Command -ArgsJson $json -TimeoutMs 15000 | ConvertFrom-Json).data
}
function Get-Context {
    $status = Invoke-Pipe 'app-script-status' @{}
    if ($status.projectId -ne $projectId) { throw 'Active project changed; delivery stopped.' }
    $offset = 0
    if ($target.id -ne 'common-background') { $offset = [Math]::Max(0, [int]$target.sceneNumber - 1) }
    $page = Invoke-Pipe 'app-script-scenes' @{projectId=$projectId; revision=$status.revision; offset=$offset}
    if ($target.id -eq 'common-background') { $row = $page.background }
    else { $row = @($page.rows | Where-Object id -eq $target.id)[0] }
    if (-not $row) {
        $offset = 0
        do {
            $page = Invoke-Pipe 'app-script-scenes' @{projectId=$projectId; revision=$status.revision; offset=$offset}
            $row = @($page.rows | Where-Object id -eq $target.id)[0]
            $offset = $page.nextOffset
        } while (-not $row -and $page.hasMore)
    }
    if (-not $row) { throw 'Target scene no longer exists.' }
    @{status=$status; row=$row; revision=$page.revision}
}
$context = Get-Context
$row = $context.row
if ($row.imageApproved) { throw 'Target was approved; delivery stopped.' }
if ($row.imageRequest.requestId -ne $target.imageRequest.requestId -or -not $row.imageRequest.current -or $row.imageRequest.state -ne 'pending') { throw 'Image request changed or is no longer pending.' }
$source = Get-Item -LiteralPath $ImagePath
$hash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$relativePath = 'Exchange/' + (Split-Path $sessionRoot -Leaf) + '/' + $source.Name
$exchangePath = Join-Path 'C:\Users\zan12\Documents\RIGMMaker' $relativePath
[IO.Directory]::CreateDirectory((Split-Path $exchangePath -Parent)) | Out-Null
if (Test-Path -LiteralPath $exchangePath) {
    if ((Get-FileHash -LiteralPath $exchangePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Exchange filename already has different content.' }
} else { Copy-Item -LiteralPath $source.FullName -Destination $exchangePath }
if ((Get-FileHash -LiteralPath $exchangePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Exchange copy hash mismatch.' }
$arguments = @{projectId=$projectId; revision=$context.revision; sceneId=$target.id; requestId=$target.imageRequest.requestId; path=$relativePath; sha256=$hash; provenance='external-generated'}
$arguments | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $sessionRoot ('delivery-{0:00}-args.json' -f $TargetIndex)) -Encoding utf8
$adopt = Invoke-Pipe 'app-script-adopt-scene-image' $arguments
$adopt | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $sessionRoot ('delivery-{0:00}-response.json' -f $TargetIndex)) -Encoding utf8
$after = Get-Context
$afterRow = $after.row
if ($afterRow.imageRequest.requestId -ne $target.imageRequest.requestId -or $afterRow.imageRequest.state -ne 'adopted') { throw 'Adoption state verification failed.' }
$managedPath = $afterRow.imagePath
if (-not [IO.Path]::IsPathRooted($managedPath)) { $managedPath = Join-Path 'C:\Users\zan12\Documents\RIGMMaker' $managedPath }
if ((Get-FileHash -LiteralPath $managedPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Managed image hash mismatch.' }
$record = [ordered]@{targetIndex=$TargetIndex; sceneId=$target.id; sceneNumber=$target.sceneNumber; title=$target.title; requestId=$target.imageRequest.requestId; sourcePath=$source.FullName; sha256=$hash; managedPath=$managedPath; imageRequestState=$afterRow.imageRequest.state; imageApproved=$afterRow.imageApproved; revision=$after.revision; deliveredAt=[DateTimeOffset]::Now.ToString('o')}
$record | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $sessionRoot ('delivery-{0:00}-verified.json' -f $TargetIndex)) -Encoding utf8
$record | ConvertTo-Json -Depth 32 -Compress
