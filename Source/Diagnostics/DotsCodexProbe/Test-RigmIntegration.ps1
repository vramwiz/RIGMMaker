param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$Exe)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$outputRoot=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $outputRoot){throw 'Choose a new output directory.'}
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$Exe=[IO.Path]::GetFullPath($Exe)
$sender=Join-Path $repo '制作支援\パイプ\Send-RigmDotsCommand.ps1'
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Name){if(-not $Value){throw ('FAILED: '+$Name)};$checks.Add($Name)}
# Build an actual Low AppContainer client into this run; no past result files are required.
$helperRoot=Join-Path $outputRoot 'AppContainerClient'
New-Item -ItemType Directory -Path $helperRoot | Out-Null
$helperBuild=@(& 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' -B -Q ('-E'+$helperRoot) ('-N0'+$helperRoot) (Join-Path $PSScriptRoot 'AppContainerPipeClient.dpr') 2>&1)
if($LASTEXITCODE -ne 0){$helperBuild|Select-Object -Last 4;throw 'AppContainer helper build failed.'}
$helperBuild|Set-Content -LiteralPath (Join-Path $helperRoot 'build.log') -Encoding UTF8
& icacls.exe $helperRoot /grant '*S-1-15-2-1:(OI)(CI)RX' '*S-1-15-2-2:(OI)(CI)RX' | Out-Null
if($LASTEXITCODE -ne 0){throw 'AppContainer helper read ACL failed.'}
$helper=Join-Path $helperRoot 'AppContainerPipeClient.exe'
function Legacy([string]$Connection,[string]$Command,[hashtable]$Arguments=@{},[string]$RequestId=([guid]::NewGuid().ToString())){
    $info=Get-Content -LiteralPath $Connection -Raw -Encoding UTF8|ConvertFrom-Json
    $client=[IO.Pipes.NamedPipeClientStream]::new('.',$info.commandPipe,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    try{
        $client.Connect(5000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
        $payload=[Text.Encoding]::UTF8.GetBytes((@{schemaVersion=1;requestId=$RequestId;command=$Command;args=$Arguments}|ConvertTo-Json -Depth 24 -Compress))
        $write=$client.WriteAsync($payload,0,$payload.Length);if(-not $write.Wait(10000)){throw 'Legacy write timeout'}
        $buffer=[byte[]]::new(65536);$read=$client.ReadAsync($buffer,0,$buffer.Length)
        if(-not $read.Wait(10000)){throw 'Legacy read timeout'}
        $response=[Text.Encoding]::UTF8.GetString($buffer,0,$read.GetAwaiter().GetResult())|ConvertFrom-Json
        if($response.requestId -cne $RequestId){throw 'Legacy id mismatch'}
        return $response
    }finally{$client.Dispose()}
}
Add-Type -AssemblyName System.Drawing
$fixture=[Drawing.Bitmap]::new(32,24);$stream=[IO.MemoryStream]::new()
try{$fixture.Save($stream,[Drawing.Imaging.ImageFormat]::Png);$imageBytes=$stream.ToArray()}finally{$stream.Dispose();$fixture.Dispose()}
$imageBase64=[Convert]::ToBase64String($imageBytes)
$normalPipes=Join-Path $env:LOCALAPPDATA 'RIGMMaker\pipes'
foreach($mode in @('codex','dots')){
    $root=Join-Path $outputRoot $mode
    $dataRoot=Join-Path $root 'Data'
    $settings=Join-Path $root 'Settings'
    $pipeDir=Join-Path $root 'LegacyPipes'
    New-Item -ItemType Directory -Path $root,$pipeDir | Out-Null
    $launch='--communication-mode '+$mode+' --data-root "'+$dataRoot+'" --settings-dir "'+$settings+'" --pipe-dir="'+$pipeDir+'"'
    $owned=Start-Process -FilePath $Exe -ArgumentList $launch -PassThru -WindowStyle Hidden
    try{
        $deadline=[DateTime]::UtcNow.AddSeconds(20)
        $discovery=$null
        while(-not $discovery){
            if($owned.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'App failed to publish discovery.'}
            if(Test-Path -LiteralPath (Join-Path $dataRoot 'Exchange')){
                $mask=if($mode -eq 'dots'){'dots-*.json'}else{'workspace-*.json'}
                $discovery=Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Exchange') -Filter $mask|Select-Object -First 1
            }
            if(-not $discovery){Start-Sleep -Milliseconds 100}
        }
        $script:currentMode=$mode;$script:currentConnection=$discovery.FullName
        function Call([string]$Command,[hashtable]$Arguments=@{},[string]$Id=([guid]::NewGuid().ToString())){
            if($script:currentMode -eq 'dots'){
                & $sender -ConnectionFile $script:currentConnection -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Depth 24 -Compress) -RequestId $Id
            }else{Legacy $script:currentConnection $Command $Arguments $Id}
        }
        $info=Get-Content -LiteralPath $discovery.FullName -Raw -Encoding UTF8|ConvertFrom-Json
        Check ($info.communicationMode -eq $mode) ($mode+' discovery mode')
        $status=Call 'app-status'
        Check $status.ok ($mode+' existing workspace status')
        Check ($status.data.dataRoot -ceq $dataRoot) ($mode+' isolated data root')
        $schema=Call 'schema'
        Check ($schema.ok -and $schema.data.workspace.'script-ai-status') ($mode+' shared command schema includes AI controls')
        $draft=Call 'app-script-new'
        Check $draft.ok ($mode+' existing new-script operation')
        $revision=$draft.data.revision
        $args=@{projectId=$draft.data.projectId;revision=$revision;title='Dots統合の通信テスト'}
        $title=Call 'app-script-set-title' $args 'set-title'
        Check ($title.ok -and $title.data.title -eq 'Dots統合の通信テスト') ($mode+' shared text editing')
        if($mode -eq 'dots'){
            $repeated=Call 'app-script-set-title' $args 'set-title'
            Check ($repeated.ok -and $repeated.data.revision -eq $title.data.revision) 'Dots replay does not edit twice'
            Check (-not (Call 'app-script-set-title' (@{projectId=$draft.data.projectId;revision=$revision;title='different'}) 'set-title').ok) 'Dots id conflict rejected'
        }
        Check (-not (Call 'app-script-set-title' @{projectId=$draft.data.projectId;revision=$revision;title='stale'}).ok) ($mode+' stale revision rejected')
        $saved=Call 'app-script-save' @{projectId=$title.data.projectId;revision=$title.data.revision}
        Check $saved.ok ($mode+' existing save operation')
        $invalidAuto=Call 'app-auto-start' @{text=''}
        Check ($invalidAuto.ok -and $invalidAuto.data.state -eq 'invalid' -and -not $invalidAuto.data.productionStarted -and -not $invalidAuto.data.jobId) ($mode+' incomplete automation input does not start production')
        # Only the owned test data receives fixtures; exercise latest-per-type and dry copy.
        $seedFile=Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Projects') -Recurse -Filter '*.rigmovie'|Select-Object -First 1
        $seed=Get-Content -LiteralPath $seedFile.FullName -Raw -Encoding UTF8
        $fixtureIds=@{}
        foreach($case in @(
            @{name='manga-old';type='manga-introduction';stamp='2026-01-01T00:00:00.000Z';state='complete'},
            @{name='manga-latest';type='manga-introduction';stamp='2026-02-01T00:00:00.000Z';state='complete'},
            @{name='anime';type='anime-review';stamp='2026-03-01T00:00:00.000Z';state='complete'},
            @{name='input';type='manga-introduction';stamp='2026-04-01T00:00:00.000Z';state='in-progress'},
            @{name='failed-automation';type='manga-introduction';stamp='2026-05-01T00:00:00.000Z';state='complete'})){
            $fixture=$seed|ConvertFrom-Json
            $fixture.projectId='{'+[guid]::NewGuid().ToString().ToUpperInvariant()+'}'
            $fixture.title=$case.name;$fixture.scriptWizard.titleInput=$case.name
            $fixture.scriptWizard.stage='title';$fixture.scriptWizard.titleStatus=$case.state
            $fixture.scriptWizard.scriptType=$case.type;$fixture.scriptWizard.updatedAt=$case.stamp
            if($case.name -eq 'failed-automation'){$fixture.scriptWizard|Add-Member -NotePropertyName automation -NotePropertyValue @{jobId='owned-fixture';state='failed'}}
            $folder=Join-Path (Join-Path $dataRoot 'Projects') $fixture.projectId
            New-Item -ItemType Directory -Path $folder|Out-Null
            $fixture|ConvertTo-Json -Depth 64|Set-Content -LiteralPath (Join-Path $folder 'project.rigmovie') -Encoding UTF8
            $fixtureIds[$case.name]=$fixture.projectId
        }
        $sourceHashes=@{}
        Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Projects') -Recurse -Filter '*.rigmovie'|ForEach-Object{$sourceHashes[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName).Hash}
        $sources=Call 'app-auto-sources' @{scriptType='manga-introduction'}
        Check ($sources.ok -and $sources.data.selected.projectId -eq $fixtureIds['manga-latest']) ($mode+' latest completed manga selected over newer anime and input')
        $anime=Call 'app-auto-sources' @{scriptType='anime-review'}
        Check ($anime.ok -and $anime.data.selected.projectId -eq $fixtureIds['anime']) ($mode+' latest anime selected independently')
        $sourceCheck=Call 'app-auto-source-check' @{scriptType='manga-introduction';projectId=$fixtureIds['manga-latest']}
        Check ($sourceCheck.ok -and $sourceCheck.data.eligible -and $sourceCheck.data.selected -and $sourceCheck.data.copyValidated -and -not $sourceCheck.data.saved) ($mode+' chosen source passes GUI copy validation without saving')
        $older=Call 'app-auto-source-check' @{scriptType='manga-introduction';projectId=$fixtureIds['manga-old']}
        Check ($older.ok -and $older.data.eligible -and -not $older.data.selected -and $older.data.copyValidated) ($mode+' older eligible source distinguished from selected latest')
        foreach($path in $sourceHashes.Keys){Check ((Get-FileHash -LiteralPath $path).Hash -ceq $sourceHashes[$path]) ($mode+' source verification preserves project bytes')}
        Check (@(Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Projects') -Recurse -Filter '*.rigmovie').Count -eq $sourceHashes.Count) ($mode+' source verification creates no saved copy')
        $ai=Call 'app-script-ai-status'
        Check ($ai.ok -and -not $ai.data.expressions.busy -and -not $ai.data.images.busy) ($mode+' idle AI status')
        $beforeAi=Call 'app-script-status'
        $badAi=Call 'app-script-ai-images-start' @{projectId=$beforeAi.data.projectId;revision=$beforeAi.data.revision}
        Check (-not $badAi.ok) ($mode+' AI start obeys existing stage checks')
        Check (-not (Call 'app-script-ai-expressions-start' @{projectId='wrong';revision=0}).ok) ($mode+' AI start checks project id')
        if($mode -eq 'dots'){
            Check ((Call 'ping').data.message -eq 'pong') 'Dots ping/pong'
            $text="日本語`n絵文字😀"
            Check ((Call 'echo' @{text=$text}).data.text -ceq $text) 'Dots text transport exact match'
            $uploaded=Call 'image.put' @{base64=$imageBase64}
            Check ($uploaded.ok -and $uploaded.data.width -eq 32) 'Dots production validator accepts uploaded image'
            $downloaded=Call 'image.get' @{imageId=$uploaded.data.imageId}
            Check ($downloaded.ok -and $downloaded.data.base64 -ceq $imageBase64) 'Dots production image byte round trip'
            Check (-not (Call 'image.get' @{imageId='..\outside'}).ok) 'Dots cannot read arbitrary file paths'
            Check (-not (Call 'image.put' @{base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('invalid'))}).ok) 'Dots production validator rejects non-image'
            $client=[IO.Pipes.NamedPipeClientStream]::new('.',$info.pipeName,[IO.Pipes.PipeDirection]::InOut)
            try{
                $client.Connect(5000)
                $bytes=[Text.Encoding]::UTF8.GetBytes('{"version":1,"id":"no-token","command":"ping","args":{}}'+"`n")
                $client.Write($bytes,0,$bytes.Length)
                $reader=[IO.StreamReader]::new($client,[Text.Encoding]::UTF8,$false,4096,$true)
                try{$unauthorized=$reader.ReadLine()|ConvertFrom-Json}finally{$reader.Dispose()}
                Check ($unauthorized.error.code -eq 'unauthorized') 'Dots missing token rejected'
            }finally{$client.Dispose()}
            Check (@(Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Exchange') -Filter 'workspace-*.json').Count -eq 0) 'Dots mode has no legacy workspace discovery'
            # Two real rotating Low AppContainers use the production endpoint.
            if(Test-Path -LiteralPath $helper){
                $script:productionConnection=$info
                $launcherSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-AppContainerAccess.ps1') -Raw
                $csharp=[regex]::Match($launcherSource,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
                if(-not ('DotsTestAppContainer' -as [type])){Add-Type -TypeDefinition $csharp}
                $sids=@()
                foreach($case in @('production-first','production-rotated')){
                    $raw=''
                    $exit=[DotsTestAppContainer]::Run($helper,('"'+$info.pipeName+'" "'+$info.accessToken+'" "'+$case+'"'),(Split-Path -Parent $helper),$false,[ref]$raw)
                    $report=$raw|ConvertFrom-Json
                    Check ($exit -eq 0 -and $report.response.ok -and $report.response.data.message -eq 'pong') ($case+' real Low AppContainer ping')
                    $sids+=$report.appContainerSid
                }
                Check ($sids[0] -ne $sids[1]) 'Production pipe accepts rotating AppContainer SID'
            }else{throw 'Build the AppContainer test helper first.'}
        }else{
            Check (@(Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Exchange') -Filter 'dots-*.json').Count -eq 0) 'Codex mode has no Dots discovery'
        }
        $legacyEditor=Call 'legacy-status'
        Check $legacyEditor.ok ($mode+' character editor uses existing model')
        $psdEditor=Call 'psd-status'
        Check $psdEditor.ok ($mode+' PSD editor uses existing model')
        if($mode -eq 'dots'){
            Check (@(Get-ChildItem -LiteralPath $pipeDir -Filter '*.json').Count -eq 0) 'Dots mode does not publish character editor pipes'
            Check (@(Get-ChildItem -LiteralPath (Join-Path $dataRoot 'Exchange') -Filter 'psd-*.json').Count -eq 0) 'Dots mode does not publish PSD pipes'
        }
        $published=@([IO.Directory]::GetFiles('\\.\pipe\')|Where-Object {$_ -match ('RIGMMaker\..*\b'+$owned.Id+'\b')})
        if($mode -eq 'dots'){
            Check ($published.Count -eq 1 -and $published[0] -match 'RIGMMaker\.Dots\.') 'Dots mode listens on exactly one Dots pipe and no legacy pipes'
        }else{
            Check (@($published|Where-Object {$_ -match 'RIGMMaker\.Dots\.'}).Count -eq 0 -and $published.Count -gt 0) 'Codex mode listens on legacy pipes and no Dots pipe'
        }
        $runText=[IO.File]::ReadAllText((Join-Path $repo '自動制作\台本\通し試験.txt'))
        $run=Call 'app-auto-start' @{text=$runText}
        Check ($run.ok -and $run.data.state -eq 'running' -and $run.data.jobId) ($mode+' automation start returns asynchronous job id')
        Check (-not (Call 'app-script-new').ok) ($mode+' production prevents competing pipe edits')
        Check (-not (Call 'app-auto-start' @{text=$runText}).ok) ($mode+' duplicate production start rejected')
        $cancel=Call 'app-auto-cancel' @{jobId=$run.data.jobId}
        Check $cancel.ok ($mode+' automation cancellation accepted')
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do{
            $runStatus=Call 'app-auto-status' @{jobId=$run.data.jobId}
            if($runStatus.data.state -ne 'running'){break}
            Start-Sleep -Milliseconds 100
        }while([DateTime]::UtcNow -lt $deadline)
        Check ($runStatus.ok -and $runStatus.data.state -eq 'cancelled' -and -not $runStatus.data.productionCompleted) ($mode+' cancellation reaches terminal state without false completion')
        foreach($path in $sourceHashes.Keys){Check ((Get-FileHash -LiteralPath $path).Hash -ceq $sourceHashes[$path]) ($mode+' automation cancellation preserves sources')}
    }finally{
        if(-not $owned.HasExited){Stop-Process -Id $owned.Id}
        $owned.Dispose()
    }
}
@{success=$true;checks=$checks.ToArray()}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
'Passed '+$checks.Count+' production integration checks. Evidence: '+$outputRoot
