param(
    [ValidateSet('codex','dots')][string]$Mode='codex',
    [string]$Exe,
    [string]$DataRoot,
    [string]$SettingsDirectory
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $Exe){$Exe=Join-Path $repo 'Win64\RigmCommunication\Release\RIGMMaker.exe'}
$Exe=[IO.Path]::GetFullPath($Exe)
if(-not(Test-Path -LiteralPath $Exe)){throw ('EXE not found: '+$Exe)}
$arguments='--communication-mode '+$Mode
foreach($item in @(@{flag='--data-root';path=$DataRoot},@{flag='--settings-dir';path=$SettingsDirectory})){
    if($item.path){
        $path=[IO.Path]::GetFullPath($item.path)
        if($path.Contains('"')){throw 'Invalid directory.'}
        $arguments+=' '+$item.flag+' "'+$path+'"'
    }
}
# 利用者が操作する本編フォームを起動する。別モードの実行中プロセスは終了しない。
$started=Start-Process -FilePath $Exe -ArgumentList $arguments -PassThru -WindowStyle Normal
$resolvedDataRoot=$DataRoot
if(-not $resolvedDataRoot){
    $resolvedDataRoot=if(Test-Path -LiteralPath 'D:\Users\take6\RIGMMaker'){'D:\Users\take6\RIGMMaker'}else{Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'RIGMMaker'}
}
$resolvedDataRoot=[IO.Path]::GetFullPath($resolvedDataRoot)
$mask=if($Mode -eq 'dots'){'dots-'+$started.Id+'-*.json'}else{'workspace-'+$started.Id+'.json'}
$exchange=Join-Path $resolvedDataRoot 'Exchange'
$connection=$null
$deadline=[DateTime]::UtcNow.AddSeconds(15)
while(-not $connection -and -not $started.HasExited -and [DateTime]::UtcNow -lt $deadline){
    if(Test-Path -LiteralPath $exchange){$connection=Get-ChildItem -LiteralPath $exchange -Filter $mask | Select-Object -First 1}
    if(-not $connection){Start-Sleep -Milliseconds 100}
}
[pscustomobject]@{processId=$started.Id;communicationMode=$Mode;executable=$Exe;dataRoot=$resolvedDataRoot;connectionFile=if($connection){$connection.FullName}else{Join-Path $exchange $mask}}
