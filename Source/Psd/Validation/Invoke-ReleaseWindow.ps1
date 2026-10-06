$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-ReleaseWindow-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters') -Force|Out-Null
$fixture=Join-Path $root 'Characters\registered.psdchar'
Copy-Item -LiteralPath 'D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psdchar' -Destination $fixture
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-WorkspacePipe.ps1'),[Text.Encoding]::UTF8)
$start=$source.IndexOf('function Call(');$end=$source.IndexOf('function PsdArgs(')
. ([scriptblock]::Create($source.Substring($start,$end-$start)))
$exe=Join-Path $repo 'Win64\Validation\IntegratedPsd\Release\RIGMMaker.exe'
$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"')) -WindowStyle Hidden -PassThru
$closed=$false
try{
 $connection=Join-Path $root ('Exchange\workspace-'+$process.Id+'.json');$deadline=[DateTime]::UtcNow.AddSeconds(12)
 while(-not(Test-Path -LiteralPath $connection)){if($process.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Release main did not start'};Start-Sleep -Milliseconds 100}
 $script:pipeName=(Get-Content -LiteralPath $connection -Encoding UTF8 -Raw|ConvertFrom-Json).commandPipe
 $startupState=Call 'app-status';if($startupState.page -ne 'home' -or $startupState.openDocuments -ne 0){throw 'Incorrect startup state'}
 $out=Join-Path $repo 'Win64\Validation\PsdStudio'
 & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path (Join-Path $out 'release-home-native.png')
 $lib=Call 'app-library';if(-not $lib.characters[0].readyForScript){throw 'Registered completed PSD is unavailable'}
 [void](Call 'app-edit-character' @{path=$fixture})
 $s=Call 'psd-status';if(-not $s.readyForScript){throw 'Completed edit did not reopen correctly'}
 [void](Call 'psd-set-view' @{sessionId=$s.sessionId;revision=$s.revision;expression=([string][char]0x697D+[char]0x3057+[char]0x307F);motion='breathe';autoBlink=$false})
 & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path (Join-Path $out 'release-psd-native.png')
 $schema=Call 'schema';if(-not $schema.movie.commands){throw 'Common schema does not expose existing movie commands'}
 $movieState=Call 'movie-status'
 [void](Call 'movie-add-character' @{projectId=$movieState.projectId;revision=$movieState.revision;character=@{id='completed-psd';name='PSD';file=$fixture;renderFormat='psd'}})
 $project=Call 'movie-project';$actor=$project.characters|Where-Object {$_.id -eq 'completed-psd'}
 if(-not $actor -or $actor.expressions.joy.psdExpression -ne ([string][char]0x697D+[char]0x3057+[char]0x307F)){throw 'Completed fun expression is missing from script actor presets'}
 $movieState=Call 'movie-status';[void](Call 'movie-save' @{projectId=$movieState.projectId;revision=$movieState.revision;path=(Join-Path $root 'completed-actor.rigmovie')})
 [void](Call 'movie-open-ui')
 & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path (Join-Path $out 'release-movie-native.png')
 [void](Call 'legacy-status')
 & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path (Join-Path $out 'release-legacy-native.png')
 [void](Call 'app-switch-page' @{page='home'})
 [void]$process.CloseMainWindow();if(-not $process.WaitForExit(15000)){throw 'Release validation app remains active'};$closed=$true
 @{root=$root;exe=$exe;normalExit=($process.ExitCode -eq 0);completedCharacterEditable=$true;completedCharacterListed=$true;completedScriptActorAdded=$true;funActorPreset=$true;movieSchemaExposed=$true;method='native PrintWindow of owned release main form; no physical mouse'}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $out 'release-window-result.json')
}finally{if(-not $closed -and -not $process.HasExited){Write-Warning ('Owned release validation process '+$process.Id+' remains active')}}
