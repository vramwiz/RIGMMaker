param([Parameter(Mandatory=$true)][string]$Root)
# This loopback-only server supplies transport fixtures. It never starts VOICEVOX.
$ErrorActionPreference = 'Stop'
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
@{port=$port} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'server.json') -Encoding UTF8
$count = 0
$query = '{"accent_phrases":[{"moras":[{"text":"カ","consonant":"k","consonant_length":0.05,"vowel":"a","vowel_length":0.1,"pitch":5}],"accent":1,"pause_mora":null,"is_interrogative":false}],"speedScale":1,"pitchScale":0,"intonationScale":1,"volumeScale":1,"prePhonemeLength":0.1,"postPhonemeLength":0.1,"outputSamplingRate":24000,"outputStereo":false}'
$wave = [IO.MemoryStream]::new(); $writer = [IO.BinaryWriter]::new($wave)
$writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int]24036)
$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16); $writer.Write([short]1); $writer.Write([short]1)
$writer.Write([int]24000); $writer.Write([int]48000); $writer.Write([short]2); $writer.Write([short]16)
$writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int]24000); $writer.Write([byte[]]::new(24000))
$waveBytes = $wave.ToArray(); $writer.Dispose(); $wave.Dispose()
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream(); $stream.ReadTimeout = 5000
            $header = ''
            while (-not $header.EndsWith("`r`n`r`n")) {
                $value = $stream.ReadByte(); if ($value -lt 0) { throw 'Client disconnected' }
                $header += [char]$value; if ($header.Length -gt 16384) { throw 'Oversized header' }
            }
            $path = ($header -split ' ')[1]; $status = '200 OK'; $body = '"fixture-version"'
            [IO.File]::AppendAllText((Join-Path $Root 'requests.txt'),$path+"`r`n")
            if ($header -match '(?im)^Expect:\s*100-continue') {
                $continue = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 100 Continue`r`n`r`n"); $stream.Write($continue,0,$continue.Length); $stream.Flush()
            }
            $length = 0; if ($header -match '(?im)^Content-Length:\s*(\d+)') { $length = [int]$Matches[1] }
            $inputBytes = [byte[]]::new($length); $received = 0
            while ($received -lt $length) { $read = $stream.Read($inputBytes,$received,$length-$received); if ($read -eq 0) { throw 'Incomplete body' }; $received += $read }
            $inputJson = [Text.Encoding]::UTF8.GetString($inputBytes)
            $type = 'application/json'
            if ($path -eq '/speakers') {
                $count++
                [IO.File]::WriteAllText((Join-Path $Root 'speaker-count.txt'),[string]$count)
                if ($count -eq 1) { Start-Sleep -Milliseconds 4000 }
                if ($count -eq 2) { Start-Sleep -Milliseconds 2500 }
                $body = '[{"name":"確認用話者","speaker_uuid":"fixture-voice","styles":[{"name":"ノーマル","id":1,"type":"talk"},{"name":"喜び","id":2,"type":"talk"}]}]'
                if ($count -eq 3) { $status = '500 Internal Server Error'; $body = '{"detail":"owned fixture failure"}' }
            }
            if ($path.StartsWith('/audio_query?')) { $body = $query }
            if ($path.StartsWith('/mora_data?')) {
                $body = $inputJson
                if ($inputJson.Contains('"_rigm_display_refresh_test":true')) {
                    Start-Sleep -Milliseconds 150
                    $phrases = @($inputJson | ConvertFrom-Json)
                    foreach ($phrase in $phrases) {
                        $phrase.PSObject.Properties.Remove('_rigm_pending_reading')
                        foreach ($mora in $phrase.moras) {
                            $mora.pitch = 4.25; $mora.consonant_length = 0.07; $mora.vowel_length = 0.16
                        }
                    }
                    $body = ConvertTo-Json -InputObject $phrases -Depth 20 -Compress
                }
            }
            if ($path.StartsWith('/accent_phrases?')) { $body = (($query | ConvertFrom-Json).accent_phrases | ConvertTo-Json -Depth 20 -AsArray -Compress) }
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            if ($path.StartsWith('/synthesis?')) { Start-Sleep -Milliseconds 200; $type = 'audio/wav'; $bytes = $waveBytes }
            $response = [Text.Encoding]::ASCII.GetBytes('HTTP/1.1 '+$status+"`r`nContent-Type: "+$type+"`r`nContent-Length: "+$bytes.Length+"`r`nConnection: close`r`n`r`n")
            $stream.Write($response,0,$response.Length); $stream.Write($bytes,0,$bytes.Length); $stream.Flush()
        } catch { Write-Output $_.Exception.Message } finally { $client.Dispose() }
    }
} finally { $listener.Stop() }
