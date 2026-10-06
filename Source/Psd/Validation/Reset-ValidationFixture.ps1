param([Parameter(Mandatory)][string]$Fixture)
$ErrorActionPreference='Stop'
$full=[IO.Path]::GetFullPath($Fixture)
$ownedRoot=Split-Path -Parent (Split-Path -Parent $full)
if(-not $ownedRoot.StartsWith([IO.Path]::GetFullPath($env:TEMP)+'\',[StringComparison]::OrdinalIgnoreCase) -or
 (Split-Path -Leaf $ownedRoot) -notmatch '^RIGMMaker-(Wizard|Workspace)Check-[a-f0-9]{32}$' -or
 (Split-Path -Leaf $full) -ne 'fixture.psdchar'){throw 'Only an owned external validation fixture can be reset'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::Open($full,[IO.Compression.ZipArchiveMode]::Update)
try{
 $entry=$zip.GetEntry('manifest.json');$reader=[IO.StreamReader]::new($entry.Open())
 try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
 $manifest|Add-Member -NotePropertyName production -NotePropertyValue @{stage='draft';checked=$false} -Force
 $manifest.settings.PSObject.Properties.Remove('motionReference')
 foreach($name in @(([string][char]0x697D+[char]0x3057+[char]0x307F),([string][char]0x697D+[char]0x3057+[char]0x3044),([string][char]0x697D))){$manifest.settings.expressions.PSObject.Properties.Remove($name)}
 $entry.Delete();$writer=[IO.StreamWriter]::new($zip.CreateEntry('manifest.json').Open(),[Text.UTF8Encoding]::new($false))
 try{$writer.Write(($manifest|ConvertTo-Json -Depth 32 -Compress))}finally{$writer.Dispose()}
}finally{$zip.Dispose()}
