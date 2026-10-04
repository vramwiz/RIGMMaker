#requires -Version 7.0
param([switch]$SkipApplicationBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $projectRoot 'Win64\Validation\IsolatedSettings\Run-Validation'
$validationRoot = Join-Path $projectRoot 'Win64\Validation'
$radVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path -LiteralPath $radVars)) { throw "Delphi environment not found: $radVars" }
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
$searchPaths = @('Tests','Source\Studio','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar',
    'Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD',
    'Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar',
    'Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
function Build-Checked([string]$Command, [string]$LogName) {
    $fullCommand = 'call "' + $radVars + '" && ' + $Command
    $output = & cmd.exe /d /s /c $fullCommand 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $validationRoot $LogName) -Encoding utf8
    $output | Write-Output
    if ($code -ne 0) { throw "Build failed: $LogName (exit $code)" }
}
function Check-Sender([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Sender integration failed: $Name" }
    $script:senderChecks.Add($Name)
    Write-Output "PASS: $Name"
}
Push-Location $projectRoot
try {
    if (-not $SkipApplicationBuild) {
        foreach ($configuration in @('Debug','Release')) {
            $exeDirectory = Join-Path $validationRoot $configuration
            New-Item -ItemType Directory -Path $exeDirectory -Force | Out-Null
            Build-Checked ('msbuild RIGMMaker.dproj /t:Build /p:Config=' + $configuration + ' /p:Platform=Win64 /p:DCC_ExeOutput="' + $exeDirectory + '" /v:minimal /nologo') ('build-' + $configuration + '.log')
        }
    }
    foreach ($testProgram in @('RigmTests','RigmControllerTests','RigmPsdTests','RigmClassificationTests','RigmOpenTests','RigmUiTests','RigmInteractionTests','RigmToolbarTests','RigmBoneTests','RigmApiTests','RigmPreviewTests')) {
        $dcuDirectory = Join-Path $validationRoot ($testProgram + 'Dcu')
        New-Item -ItemType Directory -Path $dcuDirectory -Force | Out-Null
        Build-Checked ('dcc64 -B -Q -U"' + $searchPaths + '" -E"' + $validationRoot + '" -N0"' + $dcuDirectory + '" Tests\' + $testProgram + '.dpr') ('build-' + $testProgram + '.log')
        $testExe = Join-Path $validationRoot ($testProgram + '.exe')
        $output = & $testExe ('--data-dir=' + (Join-Path $validationRoot 'UILibrary')) ('--pipe-dir=' + (Join-Path $validationRoot 'UIPipes')) 2>&1
        $code = $LASTEXITCODE
        $output | Set-Content -LiteralPath (Join-Path $validationRoot ($testProgram + '.log')) -Encoding utf8
        $output | Write-Output
        if ($code -ne 0) { throw "$testProgram failed (exit $code)" }
    }
    $senderDirectory = Join-Path $validationRoot 'Sender'
    New-Item -ItemType Directory -Path $senderDirectory -Force | Out-Null
    foreach ($name in @('ready.txt','stop.txt')) {
        $oldSignal = Join-Path $senderDirectory $name
        if (Test-Path -LiteralPath $oldSignal) { Remove-Item -LiteralPath $oldSignal }
    }
    $hostExe = Join-Path $validationRoot 'RigmTests.exe'
    $hostProcess = Start-Process -FilePath $hostExe -ArgumentList '--pipe-host' -PassThru -WindowStyle Hidden
    $senderChecks = [Collections.Generic.List[string]]::new()
    try {
        $readyPath = Join-Path $senderDirectory 'ready.txt'
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not (Test-Path -LiteralPath $readyPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
        if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Sender host did not become ready' }
        $connectionFile = (Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8).Trim()
        $senderPath = Join-Path $projectRoot '制作支援\パイプ\Send-RigmCommand.ps1'
        $status = & $senderPath -ConnectionFile $connectionFile -Command status | ConvertFrom-Json
        Check-Sender ($status.ok -and $status.data.page -eq 'layer') 'sender discovers active layer endpoint'
        $parts = & $senderPath -ConnectionFile $connectionFile -Command document -ArgsJson '{"section":"parts","limit":1}' | ConvertFrom-Json
        $partId = $parts.data.items[0].id
        Check-Sender ($parts.data.items.Count -eq 1 -and $partId) 'sender reads bounded part metadata'
        $arguments = @{id=$partId;name='sender integration rename'} | ConvertTo-Json -Compress
        $changed = & $senderPath -ConnectionFile $connectionFile -Command update-layer -ArgsJson $arguments | ConvertFrom-Json
        Check-Sender ($changed.ok -and $changed.data.revision -gt $status.data.revision) 'sender injects document id and current revision for edit'
        $completed = & $senderPath -ConnectionFile $connectionFile -Command mark-complete | ConvertFrom-Json
        Check-Sender ($completed.ok -and $completed.data.page -eq 'bone') 'sender receives completion response without source confirmation during page pipe rotation'
        $switched = & $senderPath -ConnectionFile $connectionFile -Command switch-page -ArgsJson '{"page":"layer"}' | ConvertFrom-Json
        Check-Sender ($switched.ok -and $switched.data.page -eq 'layer') 'sender switches page through common endpoint'
        $targetFile = Join-Path $senderDirectory ('saved-' + [Guid]::NewGuid().ToString('N') + '.rigm')
        $saved = & $senderPath -ConnectionFile $connectionFile -Command save -ArgsJson (@{path=$targetFile} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($saved.ok -and (Test-Path -LiteralPath $targetFile)) 'sender saves edited RIGM through application'
        $commandPipe = $status.data.pipes.commandPipe
        $schema = & $senderPath -ConnectionFile $connectionFile -Command schema | ConvertFrom-Json
        Check-Sender ($schema.ok -and $schema.data.commands.Count -eq 43) 'sender exposes all 43 command argument schemas'
        $summary = & $senderPath -PipeName $commandPipe -Command document -ArgsJson '{"section":"summary"}' | ConvertFrom-Json
        Check-Sender ($summary.ok -and $summary.data.width -eq 256 -and $summary.data.height -eq 320) 'fixed common pipe exposes document summary'
        $prepared = & $senderPath -PipeName $commandPipe -Command switch-page -ArgsJson '{"page":"bone","completeCurrent":true}' | ConvertFrom-Json
        $bones = & $senderPath -PipeName $commandPipe -Command document -ArgsJson '{"section":"bones","limit":1}' | ConvertFrom-Json
        $boneId = $bones.data.items[0].id
        $boneChanged = & $senderPath -PipeName $commandPipe -Command update-bone -ArgsJson (@{id=$boneId;name='sender root'} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($prepared.ok -and $boneChanged.ok -and $boneChanged.data.selectedId -eq $boneId) 'fixed common pipe edits bones after validated page switching'
        $prepared = & $senderPath -PipeName $commandPipe -Command switch-page -ArgsJson '{"page":"mesh","completeCurrent":true}' | ConvertFrom-Json
        Check-Sender ($prepared.ok -and $prepared.data.stages.bone -and $prepared.data.pipes.commandPipe -eq $commandPipe) 'fixed common pipe validates bone preparation and reaches mesh'
        $generated = & $senderPath -PipeName $commandPipe -Command generate-mesh -ArgsJson (@{id=$partId;grid=3} | ConvertTo-Json -Compress) | ConvertFrom-Json
        $meshId = $generated.data.selectedId
        $geometry = & $senderPath -PipeName $commandPipe -Command document -ArgsJson (@{section='mesh-vertices';id=$meshId;limit=50} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($generated.ok -and $geometry.data.total -eq 9 -and $geometry.data.items[0].weights.Count -gt 0) 'fixed common pipe generates vertices UV and automatic weights'
        $selected = & $senderPath -ConnectionFile $connectionFile -Command select-object -ArgsJson (@{id=$meshId} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($selected.ok -and $selected.data.selectedId -eq $meshId -and $selected.data.revision -eq $generated.data.revision) 'sender selects a mesh without changing document revision'
        $vertices = @(foreach ($index in @(0,2,6,8)) { $v=$geometry.data.items[$index]; @{x=$v.x;y=$v.y;u=$v.u;v=$v.v;weights=@(@{boneId=$boneId;value=1})} })
        $meshArguments = @{partId=$partId;vertices=$vertices;triangles=@(@{a=0;b=1;c=2},@{a=1;b=3;c=2})}
        $argsFile = Join-Path $senderDirectory 'set-mesh-args.json'
        $meshArguments | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $argsFile -Encoding utf8
        $configured = & $senderPath -ConnectionFile $connectionFile -Command set-mesh -ArgsFile $argsFile | ConvertFrom-Json
        $header = & $senderPath -ConnectionFile $connectionFile -Command document -ArgsJson (@{section='meshes';id=$meshId} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($configured.ok -and $header.data.items[0].vertexCount -eq 4 -and $configured.data.selectedId -eq $meshId) 'sender ArgsFile applies custom geometry without replacing stable mesh ID'
        $batchArgs = @{operations=@(@{command='update-mesh';args=@{id=$meshId;strength=0.75}},@{command='set-weights';args=@{id=$meshId;vertex=-1;weights=@(@{boneId=$boneId;value=1})}})}
        $batched = & $senderPath -PipeName $commandPipe -Command batch -ArgsJson ($batchArgs | ConvertTo-Json -Depth 12 -Compress) | ConvertFrom-Json
        Check-Sender ($batched.ok -and [int64]$batched.data.revision -eq [int64]$configured.data.revision + 1) 'fixed common pipe commits mesh batch once'
        $badRevision = $batched.data.revision
        $rejected = $false
        try { & $senderPath -PipeName $commandPipe -Command set-triangles -ArgsJson (@{id=$meshId;triangles=@(@{a=0;b=1;c=999})} | ConvertTo-Json -Depth 6 -Compress) | Out-Null } catch { $rejected=$true }
        $unchanged = & $senderPath -PipeName $commandPipe -Command status | ConvertFrom-Json
        Check-Sender ($rejected -and $unchanged.data.revision -eq $badRevision) 'sender surfaces invalid geometry rejection with unchanged revision'
        $undone = & $senderPath -PipeName $commandPipe -Command undo | ConvertFrom-Json
        $redone = & $senderPath -PipeName $commandPipe -Command redo | ConvertFrom-Json
        Check-Sender ($undone.ok -and $redone.ok -and [int64]$redone.data.revision -gt [int64]$undone.data.revision) 'sender supports common mesh undo and redo'
        $deleted = & $senderPath -PipeName $commandPipe -Command delete-mesh -ArgsJson (@{id=$meshId} | ConvertTo-Json -Compress) | ConvertFrom-Json
        $restored = & $senderPath -PipeName $commandPipe -Command undo | ConvertFrom-Json
        Check-Sender ($deleted.ok -and $restored.ok -and $restored.data.meshCount -eq $deleted.data.meshCount + 1) 'sender deletes and restores mesh through the common entry'
        $bundleStatus = & $senderPath -PipeName $commandPipe -Command status | ConvertFrom-Json
        $importFile = Join-Path $senderDirectory 'mesh-result.json'
        @{documentId=$bundleStatus.data.documentId;revision=$bundleStatus.data.revision;operations=@(@{command='set-mesh';args=$meshArguments})} | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $importFile -Encoding utf8
        $imported = & $senderPath -ConnectionFile $connectionFile -Command import -ArgsJson (@{path=$importFile} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($imported.ok -and $imported.data.selectedId -eq $meshId) 'sender imports atomic mesh result files on the mesh page'
        $preserved = & $senderPath -PipeName $commandPipe -Command generate-mesh -ArgsJson '{"grid":3,"replaceExisting":false}' | ConvertFrom-Json
        $header = & $senderPath -PipeName $commandPipe -Command document -ArgsJson (@{section='meshes';id=$meshId} | ConvertTo-Json -Compress) | ConvertFrom-Json
        Check-Sender ($preserved.ok -and $header.data.items[0].vertexCount -eq 4) 'sender missing-only generation preserves custom geometry'
        $validated = & $senderPath -PipeName $commandPipe -Command validate -ArgsJson '{"throughPage":"mesh","errorsOnly":true}' | ConvertFrom-Json
        Check-Sender ($validated.ok -and $validated.data.throughPageReady -and $validated.data.errorCount -eq 0) 'sender validates mesh data before completion'
        $finalSaved = & $senderPath -PipeName $commandPipe -Command save -ArgsJson (@{path=$targetFile} | ConvertTo-Json -Compress) | ConvertFrom-Json
        $zip = [IO.Compression.ZipFile]::OpenRead($targetFile)
        try {
            $entry=$zip.GetEntry('manifest.json'); $reader=[IO.StreamReader]::new($entry.Open(),[Text.Encoding]::UTF8)
            try { $roundtrip=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
        $roundtripMesh = $roundtrip.meshes | Where-Object {$_.id -eq $meshId}
        Check-Sender ($finalSaved.ok -and $roundtripMesh.vertices.Count -eq 4 -and $roundtripMesh.vertices[0].weights[0].boneId -eq $boneId) 'sender save reloads mesh geometry UV faces and weights from RIGM manifest'
        $preview = & $senderPath -PipeName $commandPipe -Command switch-page -ArgsJson '{"page":"preview","completeCurrent":true}' | ConvertFrom-Json
        Check-Sender ($preview.ok -and $preview.data.page -eq 'preview' -and $preview.data.pipes.commandPipe -eq $commandPipe) 'sender reaches preview using the same common pipe'
        @{success=$true;passed=$senderChecks.Count;checks=$senderChecks.ToArray()} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $senderDirectory 'results.json') -Encoding utf8
    } finally {
        'stop' | Set-Content -LiteralPath (Join-Path $senderDirectory 'stop.txt') -Encoding utf8
        $hostProcess.WaitForExit(5000) | Out-Null
        $hostProcess.Dispose()
    }
} finally { Pop-Location }
