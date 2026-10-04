#requires -Version 7.0
param(
  [Parameter(Mandatory=$true)][string]$ExePath,
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [string]$Label='product'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$exe=[IO.Path]::GetFullPath($ExePath)
$project=[IO.Path]::GetFullPath($ProjectPath)
if(-not $exe.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Executable must belong to this workspace'}
if(-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $project)){throw 'Executable/project missing'}
$directory=Join-Path $root ('Win64\Validation\ProductionStartup\'+$Label+'-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$settings=Join-Path $directory 'settings'
$library=Join-Path $directory 'library'
$pipes=Join-Path $directory 'pipes'
New-Item -ItemType Directory -Path $settings,$library,$pipes -Force|Out-Null
$sender=Join-Path $root '制作支援\パイプ\Send-RigmCommand.ps1'
$before=(Get-FileHash -LiteralPath $project -Algorithm SHA256).Hash
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name);Write-Host ('PASS: '+$Name)}
$process=Start-Process -FilePath $exe -ArgumentList @('"--settings-dir='+$settings+'"','"--data-dir='+$library+'"','"--pipe-dir='+$pipes+'"') -WindowStyle Hidden -PassThru
$connection='';$report=@{success=$false;label=$Label;executable=$exe;exeSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;processId=$process.Id;directory=$directory;sourceProject=$project;sourceSha256=$before;humanGuiVisualVerification=$false;forcedTermination=$false}
try {
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  do {
    if($process.HasExited){throw ('Application exited before pipe startup: '+$process.ExitCode)}
    $files=@(Get-ChildItem -LiteralPath $pipes -Filter ('RIGMMaker.'+$process.Id+'.*.control.json') -File)
    if($files.Count -eq 1){$connection=$files[0].FullName;break}
    Start-Sleep -Milliseconds 50
  }while([DateTime]::UtcNow -lt $deadline)
  if(-not $connection){throw 'Owned application did not publish its private connection'}
  function Invoke-App([string]$Name,[hashtable]$Arguments=@{}){
    & $sender -ConnectionFile $connection -Command $Name -ArgsJson ($Arguments|ConvertTo-Json -Depth 32 -Compress) -TimeoutMs 10000|ConvertFrom-Json
  }
  function Invoke-AfterPreview([string]$Name,[hashtable]$Arguments){
    $until=[DateTime]::UtcNow.AddSeconds(20)
    do {
      try{return Invoke-App $Name $Arguments}
      catch{
        $message=$_.Exception.Message
        if($message -notin @('別の制作ジョブが処理中です。','ジョブ完了後に保存してください。')){throw}
        Start-Sleep -Milliseconds 50
      }
    }while([DateTime]::UtcNow -lt $until)
    throw ('GUI automatic preview did not leave time for '+$Name)
  }
  $initial=Invoke-App 'app-status'
  Check ($initial.ok -and $initial.data.page -eq 'preview' -and $initial.data.openDocuments -eq 1) 'normal product starts on preview with a shared movie document'
  $core=Invoke-App 'status';$common=$core.data.pipes.commandPipe
  Check ($core.data.pipes.routing -eq 'common-command') 'product exposes the common command pipe'
  $schema=Invoke-App 'movie-schema'
  Check ($schema.ok -and @($schema.data.commands.PSObject.Properties).Count -eq 64) 'product exposes all 64 movie commands'
  foreach($page in @('create','characters','preview')){
    $changed=Invoke-App 'app-switch-page' @{page=$page}
    $current=Invoke-App 'status'
    Check ($changed.ok -and $changed.data.page -eq $page -and $current.data.pipes.commandPipe -eq $common) ('page '+$page+' preserves the common endpoint')
  }
  $entries=Invoke-App 'app-library'
  Check ($entries.ok -and @($entries.data.characters).Count -ge 1) 'isolated library can be read without touching user registration'
  $opened=Invoke-App 'app-open-work' @{path=$project}
  Check ($opened.ok -and $opened.data.page -eq 'preview' -and $opened.data.openDocuments -eq 2) 'opening the edited work retains the existing document'
  $movie=Invoke-App 'movie-project'
  Check (@($movie.data.scenes).Count -eq 4 -and @($movie.data.characters).Count -eq 1 -and @($movie.data.cues).Count -eq 4) 'edited work reopens with four scenes, four cues and its actor'
  $images=@($movie.data.scenes|ForEach-Object{$_.image})+@($movie.data.themeBackground)
  $images=@($images|ForEach-Object{if([IO.Path]::IsPathRooted($_)){$_}else{[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $project) $_))}})
  Check (@($images|Where-Object {-not (Test-Path -LiteralPath $_)}).Count -eq 0 -and $images.Count -eq 5) 'all five production image assets resolve in the product'
  $timeline=Invoke-App 'movie-timeline'
  $status=Invoke-App 'movie-status'
  Check ($status.data.time -eq 0 -and -not $status.data.playing) 'normal product opens the image work stopped at zero'
  Check ($timeline.ok -and [Math]::Abs([double]$status.data.duration-37.2106666666667) -lt 0.00001) 'original speech timing remains 37.2106667 seconds'
  $requests=Invoke-App 'movie-composition-requests'
  Check $requests.ok 'sender routes new composition commands to the product'
  $lease=Invoke-App 'movie-edit-begin' @{leaseSeconds=60}
  Check ($lease.ok -and $lease.data.locked -and $lease.data.editToken) 'Codex lease is acquired through the shipped sender'
  $heartbeat=Invoke-App 'movie-edit-heartbeat' @{editToken=$lease.data.editToken;leaseSeconds=60}
  Check ($heartbeat.ok -and $heartbeat.data.locked) 'Codex lease heartbeat uses the current token'
  $ended=Invoke-App 'movie-edit-end' @{editToken=$lease.data.editToken}
  Check ($ended.ok -and -not $ended.data.locked -and $ended.data.state -eq 'completed') 'Codex completion releases GUI editing'
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  do {$status=Invoke-App 'movie-status';if(-not $status.data.busy){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
  if($status.data.busy){throw 'Automatic GUI preview did not finish after edit completion'}
  $png=Join-Path $directory 'product-preview.png'
  $preview=Invoke-AfterPreview 'movie-preview' @{time=0.8;path=$png}
  $deadline=[DateTime]::UtcNow.AddSeconds(20)
  do {$job=Invoke-App 'movie-job-status' @{jobId=$preview.data.jobId};if($job.data.done){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
  Check ($job.data.state -eq 'succeeded' -and $job.data.collected -and (Test-Path -LiteralPath $png)) 'actual product renders the edited work to a collected preview'
  $bytes=[IO.File]::ReadAllBytes($png)
  $width=[Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes,16))
  $height=[Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes,20))
  Check ($width -eq 1920 -and $height -eq 1080) 'actual product preview is Full HD'
  if($Label -eq 'media-Root'){
    $workflow=Invoke-App 'movie-workflow-status'
    Check ($workflow.data.canNext -and -not $workflow.data.requiresHumanConfirmation) 'actual delivered work can advance after automatic preview without human confirmation'
    for($advance=0;$advance -lt 3 -and $workflow.data.currentStage -ne 'complete';$advance++){
      $next=Invoke-App 'movie-workflow-next'
      Check ($next.data.currentStage -in @('export','complete')) ('normal product advances the owned work to '+$next.data.currentStage)
      $workflow=Invoke-App 'movie-workflow-status'
    }
    Check ($workflow.data.currentStage -eq 'complete') 'normal product completes the owned image work'
  }
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  do {$status=Invoke-App 'movie-status';if(-not $status.data.busy){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
  $savedPath=Join-Path $directory 'owned-reopen.rigmovie'
  $saved=Invoke-AfterPreview 'movie-save' @{path=$savedPath}
  Check ($saved.ok -and -not $saved.data.modified -and (Test-Path -LiteralPath $savedPath)) 'product saves only an owned validation copy'
  $reopened=Invoke-App 'app-open-work' @{path=$savedPath}
  Check ($reopened.ok -and $reopened.data.openDocuments -eq 3 -and -not $reopened.data.modified) 'saved validation work reopens and keeps both previous documents'
  $again=Invoke-App 'movie-project'
  Check (@($again.data.scenes).Count -eq 4 -and @($again.data.characters).Count -eq 1 -and $again.data.themeBackground) 'saved copy preserves composition and the theme image'
  Check ((Get-FileHash -LiteralPath $project -Algorithm SHA256).Hash -eq $before) 'edited production source is unchanged by startup checks'
  $report.success=$true;$report.preview=$png;$report.savedProject=$savedPath;$report.defaultPage=$initial.data.page;$report.duration=$status.data.duration
}catch{$report.error=$_.Exception.Message;throw}
finally{
  if(-not $process.HasExited){
    & {
      if(-not ('RigmOwnedWindows' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RigmOwnedWindows {
  public delegate bool EnumProc(IntPtr h,IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f,IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,System.Text.StringBuilder s,int n);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  public static void Close(int pid) { EnumWindows((h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);var s=new System.Text.StringBuilder(128);GetClassName(h,s,128);if(owner==pid && s.ToString()=="TMainForm")PostMessage(h,0x10,IntPtr.Zero,IntPtr.Zero);return true;},IntPtr.Zero); }
}
'@
      }
      [RigmOwnedWindows]::Close($process.Id)
    }
    $null=$process.WaitForExit(10000)
  }
  $report.gracefulExit=$process.HasExited
  if($process.HasExited){$report.exitCode=$process.ExitCode}else{$report.success=$false;$report.closeBlocker='Owned process has not closed; no forced termination attempted'}
  $report.sourceUnchanged=(Get-FileHash -LiteralPath $project -Algorithm SHA256).Hash -eq $before
  $report.passed=$checks.Count;$report.checks=$checks.ToArray();$report.atUtc=[DateTime]::UtcNow.ToString('o')
  $report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $directory 'result.json') -Encoding utf8
  $report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root ('Win64\Validation\production-startup-'+$Label+'.json')) -Encoding utf8
  $process.Dispose()
}
if(-not $report.gracefulExit -or $report.exitCode -ne 0){throw 'Product did not exit gracefully with code zero'}
$report|ConvertTo-Json -Depth 12
