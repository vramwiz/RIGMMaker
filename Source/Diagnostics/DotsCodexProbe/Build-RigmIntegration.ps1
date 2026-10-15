param([string]$OutputRoot,[string]$StudioRoot='C:\Program Files (x86)\Embarcadero\Studio\37.0')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if(-not $OutputRoot){$OutputRoot=Join-Path $repo 'Win64\RigmCommunication'}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable);$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$search=$project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';'|Where-Object {$_ -and -not $_.StartsWith('$(')}
$searchPaths=@($search|ForEach-Object {Join-Path $repo $_})
$compiler=Join-Path $StudioRoot 'bin\dcc64.exe'
$results=@()
Push-Location $repo
$previousEncoding=[Console]::OutputEncoding
try{
    [Console]::OutputEncoding=[Text.Encoding]::GetEncoding(932)
    foreach($configuration in @('Debug','Release')){
        $bin=Join-Path $OutputRoot $configuration
        $dcu=Join-Path $bin 'dcu'
        New-Item -ItemType Directory -Path $bin,$dcu -Force|Out-Null
        $flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($searchPaths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data')
        if($configuration -eq 'Debug'){$flags+=@('-DDEBUG','-$O-','-$R+','-$Q+')}else{$flags+=@('-DRELEASE','-$O+','-$R-','-$Q-')}
        $build=@(& $compiler @flags (Join-Path $repo 'RIGMMaker.dpr') 2>&1)
        $code=$LASTEXITCODE
        $build|Set-Content -LiteralPath (Join-Path $bin 'build.log') -Encoding UTF8
        if($code -ne 0){$build|Select-Object -Last 8;throw ($configuration+' compilation failed.')}
        $warnings=@($build|Where-Object {$_ -match '\bW[0-9]{4}\b'})
        $newWarnings=@($warnings|Where-Object {$_ -match 'RigmDots|RigmCommunication|RigmWizardAiCommands|RigmWizardPipe'})
        $results+=@{configuration=$configuration;exitCode=$code;warnings=$warnings.Count;communicationWarnings=$newWarnings.Count;executable=(Join-Path $bin 'RIGMMaker.exe')}
        Write-Output ($configuration+': compiled; warnings='+$warnings.Count+'; communication warnings='+$newWarnings.Count)
    }
}finally{[Console]::OutputEncoding=$previousEncoding;Pop-Location}
@{compilerOnly=$true;usesDprojSearchPaths=$true;ffmpegDeploymentPerformed=$false;results=$results}|
    ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputRoot 'build-results.json') -Encoding UTF8
