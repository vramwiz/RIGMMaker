unit SoundFileUtilsWave;

interface

uses
  System.SysUtils, System.Classes, System.Math;

{------------------------------------------------------------
  絶対パスのWaveファイルから長さ（秒）を取得します
  ・PCM WAVE のみ対応（16bit/8bit, mono/stereo）
  ・解析に失敗した場合は 0 を返します
  ・長さは Ceil による「切り上げ」
------------------------------------------------------------}
function GetWaveLengthSec(const AbsoluteFileName: string): Double;

implementation

type
  TRiffHeader = packed record
    ChunkID: array[0..3] of AnsiChar;    // 'RIFF'
    ChunkSize: Cardinal;
    Format: array[0..3] of AnsiChar;     // 'WAVE'
  end;

  TChunkHeader = packed record
    ID: array[0..3] of AnsiChar;
    Size: Cardinal;
  end;

  TFmtChunk = packed record
    AudioFormat: Word;      // 1 = PCM
    NumChannels: Word;
    SampleRate: Cardinal;
    ByteRate: Cardinal;
    BlockAlign: Word;
    BitsPerSample: Word;
  end;

function GetWaveLengthSec(const AbsoluteFileName: string): Double;
var
  FS: TFileStream;
  Riff: TRiffHeader;
  Ch: TChunkHeader;
  Fmt: TFmtChunk;
  DataSize: Cardinal;
  FoundFmt, FoundData: Boolean;
  BytesPerSample: Integer;
  Samples: Double;
begin
  Result := 0.0;

  if not FileExists(AbsoluteFileName) then
    Exit;

  try
    FS := TFileStream.Create(AbsoluteFileName, fmOpenRead or fmShareDenyWrite);
    try
      // RIFF / WAVE ヘッダ確認
      if FS.Read(Riff, SizeOf(Riff)) <> SizeOf(Riff) then Exit;

      if (Riff.ChunkID <> 'RIFF') or (Riff.Format <> 'WAVE') then
        Exit;

      FoundFmt  := False;
      FoundData := False;
      DataSize  := 0;

      // チャンク解析
      while FS.Position + SizeOf(TChunkHeader) <= FS.Size do
      begin
        if FS.Read(Ch, SizeOf(Ch)) <> SizeOf(Ch) then Break;

        // fmt チャンク
        if Ch.ID = 'fmt ' then
        begin
          if Ch.Size >= SizeOf(TFmtChunk) then
          begin
            FS.Read(Fmt, SizeOf(TFmtChunk));
            FoundFmt := True;

            // 余分があればスキップ
            if Ch.Size > SizeOf(TFmtChunk) then
              FS.Seek(Ch.Size - SizeOf(TFmtChunk), soFromCurrent);
          end
          else
            Exit;
        end
        // data チャンク
        else if Ch.ID = 'data' then
        begin
          DataSize := Ch.Size;
          FoundData := True;
          FS.Seek(Ch.Size, soFromCurrent);
        end
        else
        begin
          // その他はスキップ
          FS.Seek(Ch.Size, soFromCurrent);
        end;

        if FoundFmt and FoundData then Break;
      end;

      if not (FoundFmt and FoundData) then Exit;
      if Fmt.AudioFormat <> 1 then Exit; // PCMのみ

      if (Fmt.NumChannels = 0) or (Fmt.BitsPerSample = 0) or (Fmt.SampleRate = 0) then
        Exit;

      // 1サンプルのバイト数
      BytesPerSample := (Fmt.NumChannels * Fmt.BitsPerSample) div 8;
      if BytesPerSample <= 0 then Exit;

      // 総サンプル数
      Samples := DataSize / BytesPerSample;

      // 秒に変換（小数あり）
      Result := Samples / Fmt.SampleRate;

    finally
      FS.Free;
    end;

  except
    Result := 0.0;
  end;
end;


end.

