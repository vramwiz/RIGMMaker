$ErrorActionPreference = 'Stop'
$taskDir = $PSScriptRoot
$sender = 'D:\DelphiProg\AviUtl2Plugin\Syncroh2\Doc\PSDArtEditor\Send-ArtCommand.ps1'
$pipeInfo = Get-Content -LiteralPath "$taskDir\connection.json" -Raw | ConvertFrom-Json
$manifest = @(Get-Content -LiteralPath "$taskDir\manifest.json" -Raw | ConvertFrom-Json)
$log = [System.Collections.Generic.List[object]]::new()

function Send-Command([string]$command, [hashtable]$payload) {
    $reply = & $sender -PipeName $pipeInfo.pipeName -Command $command -ArgsJson ($payload | ConvertTo-Json -Compress) -TimeoutMs 60000 | ConvertFrom-Json
    if (!$reply.ok) { throw ($reply | ConvertTo-Json -Depth 20) }
    return $reply
}

function Assert-Exclusive($doc, [string]$selectedName) {
    foreach ($kind in @('eyes', 'brows', 'mouths')) {
        $names = @($manifest | Where-Object kind -eq $kind | ForEach-Object name)
        $members = @($doc.data.layers | Where-Object name -In $names)
        if ($members.Count -ne $names.Count) { throw "Missing $kind members" }
        $visible = @($members | Where-Object visible)
        if ($visible.Count -ne 1) { throw "Exclusive visibility failed: $kind" }
        $parent = @($doc.data.layers | Where-Object id -eq $members[0].parentId)
        if ($parent.Count -ne 1 -or !$parent[0].visible) { throw "Group hidden: $kind" }
    }
    if ($selectedName -and !($doc.data.layers | Where-Object name -eq $selectedName).visible) { throw "Target hidden: $selectedName" }
    foreach ($name in @('両目（原画画素）', '両眉（原画画素）', '口（原画画素）', '元画像（比較用・原寸）')) {
        if (($doc.data.layers | Where-Object name -eq $name).visible) { throw "Archive visible: $name" }
    }
    if (!($doc.data.layers | Where-Object name -eq 'ベース（背景透過・目眉口補完）').visible) { throw 'Base hidden' }
}

$doc = Send-Command 'document' @{}
Assert-Exclusive $doc ''
foreach ($item in @($manifest | Where-Object { !$_.original }) + @($manifest | Where-Object original)) {
    $doc = Send-Command 'document' @{}
    $layer = @($doc.data.layers | Where-Object name -eq $item.name)
    if ($layer.Count -ne 1) { throw "Ambiguous layer: $($item.name)" }
    $reply = Send-Command 'select-part' @{ documentId = $doc.data.documentId; ifRevision = [string]$doc.data.revision; layerId = $layer[0].id }
    $after = Send-Command 'document' @{}
    Assert-Exclusive $after $item.name
    $log.Add(@{ name = $item.name; revisionBefore = $doc.data.revision; revisionAfter = $after.data.revision; exclusive = $true; response = $reply })
}
$doc = Send-Command 'document' @{}
foreach ($item in @($manifest | Where-Object original)) {
    if (!($doc.data.layers | Where-Object name -eq $item.name).visible) { throw "Original not restored: $($item.name)" }
}
@{ result = 'passed'; selectionCount = $log.Count; testedGeneratedCount = 21; originalRestored = $true; checks = $log } | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath "$taskDir\selection-verification.json" -Encoding utf8
$save = Send-Command 'save' @{ documentId = $doc.data.documentId; ifRevision = [string]$doc.data.revision }
$save | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath "$taskDir\save-response.json" -Encoding utf8
$doc = Send-Command 'document' @{}
$doc | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath "$taskDir\saved-document.json" -Encoding utf8
$status = Send-Command 'status' @{}
$status | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath "$taskDir\saved-status.json" -Encoding utf8
Assert-Exclusive $doc ''
if ($status.data.modified -or $status.data.busy) { throw 'Save unfinished' }
Copy-Item -LiteralPath $status.data.fileName -Destination "$taskDir\blonde_expressions_review.psd"
@{ result = 'passed'; selections = $log.Count; generatedStates = 21; originalRestored = $true; saved = $true; managedPsd = $status.data.fileName; reviewPsd = "$taskDir\blonde_expressions_review.psd" } | ConvertTo-Json
