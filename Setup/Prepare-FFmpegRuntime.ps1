param([string]$Archive='D:\DelphiProg\VM_Media_Output\Setup\VW_Media_Output.zip')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$destination=Join-Path $repo 'Runtime\FFmpeg'
$names=@('avutil-60.dll','swresample-6.dll','swscale-9.dll','avcodec-62.dll','avformat-62.dll','FFmpeg-LICENSE.txt','FFmpeg-README.txt')
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
$files=@()
try {
    foreach($name in $names){
        $entries=@($zip.Entries | Where-Object {($_.FullName.Replace('\','/').Split('/')[-1]) -eq $name})
        if($entries.Count -ne 1){throw ('Expected one runtime entry: '+$name)}
        $path=Join-Path $destination $name
        $inputStream=$entries[0].Open()
        $buffer=[IO.MemoryStream]::new()
        try{$inputStream.CopyTo($buffer);$bytes=$buffer.ToArray()}finally{$buffer.Dispose();$inputStream.Dispose()}
        if($name.EndsWith('.dll')){
            if($bytes.Length -lt 64){throw ('Truncated DLL: '+$name)}
            $pe=[BitConverter]::ToInt32($bytes,60)
            if($pe -lt 0 -or $pe+6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664){throw ('Expected Win64 DLL: '+$name)}
        }
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
        if(Test-Path -LiteralPath $path){
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hash){throw ('Existing runtime differs; preserved: '+$path)}
        }else{[IO.File]::WriteAllBytes($path,$bytes)}
        $files += [ordered]@{name=$name;bytes=$bytes.Length;sha256=$hash}
    }
}finally{$zip.Dispose()}
$manifest=[ordered]@{version='8.1.1-full_build-www.gyan.dev';architecture='Win64';source='https://github.com/FFmpeg/FFmpeg/commit/239f2c733d';reference='VM_Media_Output/Setup/VW_Media_Output.zip';archiveSha256=(Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash;files=$files}
[IO.File]::WriteAllText((Join-Path $destination 'manifest.json'),($manifest | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
Write-Output ('Prepared '+$files.Count+' runtime files: '+$destination)
