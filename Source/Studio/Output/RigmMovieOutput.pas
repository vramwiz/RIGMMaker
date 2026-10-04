// 出力プリセット、エンコード設定と保存先の共通規則を定義する。ファイル生成は出力ジョブへ委譲する。
unit RigmMovieOutput;
interface
uses System.JSON;
function MovieOutputPresets: TJSONObject;
procedure MoviePresetDimensions(const Id: string; out Width,Height,Fps: Integer);
function MoviePresetId(Width,Height,Fps: Integer): string;
function MovieEncoderOptions(const Profile: string): string;
function MovieJpegQuality(const Profile: string): Integer;
implementation
uses System.SysUtils, RigmModel, RigmJson;
function MovieOutputPresets: TJSONObject;
begin
  Result := ParseObject('{"draft":{"width":640,"height":360,"fps":15},"hd":{"width":1280,"height":720,"fps":30},"fullhd":{"width":1920,"height":1080,"fps":30},"custom":"explicit dimensions and fps",'+
    '"encoding":{"fast":"veryfast / CRF23 / JPEG80; smaller CPU budget","balanced":"medium / CRF20 / JPEG90","quality":"slow / CRF18 / JPEG95; larger staging and CPU time"},"threads":4,"limit":"MP4 streams raw frames to FFmpeg; AVI alone retains its legacy 2GB limit"}');
end;
procedure MoviePresetDimensions(const Id: string; out Width,Height,Fps: Integer);
begin
  if Id='draft' then begin Width := 640; Height := 360; Fps := 15; end
  else if Id='hd' then begin Width := 1280; Height := 720; Fps := 30; end
  else if Id='fullhd' then begin Width := 1920; Height := 1080; Fps := 30; end
  else if Id='custom' then begin Width := 0; Height := 0; Fps := 0; end
  else raise ERigm.Create('出力プリセットはdraft、hd、fullhd、customです。');
end;
function MoviePresetId(Width,Height,Fps: Integer): string;
begin
  Result := 'custom'; if (Width=640) and (Height=360) and (Fps=15) then Result := 'draft';
  if (Width=1280) and (Height=720) and (Fps=30) then Result := 'hd';
  if (Width=1920) and (Height=1080) and (Fps=30) then Result := 'fullhd';
end;
function MovieEncoderOptions(const Profile: string): string;
begin
  if Profile='fast' then Result := '-preset veryfast -crf 23'
  else if Profile='balanced' then Result := '-preset medium -crf 20'
  else if Profile='quality' then Result := '-preset slow -crf 18'
  else raise ERigm.Create('出力品質はfast、balanced、qualityです。');
end;
function MovieJpegQuality(const Profile: string): Integer;
begin
  MovieEncoderOptions(Profile); Result := 90; if Profile='fast' then Result := 80 else if Profile='quality' then Result := 95;
end;
end.
