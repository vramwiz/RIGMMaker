param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [switch]$Live
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$outputRoot = [IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $outputRoot) { throw 'Use a new validation output directory.' }
$binRoot = Join-Path $outputRoot 'bin'
$dcuRoot = Join-Path $outputRoot 'dcu'
$runRoot = Join-Path $outputRoot 'run'
New-Item -ItemType Directory -Path $binRoot,$dcuRoot,$runRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AiExpressionsCheck.dpr') -Destination (Join-Path $outputRoot 'AiExpressionsCheck.dpr')
Copy-Item -LiteralPath (Join-Path $repoRoot 'RIGMMaker.res') -Destination (Join-Path $outputRoot 'AiExpressionsCheck.res')
[xml]$project = Get-Content -LiteralPath (Join-Path $repoRoot 'RIGMMaker.dproj') -Raw -Encoding UTF8
$ns = [Xml.XmlNamespaceManager]::new($project.NameTable)
$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$search = $project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object { $_ -and -not $_.StartsWith('$(') }
$paths = @($search | ForEach-Object { Join-Path $repoRoot $_ }) + @($PSScriptRoot)
$flags = @('-B','-Q',('-E'+$binRoot),('-N0'+$dcuRoot),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-DDEBUG','-$O-','-$R+','-$Q+','-$C+')
$previousEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(932)
    $buildOutput = & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags (Join-Path $outputRoot 'AiExpressionsCheck.dpr') 2>&1
    $buildExit = $LASTEXITCODE
    $buildOutput | Set-Content -LiteralPath (Join-Path $outputRoot 'build.log') -Encoding UTF8
} finally { [Console]::OutputEncoding = $previousEncoding }
if ($buildExit -ne 0) { $buildOutput | Select-Object -Last 12; throw 'AI expression verification build failed.' }
$arguments = '"'+$runRoot+'" --data-root "'+(Join-Path $runRoot 'OwnedData')+'" --settings-dir "'+(Join-Path $runRoot 'Settings')+'"'
if ($Live) { $arguments += ' --live' }
$owned = Start-Process -FilePath (Join-Path $binRoot 'AiExpressionsCheck.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runRoot 'stdout.txt') -RedirectStandardError (Join-Path $runRoot 'stderr.txt')
Write-Output ('Owned validation PID: '+$owned.Id)
$deadline = [DateTime]::UtcNow.AddSeconds(360)
try {
    while (-not $owned.WaitForExit(250)) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Owned AI validation timed out.' }
    }
    Get-Content -LiteralPath (Join-Path $runRoot 'stdout.txt') -Tail 14
    $report = Get-Content -LiteralPath (Join-Path $runRoot 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Output ('Checks: '+$report.checks.Count+'; exit: '+$owned.ExitCode)
    if ($owned.ExitCode -ne 0 -or -not $report.success) { throw $report.error }
} finally {
    if (-not $owned.HasExited) { Stop-Process -Id $owned.Id }
}
