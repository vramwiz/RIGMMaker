param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [Parameter(Mandatory=$true)][string]$DataRoot,
    [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$outputRoot=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $outputRoot){throw 'Choose a new output directory.'}
New-Item -ItemType Directory -Path $outputRoot|Out-Null
$Exe=[IO.Path]::GetFullPath($Exe);$DataRoot=[IO.Path]::GetFullPath($DataRoot)
$sender=Join-Path $repo '制作支援\パイプ\Send-RigmDotsCommand.ps1'
$before=@{}
if(Test-Path -LiteralPath (Join-Path $DataRoot 'Projects')){
    Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Projects') -Recurse -Filter '*.rigmovie'|ForEach-Object{$before[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Name){if(-not $Value){throw ('FAILED: '+$Name)};$checks.Add($Name)}
$settings=Join-Path $outputRoot 'Settings'
$owned=Start-Process -FilePath $Exe -ArgumentList ('--communication-mode dots --data-root "'+$DataRoot+'" --settings-dir "'+$settings+'"') -PassThru -WindowStyle Hidden
$connectionFile=$null
try{
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    while(-not $connectionFile){
        if($owned.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Production app startup failed.'}
        $exchange=Join-Path $DataRoot 'Exchange'
        if(Test-Path -LiteralPath $exchange){$found=Get-ChildItem -LiteralPath $exchange -Filter ('dots-'+$owned.Id+'-*.json')|Select-Object -First 1;if($found){$connectionFile=$found.FullName}}
        if(-not $connectionFile){Start-Sleep -Milliseconds 100}
    }
    function Call([string]$Command,[hashtable]$Arguments=@{}){
        $reply=& $sender -ConnectionFile $connectionFile -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Depth 24 -Compress)
        if(-not $reply.ok){throw ($reply.error|ConvertTo-Json -Compress)}
        return $reply.data
    }
    Check ((Call 'ping').message -eq 'pong') 'Production Dots pipe ping/pong'
    $text=@'
作品名：自動制作の受付試験
種類：漫画
ニコニコ漫画の作品URL：

*背景
画像：人物のいない白い背景

*紹介
画像：白い背景の青い円
表示：
本文：
これは自動制作の受付試験です。
字幕とセリフを一致させます。

*総評
ストーリー：4
キャラクター：4.5
作画：4
演出・テンポ：3.5
世界観・設定：4
本文：
読み間違いやイントネーションの違いは許容します。
'@
    [IO.File]::WriteAllText((Join-Path $outputRoot 'input.txt'),$text,[Text.UTF8Encoding]::new($false))
    $blank=Call 'app-auto-validate' @{text=''}
    Check (-not $blank.valid -and $blank.issues.Count -ge 5) 'All missing fields returned together'
    $blank|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $outputRoot 'invalid-input.json') -Encoding UTF8
    $valid=Call 'app-auto-validate' @{text=$text}
    Check ($valid.valid -and $valid.message) 'Complete input receives positive acknowledgement'
    Check ($valid.data.scenes.Count -eq 1 -and $valid.data.summary.items.Count -eq 5) 'Background scenes and fixed summary axes parsed separately'
    Check ($valid.data.scenes[0].body -match "字幕とセリフを一致させます。") 'Multiline dialogue preserved'
    Check (Call 'app-auto-validate' @{text=$text.Replace('種類：漫画','種類：アニメ')}).valid 'Anime type accepted separately'
    Check (-not (Call 'app-auto-validate' @{text=$text.Replace('種類：漫画','種類：アニメ／漫画')}).valid) 'Ambiguous type rejected'
    Check (-not (Call 'app-auto-validate' @{text=$text.Replace('ストーリー：4','ストーリー：6')}).valid) 'Out-of-range score rejected'
    Check (-not (Call 'app-auto-validate' @{text=$text.Replace('ストーリー：4','ストーリー：4' + "`n" + 'ストーリー：5')}).valid) 'Duplicate summary score rejected'
    $beforeInvalid=Call 'app-auto-check' @{text=''}
    Check ($beforeInvalid.state -eq 'invalid' -and -not $beforeInvalid.jobId) 'Invalid input does not start a check job'
    $sources=Call 'app-auto-sources' @{scriptType='manga-introduction'}
    $sources|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $outputRoot 'sources.json') -Encoding UTF8
    $unknownSource=Call 'app-auto-source-check' @{scriptType='manga-introduction';projectId=[guid]::NewGuid().ToString()}
    Check (-not $unknownSource.found -and -not $unknownSource.eligible -and -not $unknownSource.saved) 'Unknown source is not selected or created'
    $sourceReports=@()
    foreach($entry in @($sources.candidates)+@($sources.excluded)){
        if(-not $entry.projectId){continue}
        $report=Call 'app-auto-source-check' @{scriptType='manga-introduction';projectId=$entry.projectId}
        Check ($report.found -and -not $report.saved -and $report.source.projectId -eq $entry.projectId) 'Specific source inspected without saving a copy'
        if($entry.reason){Check (-not $report.eligible -and -not $report.selected -and $report.message) 'Excluded source returns explicit eligibility response'}
        if($report.selected){Check ($report.eligible -and $report.copyValidated -and $sources.selected.projectId -eq $entry.projectId) 'Latest source passes the same copy validation as GUI'}
        if($entry.scriptType -eq 'manga-introduction'){
            $wrongType=Call 'app-auto-source-check' @{scriptType='anime-review';projectId=$entry.projectId}
            Check ($wrongType.found -and -not $wrongType.eligible -and -not $wrongType.selected) 'Manga source is not selected for anime'
        }
        $sourceReports+=$report
    }
    $sourceReports|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $outputRoot 'source-checks.json') -Encoding UTF8
    $accepted=Call 'app-auto-check' @{text=$text}
    Check ($accepted.state -eq 'running' -and $accepted.jobId -and -not $accepted.productionStarted) 'Check accepted with job id and no false production start'
    $accepted|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $outputRoot 'accepted.json') -Encoding UTF8
    $sequence=0;$events=[Collections.Generic.List[object]]::new();$deadline=[DateTime]::UtcNow.AddSeconds(15)
    do{
        $status=Call 'app-auto-status' @{jobId=$accepted.jobId;afterSequence=$sequence}
        foreach($event in $status.events){Check ($event.sequence -gt $sequence) 'New stage event sequence';$sequence=$event.sequence;$events.Add($event)}
        if($status.state -ne 'running'){break}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    Check ($status.state -ne 'running') 'Check job reaches a terminal state'
    Check (-not $status.productionStarted) 'Preflight never reports MP4 production success'
    $status|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $outputRoot 'final-status.json') -Encoding UTF8
    $events.ToArray()|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $outputRoot 'events.json') -Encoding UTF8
    $noNewEvents=Call 'app-auto-status' @{jobId=$accepted.jobId;afterSequence=$sequence}
    Check ($noNewEvents.events.Count -eq 0) 'Event cursor avoids duplicate notifications'
    foreach($path in $before.Keys){Check ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $before[$path]) 'Original saved project unchanged'}
    $after=@(Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Projects') -Recurse -Filter '*.rigmovie')
    Check ($after.Count -eq $before.Count) 'No new project created by preflight'
    @{success=$true;state=$status.state;productionCompleted=$false;issues=$status.issues;checks=$checks.ToArray()}|
        ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
    'Checks passed: '+$checks.Count+'; production state: '+$status.state
    $status.issues|Format-Table field,code,message -Wrap
    # Close only the verification-owned idle process; no user process is stopped.
}catch{
    @{success=$false;error=$_.ToString();checks=$checks.ToArray()}|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
    throw
}finally{
    if(-not $owned.HasExited){Stop-Process -Id $owned.Id}
    $owned.Dispose()
}
