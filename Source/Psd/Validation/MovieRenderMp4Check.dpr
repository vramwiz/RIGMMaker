program MovieRenderMp4Check;
{$APPTYPE CONSOLE}
// 描画DCの回収を競合させながら実MP4を出力し、全映像フレームを復号する。
uses System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils, System.JSON,
  System.Math, System.Types, Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmMovieModel, RigmMovieComposition, RigmMovieAudio, RigmMovieMp4, RigmFFmpegApi, RigmFFmpegTypes;
var Root: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create(Name);
  Checks.Add(Name); Writeln('PASS ',Name); Flush(Output);
end;
function Fixture(W,H,Count: Integer): TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create; Result.Width := W; Result.Height := H;
  Result.Fps := 30; Result.EncodeProfile := 'fast';
  Result.FileName := TPath.Combine(Root,'owned.rigmovie');
  var S := TRigmMovieScene.Create; Result.Scenes.Add(S);
  S.Title := '雪景色の章名'; S.Description := '半透明背景付きの補足文';
  S.DisplayMode := 'both'; S.Image := TPath.Combine(Root,'scene.png');
  var C := TRigmMovieCue.Create; Result.Cues.Add(C);
  C.Scene := S.Id; C.Text := ''; C.Subtitle := '字幕とシーン画像の連続出力';
  C.Pause := Count/30.0; C.AudioSeconds := 0;
end;
procedure ExportWithCollection(P: TRigmMovieProject; const Path: string;
  FailAfter: Integer; out Failure: string; out Collections: Integer;
  UseStoredAudio: Boolean=False; RaiseError87: Boolean=False);
var Done: Integer;
begin
  Done := 0; Failure := ''; Collections := 0;
  var A: TRigmPcm;
  if UseStoredAudio then A := MixMovieAudio(P)
  else begin A := TRigmPcm.Create; A.Rate := 48000; SetLength(A.Samples,Ceil(P.Duration*A.Rate)); end;
  var ErrorText := '';
  var Worker := TThread.CreateAnonymousThread(procedure
    begin
      try
        StreamMovieMp4(P,nil,A,Path,nil,
          procedure(Current,Total: Integer; Staging: UInt64)
          begin
            if (FailAfter>0) and (Current=FailAfter) then begin
              if RaiseError87 then begin
                var E := EOSError.Create('Owned error 87 diagnostic'); E.ErrorCode := 87; raise E;
              end;
              P.Scenes[0].Image := TPath.Combine(Root,'missing-after-frame.png');
            end;
            if Current mod 1000=0 then begin Writeln('Rendered ',Current,'/',Total); Flush(Output); end;
          end,nil,nil);
      except on E: Exception do begin
        ErrorText := E.ClassName+': '+E.Message;
        if E is EOSError then ErrorText := ErrorText+' [preserved-code='+IntToStr(EOSError(E).ErrorCode)+']';
      end; end;
      TInterlocked.Exchange(Done,1);
    end);
  Worker.FreeOnTerminate := False;
  try
    Worker.Start;
    while TInterlocked.CompareExchange(Done,0,0)=0 do begin
      FreeMemoryContexts; Inc(Collections); Sleep(1);
    end;
    Worker.WaitFor; Failure := ErrorText;
  finally Worker.Free; A.Free; end;
end;
function DecodeVideo(const Path: string; W,H: Integer): Integer; forward;
procedure StoredProject(const Path: string);
begin
  var P := LoadMovie(Path); var Failure: string; var Collections: Integer;
  try
    var Before := P.Json;
    try
      var Expected := Ceil(P.Duration*P.Fps);
      Writeln('Stored project: ',P.Width,'x',P.Height,' ',P.Fps,'fps, ',Expected,' frames'); Flush(Output);
      var OutputPath := TPath.Combine(Root,'stored-project.mp4');
      ExportWithCollection(P,OutputPath,0,Failure,Collections,True);
      Check(Failure='','stored project exports with context collection: '+Failure);
      var After := P.Json;
      try Check(Before.ToJSON=After.ToJSON,'export preserves the in-memory stored project'); finally After.Free; end;
      Check(Collections>0,'VCL context collection competed with stored-project export');
      Check(DecodeVideo(OutputPath,P.Width,P.Height)=Expected,'every stored-project video frame decodes');
    finally Before.Free; end;
  finally P.Free; end;
end;
function DecodeVideo(const Path: string; W,H: Integer): Integer;
var Format: PAVFormatContext; Packet: PAVPacket; Frame: PAVFrame;
  Codec: PAVCodecContext; VideoIndex,Count: Integer;
  procedure Receive(Api: TRigmFFmpegApi);
  begin
    while True do begin
      var Code := Api.avcodec_receive_frame(Codec,Frame);
      if (Code=AVERROR_EAGAIN) or (Code=AVERROR_EOF) then Exit;
      Api.Check(Code,'decode video frame');
      if (Frame^.width<>W) or (Frame^.height<>H) then raise Exception.Create('Decoded frame dimensions changed');
      Inc(Count);
    end;
  end;
