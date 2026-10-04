#requires -Version 7.0
param([int]$Port=51234,[Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $Directory -Force | Out-Null
# Deterministic HTTP fixture. This is NOT VOICEVOX and never produces speech.
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
$listener.Start()
Set-Content -LiteralPath (Join-Path $Directory 'fixture-ready.txt') -Value $Port
try {
  $deadline=[DateTime]::UtcNow.AddMinutes(15)
  while([DateTime]::UtcNow -lt $deadline -and -not (Test-Path (Join-Path $Directory 'fixture-stop.txt'))) {
    if(-not $listener.Pending()){Start-Sleep -Milliseconds 10;continue}
    $client=$listener.AcceptTcpClient();$client.ReceiveTimeout=5000;$client.SendTimeout=5000
    try {
      $stream=$client.GetStream();$header=[Collections.Generic.List[byte]]::new()
      while($header.Count -lt 65536){
        $b=$stream.ReadByte();if($b -lt 0){throw 'EOF'};$header.Add([byte]$b)
        if($header.Count -ge 4 -and [Text.Encoding]::ASCII.GetString($header.ToArray(),$header.Count-4,4) -eq "`r`n`r`n"){break}
      }
      $request=[Text.Encoding]::ASCII.GetString($header.ToArray())
      $path=($request.Split("`r`n")[0].Split(' '))[1]
      $length=0;if($request -match '(?im)^Content-Length: (\d+)'){ $length=[int]$matches[1] }
      if($request -match '(?im)^Expect: 100-continue'){$interim=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 100 Continue`r`n`r`n");$stream.Write($interim)}
      $body=[byte[]]::new($length);$received=0;while($received -lt $length){$n=$stream.Read($body,$received,$length-$received);if($n -le 0){throw 'body EOF'};$received+=$n}
      $status='200 OK';$type='application/json';$data='{}'
      if($path -like '/speakers*'){$data='[{"name":"TEST TONE FIXTURE","speaker_uuid":"fixture-not-a-real-speaker","styles":[{"id":101,"name":"Tone","type":"talk"},{"id":102,"name":"Slow tone","type":"talk"}]}]'}
      elseif($path -like '/audio_query*'){$data='{"accent_phrases":[{"moras":[{"text":"TEST","consonant":null,"consonant_length":null,"vowel":"a","vowel_length":0.4,"pitch":5}],"accent":1,"pause_mora":null,"is_interrogative":false}],"speedScale":1,"pitchScale":0,"intonationScale":1,"volumeScale":1,"prePhonemeLength":0.05,"postPhonemeLength":0.05,"outputSamplingRate":24000,"outputStereo":false,"kana":"TEST"}'}
      elseif($path -like '/synthesis*'){
        $type='audio/wav';$memory=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($memory)
        try {
          $rate=24000;$samples=12000;$writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([uint32](36+$samples*2));$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([uint32]16)
          $writer.Write([uint16]1);$writer.Write([uint16]1);$writer.Write([uint32]$rate);$writer.Write([uint32]($rate*2));$writer.Write([uint16]2);$writer.Write([uint16]16)
          $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([uint32]($samples*2))
          for($i=0;$i -lt $samples;$i++){$value=0;if($i -ge 1200 -and $i -lt 10800){$value=[int16]([Math]::Sin($i*2*[Math]::PI*220/$rate)*10000)};$writer.Write([int16]$value)}
          $bytes=$memory.ToArray()
        }finally{$writer.Dispose();$memory.Dispose()}
        # A brief delay makes cancellation and GUI responsiveness observable.
        Set-Content -LiteralPath (Join-Path $Directory 'synthesis-active.txt') 'active'
        $delay=120;$delayFile=Join-Path $Directory 'delay-ms.txt'
        if(Test-Path -LiteralPath $delayFile){$delay=[int](Get-Content -LiteralPath $delayFile -Raw)}
        Start-Sleep -Milliseconds $delay
        $countFile=Join-Path $Directory 'synthesis-count.txt';$number=1
        if(Test-Path -LiteralPath $countFile){$number=[int](Get-Content -LiteralPath $countFile -Raw)+1}
        Set-Content -LiteralPath $countFile -Value $number
        $failFile=Join-Path $Directory 'fail-synthesis-number.txt'
        if((Test-Path -LiteralPath $failFile) -and $number -eq [int](Get-Content -LiteralPath $failFile -Raw)){
          $status='500 Internal Server Error';$type='application/json';$data='{"detail":"controlled fixture synthesis failure, not real engine"}'
        }
      }
      elseif($path -eq '/version'){$data='"TEST FIXTURE - NO SPEECH"'}
      else{$status='404 Not Found';$data='{"detail":"fixture endpoint not supported"}'}
      if($path -like '/speakers*'){
        Set-Content -LiteralPath (Join-Path $Directory 'speakers-active.txt') 'active'
        $speakerDelayFile=Join-Path $Directory 'speakers-delay-ms.txt'
        if(Test-Path -LiteralPath $speakerDelayFile){Start-Sleep -Milliseconds ([int](Get-Content -LiteralPath $speakerDelayFile -Raw))}
      }
      if($type -ne 'audio/wav'){$bytes=[Text.Encoding]::UTF8.GetBytes($data)}
      $response=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
      $stream.Write($response);$stream.Write($bytes);$stream.Flush()
      Add-Content -LiteralPath (Join-Path $Directory 'fixture-requests.log') -Value $path
    }catch{Add-Content -LiteralPath (Join-Path $Directory 'fixture-errors.log') -Value $_.Exception.Message}
    finally{$client.Dispose()}
  }
}finally{$listener.Stop()}
