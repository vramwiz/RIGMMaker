param([ValidateSet('Debug','Release')][string]$Config)
$ErrorActionPreference = 'Stop'
$repo = 'D:\DelphiProg\RIGMMaker'
$root = Join-Path $PSScriptRoot $Config
$bin = Join-Path $root 'bin'
$dcu = Join-Path $root 'dcu'
New-Item -ItemType Directory -Path $root,$bin,$dcu -Force | Out-Null
[xml]$project = Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns = [Xml.XmlNamespaceManager]::new($project.NameTable)
$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$searchNode = $project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns)
$searchNode.InnerText = (($searchNode.InnerText -split ';' | ForEach-Object {
    if ($_ -and -not $_.StartsWith('$(')) { Join-Path $repo $_ } else { $_ }
}) -join ';')
foreach ($reference in $project.SelectNodes('//m:DCCReference',$ns)) {
    $reference.SetAttribute('Include',(Join-Path $repo $reference.GetAttribute('Include')))
}
foreach ($node in $project.SelectNodes('//m:DCC_ExeOutput',$ns)) { $node.InnerText = $bin }
foreach ($node in $project.SelectNodes('//m:DCC_DcuOutput',$ns)) { $node.InnerText = $dcu }
$project.SelectSingleNode('//m:RigmFFmpegRuntimeSource',$ns).InnerText = Join-Path $repo 'Runtime\FFmpeg'
$projectPath = Join-Path $root 'RIGMMaker.dproj'
$project.Save($projectPath)
$main = [IO.File]::ReadAllText((Join-Path $repo 'RIGMMaker.dpr'))
$main = [regex]::Replace($main,"in '([^']+)'",[Text.RegularExpressions.MatchEvaluator]{
    param($match)
    "in '"+(Join-Path $repo $match.Groups[1].Value)+"'"
})
[IO.File]::WriteAllText((Join-Path $root 'RIGMMaker.dpr'),$main,[Text.UTF8Encoding]::new($true))
Copy-Item -LiteralPath (Join-Path $repo 'RIGMMaker.res') -Destination (Join-Path $root 'RIGMMaker.res')
$batch = '@echo off'+"`r`n"+
    'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"'+"`r`n"+
    'msbuild "'+$projectPath+'" /t:Build /p:Config='+$Config+' /p:Platform=Win64 /v:minimal /nologo'+"`r`n"+
    'exit /b %errorlevel%'+"`r`n"
$batchPath = Join-Path $root 'build.cmd'
[IO.File]::WriteAllText($batchPath,$batch,[Text.Encoding]::ASCII)
& $env:ComSpec /d /c $batchPath *> (Join-Path $root 'build.log')
$code = $LASTEXITCODE
Get-Content -LiteralPath (Join-Path $root 'build.log') -Tail 3
if ($code -ne 0) { throw ('Product '+$Config+' build failed: '+$code) }
Get-FileHash -LiteralPath (Join-Path $bin 'RIGMMaker.exe') -Algorithm SHA256 | Format-List Path,Hash
