param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output = [IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $output) { throw 'Use a new validation output directory' }
$bin = Join-Path $output 'bin'; $dcu = Join-Path $output 'dcu'; $runRoot = Join-Path $output 'run'; $httpRoot = Join-Path $output 'http'
New-Item -ItemType Directory -Path $bin,$dcu,$runRoot,$httpRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CastingFeedbackCheck.dpr') -Destination (Join-Path $output 'CastingFeedbackCheck.dpr')
Copy-Item -LiteralPath (Join-Path $repo 'RIGMMaker.res') -Destination (Join-Path $output 'CastingFeedbackCheck.res')
[xml]$project = Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns = [Xml.XmlNamespaceManager]::new($project.NameTable); $ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$search = $project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')}
$paths = @($search | ForEach-Object {Join-Path $repo $_})+@($PSScriptRoot)
$flags = @('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-DDEBUG','-$O-','-$R+','-$Q+','-$C+')
Push-Location $output
try {
    & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags (Join-Path $output 'CastingFeedbackCheck.dpr') *> (Join-Path $output 'build.log')
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 15; throw 'Feedback probe build failed' }
} finally { Pop-Location }
# An owned inert executable prevents fallback to the user's installed engine.
$inertEngine = Join-Path $bin 'run.exe'; [IO.File]::WriteAllBytes($inertEngine,[byte[]]@(0))
[IO.File]::WriteAllText((Join-Path $bin 'VoicevoxEngine.ini'),("[VOICEVOX]`r`nEngineExe="+$inertEngine+"`r`n"),[Text.UTF8Encoding]::new($true))
$server = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList ('-NoProfile -File "'+(Join-Path $PSScriptRoot 'VoiceCatalogFixture.ps1')+'" -Root "'+$httpRoot+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $httpRoot 'stdout.txt') -RedirectStandardError (Join-Path $httpRoot 'stderr.txt')
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $serverInfo = Join-Path $httpRoot 'server.json'
    while (-not (Test-Path -LiteralPath $serverInfo)) {
        if ($server.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Owned HTTP fixture did not start' }
        Start-Sleep -Milliseconds 50
    }
    $port = (Get-Content -LiteralPath $serverInfo -Raw | ConvertFrom-Json).port
    $arguments = '"'+$runRoot+'" http://127.0.0.1:'+$port+' "'+(Join-Path $httpRoot 'speaker-count.txt')+'" --data-root "'+(Join-Path $runRoot 'OwnedData')+'" --settings-dir "'+(Join-Path $runRoot 'Settings')+'"'
    $probe = Start-Process -FilePath (Join-Path $bin 'CastingFeedbackCheck.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runRoot 'stdout.txt') -RedirectStandardError (Join-Path $runRoot 'stderr.txt')
    $deadline = [DateTime]::UtcNow.AddSeconds(50)
    while (-not $probe.WaitForExit(250)) { if ([DateTime]::UtcNow -gt $deadline) { throw 'Owned feedback probe timed out' } }
    Get-Content -LiteralPath (Join-Path $runRoot 'stdout.txt') -Tail 14
    $report = Get-Content -LiteralPath (Join-Path $runRoot 'result.json') -Raw | ConvertFrom-Json
    Write-Output ('Feedback checks='+$report.checks.Count+'; exit='+$probe.ExitCode)
    if ($probe.ExitCode -ne 0 -or $report.error) { throw $report.error }
} finally {
    if ($probe -and -not $probe.HasExited) { Stop-Process -Id $probe.Id }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id }
}
