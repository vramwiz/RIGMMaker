param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [switch]$LiveText,
    [switch]$LiveImage,
    [string]$Exe,
    [switch]$AllowAppContainer
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$outputRoot = [IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $outputRoot) { throw 'Choose a new output directory.' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
if (-not $Exe) { $Exe = Join-Path $repoRoot 'Win64\DotsCodexProbe\Release\DotsCodexProbe.exe' }
$connectionFile = Join-Path $outputRoot 'state\connection.json'
$sender = Join-Path $PSScriptRoot 'Send-ProbeCommand.ps1'
$checks = [Collections.Generic.List[string]]::new()
$launchArguments = '--state-dir "'+(Join-Path $outputRoot 'state')+'"'
if ($AllowAppContainer) { $launchArguments += ' --allow-appcontainer' }
$owned = Start-Process -FilePath $Exe -ArgumentList $launchArguments -PassThru -WindowStyle Hidden
function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('FAILED: '+$Name) }
    $checks.Add($Name)
}
function Invoke([string]$Command, [hashtable]$Arguments=@{}, [string]$Id=([guid]::NewGuid().ToString())) {
    & $sender -ConnectionFile $connectionFile -Command $Command -ArgsJson ($Arguments | ConvertTo-Json -Compress -Depth 20) -RequestId $Id
}
function RawRequest([string]$Text, [int]$Chunk=17) {
    $discovery = Get-Content -LiteralPath $connectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($discovery.requiresAccessToken) {
        try {
            $parsed = ConvertFrom-Json -InputObject $Text -AsHashtable
            if ($parsed -is [Collections.IDictionary]) { $parsed.accessToken = $discovery.accessToken; $Text=$parsed | ConvertTo-Json -Depth 20 -Compress }
        } catch { }
    }
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $discovery.pipeName, [IO.Pipes.PipeDirection]::InOut)
    try {
        $client.Connect(5000)
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text+"`n")
        for ($i=0; $i -lt $bytes.Length; $i+=$Chunk) { $client.Write($bytes,$i,[Math]::Min($Chunk,$bytes.Length-$i)) }
        $reader = [IO.StreamReader]::new($client,[Text.Encoding]::UTF8,$false,4096,$true)
        try { $reader.ReadLine() | ConvertFrom-Json } finally { $reader.Dispose() }
    } finally { $client.Dispose() }
}
function WaitJob([string]$Id, [int]$Seconds) {
    $until = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $result = Invoke 'job.get' @{jobId=$Id}
        if (-not $result.ok) { throw ($result | ConvertTo-Json -Depth 10) }
        if ($result.data.state -ne 'running') { return $result.data }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $until)
    throw 'Codex job deadline exceeded.'
}
try {
    $until = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $connectionFile)) {
        if ($owned.HasExited -or [DateTime]::UtcNow -gt $until) { throw 'App startup failed.' }
        Start-Sleep -Milliseconds 100
    }
    Check (Invoke 'ping').ok 'Named pipe discovery and ping'
    $text = "日本語・改行`n引用符`"とemoji😀"
    Check ((Invoke 'echo' @{text=$text}).data.text -ceq $text) 'UTF-8 Japanese emoji escaped newline'
    $long = '通信ABC😀' * 10000
    Check ((Invoke 'echo' @{text=$long}).data.text -ceq $long) 'Fragmented large request and response'
    $fragmented = RawRequest (@{version=1;id='split';command='echo';args=@{text=$text}} | ConvertTo-Json -Compress) 1
    Check ($fragmented.data.text -ceq $text) 'One-byte writes across UTF-8 boundaries'
    Check (-not (RawRequest '{broken').ok) 'Malformed JSON rejected'
    Check (-not (RawRequest '{"version":2,"id":"bad-v","command":"ping","args":{}}').ok) 'Unknown version rejected'
    Check (-not (RawRequest '{"version":1,"id":4,"command":"ping","args":{}}').ok) 'Non-string id rejected'
    Check (-not (RawRequest '{"version":1,"id":"bad-a","command":"ping","args":[]}').ok) 'Non-object args rejected'
    Check (-not (Invoke 'not-a-command').ok) 'Unknown command rejected'
    Check (-not (Invoke 'echo' @{text=42}).ok) 'Echo requires a string'
    Check (-not (Invoke 'text.save' @{}).ok) 'Text save requires a string'
    $saved = Invoke 'text.save' @{text=$text} 'save-repeat'
    Check ($saved.ok -and ((Get-Content -LiteralPath $saved.data.path -Raw -Encoding UTF8) -ceq $text)) 'Text saved on client'
    $replayed = Invoke 'text.save' @{text=$text} 'save-repeat'
    Check ($saved.data.path -ceq $replayed.data.path) 'Repeated request id does not write twice'
    Check ((Invoke 'text.save' @{text='changed'} 'save-repeat').error.code -eq 'id_conflict') 'Reused id with changed payload rejected'
    Check (-not (Invoke 'image.get' @{imageId='..\outside'}).ok) 'Unknown image path cannot be read'
    Check (-not (Invoke 'job.get' @{jobId='missing'}).ok) 'Unknown job rejected'
    Check (-not (Invoke 'codex.start' @{mode='other';text='test'}).ok) 'Invalid mode rejected before launch'
    Check (-not (Invoke 'codex.start' @{mode='text';text=''}).ok) 'Empty prompt rejected before launch'
    Check (-not (Invoke 'image.put' @{base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('not image'))}).ok) 'Non-image payload rejected'
    Check (-not (Invoke 'image.put' @{base64='@@@'}).ok) 'Malformed Base64 rejected'
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new(64,48)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $memory = [IO.MemoryStream]::new()
    try {
        $graphics.Clear([Drawing.Color]::CornflowerBlue)
        $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
        $bytes = $memory.ToArray()
    } finally { $graphics.Dispose(); $bitmap.Dispose(); $memory.Dispose() }
    $image = Invoke 'image.put' @{base64=[Convert]::ToBase64String($bytes)}
    Check ($image.ok -and $image.data.width -eq 64 -and $image.data.height -eq 48) 'Base64 PNG saved decoded and displayed'
    $download = Invoke 'image.get' @{imageId=$image.data.imageId}
    Check ($download.ok -and $download.data.base64 -ceq [Convert]::ToBase64String($bytes)) 'Image round trip bytes identical'
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    Check ($download.data.sha256 -ceq $hash) 'Image SHA256 matches independently calculated hash'
    $oversizedHeader = $bytes.Clone()
    $oversizedHeader[16]=127
    Check (-not (Invoke 'image.put' @{base64=[Convert]::ToBase64String($oversizedHeader)}).ok) 'Oversized PNG dimensions rejected before decode'
    foreach ($format in @([Drawing.Imaging.ImageFormat]::Jpeg,[Drawing.Imaging.ImageFormat]::Bmp)) {
        $fixture = [Drawing.Bitmap]::new(32,24)
        $stream = [IO.MemoryStream]::new()
        try { $fixture.Save($stream,$format); $formatBytes=$stream.ToArray() }
        finally { $stream.Dispose(); $fixture.Dispose() }
        $uploadedFormat = Invoke 'image.put' @{base64=[Convert]::ToBase64String($formatBytes)}
        Check ($uploadedFormat.ok -and $uploadedFormat.data.width -eq 32) ($format.ToString()+' decode and storage')
    }
    if ($LiveText) {
        $started = Invoke 'codex.start' @{mode='text';text='Reply with exactly DOTS_TEXT_OK'} 'live-text'
        Check $started.ok 'Real Codex text job accepted'
        $duplicate = Invoke 'codex.start' @{mode='text';text='Reply with exactly DOTS_TEXT_OK'} 'live-text'
        Check ($duplicate.data.jobId -ceq $started.data.jobId) 'Codex start replay keeps the same job'
        Check ((Invoke 'codex.start' @{mode='text';text='another'}).error.code -eq 'busy') 'Concurrent job rejected'
        $job = WaitJob $started.data.jobId 330
        Check ($job.state -eq 'completed' -and $job.text -cmatch 'DOTS_TEXT_OK') 'Real Codex text reply via Dots pipe'
        $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'live-text.json') -Encoding UTF8
        $started = Invoke 'codex.start' @{mode='text';text='Describe the attached image color briefly.';imageId=$image.data.imageId}
        Check $started.ok 'Real Codex accepts attached image job'
        $job = WaitJob $started.data.jobId 330
        Check ($job.state -eq 'completed' -and $job.text -match 'blue|青') 'Real Codex image input interpreted'
        $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'live-vision.json') -Encoding UTF8
        $started = Invoke 'codex.start' @{mode='text';text='Briefly explain this test.'}
        $cancelled = Invoke 'job.cancel' @{jobId=$started.data.jobId}
        Check $cancelled.ok 'Cancellation accepted'
        $job = WaitJob $started.data.jobId 15
        Check ($job.state -eq 'cancelled') 'Cancelled worker stops and releases busy state'
    }
    if ($LiveImage) {
        $started = Invoke 'codex.start' @{mode='image';text='Generate one small simple illustration of a blue sphere on a plain white background. No text.'}
        Check $started.ok 'Real Codex image generation accepted'
        $job = WaitJob $started.data.jobId 630
        $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'live-image.json') -Encoding UTF8
        Check ($job.state -eq 'completed' -and $job.image.imageId) 'Real generated image received decoded and stored'
        $received = Invoke 'image.get' @{imageId=$job.image.imageId}
        Check ($received.ok -and $received.data.sha256 -ceq $job.image.sha256) 'Generated image returned to Dots caller'
    }
    Check (Invoke 'ping').ok 'Listener usable after errors and jobs'
    # Close exactly our main form using its owning UI thread, including a connected idle client.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DotsProbeWindow {
    public delegate bool Callback(IntPtr handle, IntPtr data);
    [DllImport("user32.dll")] public static extern bool EnumWindows(Callback callback, IntPtr data);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint pid);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr handle, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr handle, System.Text.StringBuilder text, int max);
}
'@
    $discovery = Get-Content -LiteralPath $connectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $idle = [IO.Pipes.NamedPipeClientStream]::new('.', $discovery.pipeName, [IO.Pipes.PipeDirection]::InOut)
    try {
        $idle.Connect(5000)
        $script:windowCount = 0
        $callback = [DotsProbeWindow+Callback] {
            param($handle,$data)
            [uint32]$processId = 0
            [void][DotsProbeWindow]::GetWindowThreadProcessId($handle,[ref]$processId)
            if ($processId -eq $owned.Id) {
                $title = [Text.StringBuilder]::new(256)
                [void][DotsProbeWindow]::GetWindowText($handle,$title,256)
                if ($title.ToString() -eq 'Dots → アプリ → Codex 通信試験') {
                    $script:windowCount++
                    [void][DotsProbeWindow]::PostMessage($handle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
                }
            }
            return $true
        }
        [void][DotsProbeWindow]::EnumWindows($callback,[IntPtr]::Zero)
        Check ($script:windowCount -eq 1) 'Exactly one main form'
        Check ($owned.WaitForExit(10000)) 'Clean shutdown with idle connected pipe'
        Check (-not (Test-Path -LiteralPath $connectionFile)) 'Discovery removed on clean shutdown'
    } finally { $idle.Dispose() }
    @{success=$true;checks=$checks.ToArray();liveText=[bool]$LiveText;liveImage=[bool]$LiveImage} |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
    Write-Output ('Passed '+$checks.Count+' checks. Evidence: '+$outputRoot)
} catch {
    @{success=$false;error=$_.ToString();checks=$checks.ToArray()} | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
    throw
} finally {
    if (-not $owned.HasExited) { Stop-Process -Id $owned.Id }
    $owned.Dispose()
}