begin
  Format := nil; Packet := nil; Frame := nil; Codec := nil; VideoIndex := -1; Count := 0;
  var Api := TRigmFFmpegApi.Create;
  try
    var Name := UTF8String(Path);
    Api.Check(Api.avformat_open_input(@Format,PAnsiChar(Name),nil,nil),'open rendered MP4');
    Api.Check(Api.avformat_find_stream_info(Format,nil),'find rendered MP4 streams');
    Check(Format^.nb_streams=2,'rendered MP4 contains video and audio');
    for var I := 0 to Integer(Format^.nb_streams)-1 do begin
      var Stream := PAVStream(PPointer(NativeUInt(Format^.streams)+NativeUInt(I)*SizeOf(Pointer))^);
      if Stream^.codecpar^.codec_type<>AVMEDIA_TYPE_VIDEO then Continue;
      Check(Stream^.codecpar^.codec_id=27,'rendered video uses H.264'); VideoIndex := I;
      Codec := Api.avcodec_alloc_context3(Api.avcodec_find_decoder(Stream^.codecpar^.codec_id));
      Api.Check(Api.avcodec_parameters_to_context(Codec,Stream^.codecpar),'decoder parameters');
      Api.Check(Api.avcodec_open2(Codec,nil,nil),'open video decoder');
    end;
    Check(Codec<>nil,'rendered video decoder opened');
    Packet := Api.av_packet_alloc(); Frame := Api.av_frame_alloc();
    while Api.av_read_frame(Format,Packet)>=0 do begin
      if Packet^.stream_index=VideoIndex then begin
        Api.Check(Api.avcodec_send_packet(Codec,Packet),'decode video packet'); Receive(Api);
      end;
      Api.av_packet_unref(Packet);
    end;
    Api.Check(Api.avcodec_send_packet(Codec,nil),'drain video decoder'); Receive(Api);
    Result := Count;
  finally
    if Frame<>nil then Api.av_frame_free(@Frame);
    if Packet<>nil then Api.av_packet_free(@Packet);
    if Codec<>nil then Api.avcodec_free_context(@Codec);
    if Format<>nil then Api.avformat_close_input(@Format);
    Api.Free;
  end;
end;
procedure SuccessfulExport(W,H,Count: Integer);
begin
  var P := Fixture(W,H,Count); var Failure: string; var Collections: Integer;
  try
    var Path := TPath.Combine(Root,Format('render-%dx%d.mp4',[W,H]));
    ExportWithCollection(P,Path,0,Failure,Collections);
    Check(Failure='',Format('%d frames at %dx%d survive context collection: %s',[Count,W,H,Failure]));
    Check(Collections>0,'VCL contexts were collected during MP4 output');
    Check(DecodeVideo(Path,W,H)=Count,'every rendered MP4 frame decodes including the last frame');
  finally P.Free; end;
end;
procedure FailureDiagnostic;
begin
  var P := Fixture(320,180,120); var Failure: string; var Collections: Integer;
  try
    var Path := TPath.Combine(Root,'expected-render-failure.mp4');
    ExportWithCollection(P,Path,5,Failure,Collections);
    TFile.WriteAllText(TPath.Combine(Root,'expected-render-failure.txt'),Failure,TEncoding.UTF8);
    Check(Failure.Contains('ffmpeg-shared-h264-aac / render / 出力フレーム 6/120'),'render failure identifies backend, stage and exact frame');
    Check(Failure.Contains('320x180 30fps') and Failure.Contains('GDI=') and Failure.Contains('handles='),'render failure contains dimensions and resource counts');
    Check(Failure.Contains('missing-after-frame.png'),'render failure retains the original cause');
    Check(not FileExists(Path),'failed writer removes its unfinished output');
    P.Scenes[0].Image := TPath.Combine(Root,'scene.png');
    Path := TPath.Combine(Root,'expected-win32-87.mp4');
    ExportWithCollection(P,Path,5,Failure,Collections,False,True);
    TFile.WriteAllText(TPath.Combine(Root,'expected-win32-87.txt'),Failure,TEncoding.UTF8);
    Check(Failure.Contains('frame-progress / 出力フレーム 5/120'),'Win32 diagnostic identifies the failing operation and frame');
    Check(Failure.Contains('Win32=87') and Failure.Contains('preserved-code=87'),'failure context preserves EOSError and its native code 87');
    Check(not FileExists(Path),'Win32 failure removes its unfinished output');
  finally P.Free; end;
end;
begin
  Checks := TJSONArray.Create;
  try
    try
      Root := ParamStr(1); if Root='' then raise Exception.Create('Owned output directory required');
      ForceDirectories(Root);
      var B := TBitmap.Create; var PNG := TPngImage.Create;
      try
        B.PixelFormat := pf32bit; B.SetSize(64,64); B.Canvas.Brush.Color := clAqua;
        B.Canvas.FillRect(Rect(0,0,64,64)); PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'scene.png'));
      finally PNG.Free; B.Free; end;
      if ParamCount>1 then StoredProject(ParamStr(2))
      else begin
        SuccessfulExport(320,180,4710);
        SuccessfulExport(1920,1080,60);
        FailureDiagnostic;
      end;
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Checks.ToJSON,TEncoding.UTF8);
      Writeln('PASS checks=',Checks.Count,'; no audio playback or VOICEVOX calls');
    except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message); Halt(1); end; end;
  finally Checks.Free; end;
end.
