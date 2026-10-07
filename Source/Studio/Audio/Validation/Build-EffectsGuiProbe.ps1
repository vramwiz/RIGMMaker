param(
  [string]$OutDir=(Join-Path ([IO.Path]::GetTempPath()) ('rigm-effects-gui-'+[guid]::NewGuid().ToString('N').Substring(0,8))),
  [ValidateSet('Debug','Release')][string]$Configuration='Debug',
  [switch]$Run
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$outRoot=[IO.Path]::GetFullPath($OutDir)
$repoPrefix=$repoRoot.TrimEnd('\')+'\'
if($outRoot.Equals($repoRoot,[StringComparison]::OrdinalIgnoreCase) -or $outRoot.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)){
  throw 'Choose a separate OutDir outside the repository; generated EXE/DCU/fixtures must stay isolated.'
}
$tempOutDir=Join-Path $outRoot ('b-'+[guid]::NewGuid().ToString('N'))
$binRoot=Join-Path $tempOutDir 'bin'
$dcuRoot=Join-Path $tempOutDir 'dcu'
$runRoot=Join-Path $tempOutDir 'run'
if($runRoot.Length -gt 130){throw 'Choose a shorter OutDir: the workspace JSON and atomic temporary files require the isolated run root to be at most 130 characters.'}
$resource=Join-Path $repoRoot 'RIGMMaker.res'
$probe=Join-Path $PSScriptRoot 'EffectsGuiProbe.dpr'
if(-not (Test-Path -LiteralPath $resource)){throw 'Application resource RIGMMaker.res is required for the copied production style and manifest.'}
if(-not (Test-Path -LiteralPath $probe)){throw 'EffectsGuiProbe.dpr is missing.'}
$compilerCommand=Get-Command 'dcc64.exe' -ErrorAction SilentlyContinue
if($compilerCommand){$compiler=$compilerCommand.Source}else{$compiler='C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'}
if(-not (Test-Path -LiteralPath $compiler)){throw 'Delphi dcc64 compiler is unavailable.'}
New-Item -ItemType Directory -Path $tempOutDir,$binRoot,$dcuRoot -Force | Out-Null
$copiedProbe=Join-Path $tempOutDir 'EffectsGuiProbe.dpr'
Copy-Item -LiteralPath $probe -Destination $copiedProbe
Copy-Item -LiteralPath $resource -Destination (Join-Path $tempOutDir 'EffectsGuiProbe.res')
$sourceRoot=Join-Path $repoRoot 'Source'
$sourcePaths=@($sourceRoot)+@(Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse | ForEach-Object {$_.FullName})
$flags=@('-B','-Q',('-E'+$binRoot),('-N0'+$dcuRoot),('-U'+($sourcePaths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data')
if($Configuration -eq 'Debug'){$flags+=@('-DDEBUG','-$O-','-$R+','-$Q+','-$C+')}else{$flags+=@('-DRELEASE','-$O+','-$R-','-$Q-')}
$buildLog=Join-Path $tempOutDir 'build.log'
Push-Location $tempOutDir
try {
  & $compiler @flags $copiedProbe *> $buildLog
  if($LASTEXITCODE -ne 0){throw ('Owned GUI probe compilation failed; see '+$buildLog)}
} finally {Pop-Location}
$exe=Join-Path $binRoot 'EffectsGuiProbe.exe'
Write-Output ('Owned probe executable: '+$exe)
Write-Output ('Build log: '+$buildLog)
if($Run){
  New-Item -ItemType Directory -Path $runRoot | Out-Null
  $stdout=Join-Path $runRoot 'stdout.txt'
  $stderr=Join-Path $runRoot 'stderr.txt'
  # Launch only the copied test executable. It owns its window/workspace/PCM/settings/pipe.
  $ownedProbe=Start-Process -FilePath $exe -ArgumentList ('"'+$runRoot+'"') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $ownedProbe.WaitForExit()
  Write-Output ('Owned probe PID '+$ownedProbe.Id+' exited '+$ownedProbe.ExitCode)
  Write-Output ('Probe reports and native VCL client PNGs: '+$runRoot)
  if($ownedProbe.ExitCode -ne 0){throw ('Owned GUI probe failed; see '+$stdout)}
}
