param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [Parameter(Mandatory=$true)][string]$DataRoot,
    [Parameter(Mandatory=$true)][string]$InputFile,
    [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$OutDir=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $OutDir){throw 'Choose a new evidence directory.'}
New-Item -ItemType Directory -Path $OutDir|Out-Null
$sender=Join-Path $repo '制作支援\パイプ\Send-RigmDotsCommand.ps1'
$before=@{}
Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Projects') -Filter '*.rigmovie' -Recurse|ForEach-Object{$before[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName).Hash}
$settings=Join-Path $OutDir 'Settings'
$owned=Start-Process -FilePath ([IO.Path]::GetFullPath($Exe)) -ArgumentList ('--communication-mode dots --data-root "'+[IO.Path]::GetFullPath($DataRoot)+'" --settings-dir "'+$settings+'"') -PassThru -WindowStyle Hidden
$jobId=$null;$terminal=$false
try{
    $deadline=[DateTime]::UtcNow.AddSeconds(20);$connection=$null
    while(-not $connection){
        if($owned.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'App startup failed.'}
        $connection=Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Exchange') -Filter ('dots-'+$owned.Id+'-*.json')|Select-Object -First 1
        if(-not $connection){Start-Sleep -Milliseconds 100}
    }
    function Call([string]$Command,[hashtable]$Arguments){
        $reply=& $sender -ConnectionFile $connection.FullName -Command $Command -ArgsJson ($Arguments|ConvertTo-Json -Depth 32 -Compress)
        if(-not $reply.ok){throw ($reply.error|ConvertTo-Json -Compress)}
        $reply.data
    }
    $inputText=[IO.File]::ReadAllText([IO.Path]::GetFullPath($InputFile))
    $started=Call 'app-auto-start' @{text=$inputText}
    $started|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $OutDir 'accepted.json') -Encoding UTF8
    if($started.state -ne 'running' -or -not $started.jobId){throw ('Start rejected: '+($started|ConvertTo-Json -Depth 20 -Compress))}
    $jobId=$started.jobId;$sequence=0;$events=[Collections.Generic.List[object]]::new()
    $deadline=[DateTime]::UtcNow.AddMinutes(65)
    do{
        if($owned.HasExited){throw 'App exited during production.'}
        $state=Call 'app-auto-status' @{jobId=$jobId;afterSequence=$sequence}
        foreach($event in $state.events){
            if($event.sequence -le $sequence){throw 'Event sequence repeated.'}
            $sequence=$event.sequence;$events.Add($event)
            Write-Output ($event.sequence.ToString()+' '+$event.stage+' '+$event.state+' '+$event.message)
        }
        $state|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $OutDir 'latest-status.json') -Encoding UTF8
        if($state.state -ne 'running'){$terminal=$true;break}
        if([DateTime]::UtcNow -gt $deadline){throw 'Production polling timeout.'}
        Start-Sleep -Seconds 2
    }while($true)
    $events.ToArray()|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $OutDir 'events.json') -Encoding UTF8
    foreach($path in $before.Keys){if((Get-FileHash -LiteralPath $path).Hash -cne $before[$path]){throw ('Original project changed: '+$path)}}
    if($state.state -ne 'completed' -or -not $state.productionCompleted){throw ('Production stopped: '+$state.message)}
    foreach($key in @('videoPath','textPath')){if(-not(Test-Path -LiteralPath $state.$key)){throw ('Missing artifact: '+$key)}}
    $movie=Get-Content -LiteralPath $state.projectPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($cue in $movie.cues){if($cue.text -cne $cue.subtitle){throw 'Subtitle differs from source dialogue.'}}
    $bodyScenes=@($movie.scenes|Where-Object {$_.title -in @('青い円','赤い四角')})
    if($bodyScenes.Count -ne 2){throw 'Input scene boundaries or titles differ.'}
    @{success=$true;state=$state.state;jobId=$jobId;sourceProjectsUnchanged=$before.Count;videoPath=$state.videoPath;textPath=$state.textPath;projectPath=$state.projectPath;eventCount=$events.Count}|
        ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
}catch{
    @{success=$false;error=$_.ToString();jobId=$jobId}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
    throw
}finally{
    # Keep an active production app on polling failure. Close only our terminal, idle app.
    if($terminal -and -not $owned.HasExited){Stop-Process -Id $owned.Id}
    $owned.Dispose()
}