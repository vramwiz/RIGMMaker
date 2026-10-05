// 単一キャラクターの時刻別姿勢と動画フレームを生成する。複数キャラクターの合成はCompositorへ委譲する。
unit RigmMovieRendering;

interface
uses System.SysUtils, System.JSON, Vcl.Graphics, RigmModel, RigmMovieModel, RigmMovieAudio;

procedure MoviePose(Project: TRigmMovieProject; Document: TRigmDocument; Seconds: Double;
  Audio: TRigmPcm; Pose: TRigmPose);
function RenderMovieFrame(Project: TRigmMovieProject; Document: TRigmDocument;
  Seconds: Double; Audio: TRigmPcm = nil): Vcl.Graphics.TBitmap;

function MovieSubtitlePage(const Text: string; Canvas: TCanvas; Width,Lines: Integer;
  Progress: Double; out PageCount: Integer): string;

implementation
uses System.Math, System.Types, System.Classes, Winapi.Windows, RigmRenderer, RigmJson,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, RigmMoviePhonemes, RigmMovieCompositor, RigmMovieActing,
  RigmCharacterCatalog, RigmMovieComposition, RigmMoviePsdRendering;

function MovieSubtitlePage(const Text: string; Canvas: TCanvas; Width,Lines: Integer;
  Progress: Double; out PageCount: Integer): string;
var Wrapped,Pages: TStringList; Line,Page,Glyph: string; Used,I,Count: Integer;
  procedure Emit;
  begin Wrapped.Add(Line); Line := ''; Used := 0; end;
begin
  Wrapped := TStringList.Create; Pages := TStringList.Create;
  try
    Line := ''; Used := 0; I := 1;
    while I<=Length(Text) do begin
      Count := 1;
      if (Ord(Text[I])>=$D800) and (Ord(Text[I])<=$DBFF) and (I<Length(Text)) and
        (Ord(Text[I+1])>=$DC00) and (Ord(Text[I+1])<=$DFFF) then Count := 2;
      Glyph := Copy(Text,I,Count); Inc(I,Count);
      if Glyph=#13 then Continue;
      if Glyph=#10 then begin Emit; Continue; end;
      var GWidth := Canvas.TextWidth(Glyph);
      if (Line<>'') and (Used+GWidth>Width) then Emit;
      Line := Line+Glyph; Inc(Used,GWidth);
    end;
    if (Line<>'') or (Wrapped.Count=0) then Emit;
    Page := '';
    for I := 0 to Wrapped.Count-1 do begin
      if Page<>'' then Page := Page+sLineBreak; Page := Page+Wrapped[I];
      if ((I+1) mod Max(1,Lines)=0) or (I=Wrapped.Count-1) then begin Pages.Add(Page); Page := ''; end;
    end;
    PageCount := Pages.Count; Result := Pages[EnsureRange(Floor(EnsureRange(Progress,0.0,0.999999)*PageCount),0,PageCount-1)];
  finally Pages.Free; Wrapped.Free; end;
end;

procedure MoviePose(Project: TRigmMovieProject; Document: TRigmDocument; Seconds: Double;
  Audio: TRigmPcm; Pose: TRigmPose);
var Local, Start, Head, Body, Eyes, Gain, MouthTime,BlinkOpen: Double; C: TRigmMovieCue;
begin
  Pose.Reset; C := Project.CueAt(Seconds,Local,Start); if C=nil then Exit;
  Head := 0; Body := 0; Eyes := 1;
  if C.Motion<>'still' then begin
    Head := Sin(Seconds*1.4)*4; Body := Sin(Seconds*0.9)*2;
    if C.Motion='nod' then Head := Head+Sin(Local*4)*6*Exp(-Local*0.6);
    if C.Motion='emphasis' then Body := Body+Sin(Local*2.5)*6*Exp(-Local*0.3);
  end;
  if C.Expression='smile' then begin Eyes := 0.75; Head := Head+2; end;
  if C.Expression='serious' then Head := Head-1;
  if C.Expression='sad' then begin Eyes := 0.7; Head := Head-3; Body := Body-2; end;
  Gain := C.Acting.Gain(Local,Project.CueDuration(C));
  Head := Head*C.Acting.HeadGain*Gain; Body := Body*C.Acting.BodyGain*Gain;
  BlinkOpen := MovieBlinkOpen(Seconds,C.Acting.BlinkInterval,C.Acting.BlinkDuration,
    C.Acting.BlinkPhase,C.Acting.BlinkStrength,Gain,Project.Fps);
  Eyes := Eyes*BlinkOpen;
  C.Acting.ApplyVariants(Document,Pose);
  Pose.Values.AddOrSetValue('headAngle',Head); Pose.Values.AddOrSetValue('bodyAngle',Body);
  Pose.Values.AddOrSetValue('eyeOpen',EnsureRange(Eyes,0.0,1.0));
  MouthTime := Local+C.Acting.LipLead;
  if (Audio<>nil) and (MouthTime>=0) and (MouthTime<C.AudioSeconds) and (Local<C.AudioSeconds) then
    Pose.Values.AddOrSetValue('mouthOpen',EnsureRange(Audio.Envelope(Start+MouthTime)*C.Acting.MouthGain*Gain,0.0,1.0))
  else Pose.Values.AddOrSetValue('mouthOpen',0);
  for var Pair in C.Parameters do begin
    for var P in Document.Parameters do if P.Id=Pair.JsonString.Value then begin
      var Value := TJSONNumber(Pair.JsonValue).AsDouble;
      Pose.Values.AddOrSetValue(P.Id,EnsureRange(Value,P.Minimum,P.Maximum)); Break;
    end;
  end;
  if C.Parameters.GetValue('eyeOpen')<>nil then BlinkOpen := Pose.Value('eyeOpen');
  var PhonemesAvailable := False;
  if (MouthTime>=0) and (MouthTime<C.AudioSeconds) and (Local<C.AudioSeconds) then begin
    var Phone: string;
    var Mouth := MoviePhonemeSample(ResolveMoviePath(Project.FileName,C.LabFile),MouthTime,Phone,PhonemesAvailable);
    if PhonemesAvailable then begin
      Pose.Values.AddOrSetValue('mouthOpen',EnsureRange(Mouth*C.Acting.MouthGain*Gain,0.0,1.0));
      if Length(Phone)=1 then Pose.Values.AddOrSetValue('mouthPhoneme',Ord(Phone[1]));
    end;
  end;
  C.Acting.ApplyFeatureAssets(Document,Pose,Pose.Value('mouthOpen'),BlinkOpen);
end;
function RenderMovieFrame(Project: TRigmMovieProject; Document: TRigmDocument;
  Seconds: Double; Audio: TRigmPcm): Vcl.Graphics.TBitmap;
var Pose: TRigmPose; Pixels: TBytes; W,H,L,T,X,Y,P,Q,A: Integer; Row: PByte;
  C: TRigmMovieCue; Local, Start: Double; Picture: TPicture; R: TRect; Info: TBitmapInfo;
  DC: HDC; Dib,Previous: HGDIOBJ; Bits: Pointer; CaptionCanvas: TCanvas;
begin
  if (Project.Characters.Count=0) and (CharacterFormat(Project.CharacterFile)='psd') then begin
    var Copy := Project.Clone;
    try
      var Actor := TRigmMovieCharacter.Create; Copy.Characters.Add(Actor); Actor.FileName := ResolveMoviePath(Project.FileName,Project.CharacterFile);
      Actor.RenderFormat := 'psd'; Actor.X := 700; Actor.Y := 80; Actor.Width := 520; Actor.Height := 950;
      if Copy.Cues.Count>0 then Actor.SpeakerId := Copy.Cues[0].SpeakerId;
      Actor.Expressions.Free; Actor.Expressions := PsdMovieExpressions(Actor.FileName);
      Exit(RenderComposition(Copy,Seconds,Audio));
    finally Copy.Free; end;
  end;
  if (Project.Scenes.Count>0) or (Project.Characters.Count>0) then Exit(RenderComposition(Project,Seconds,Audio));
  Result := Vcl.Graphics.TBitmap.Create; Pose := TRigmPose.Create;
  try
   try
    Result.PixelFormat := pf32bit; Result.SetSize(Project.Width,Project.Height);
    Result.Canvas.Brush.Color := TColor(Project.BackgroundColor); Result.Canvas.FillRect(Rect(0,0,Project.Width,Project.Height));
    C := Project.CueAt(Seconds,Local,Start);
    if (C<>nil) and (C.Background<>'') then begin
      Picture := TPicture.Create;
      try
        Picture.LoadFromFile(ResolveMoviePath(Project.FileName,C.Background));
        if (Picture.Width<1) or (Picture.Height<1) then raise ERigm.Create('背景画像が空です。');
        var Scale := Max(Project.Width/Picture.Width,Project.Height/Picture.Height);
        var BW := Round(Picture.Width*Scale); var BH := Round(Picture.Height*Scale);
        Result.Canvas.StretchDraw(Rect((Project.Width-BW) div 2,(Project.Height-BH) div 2,(Project.Width+BW) div 2,(Project.Height+BH) div 2),Picture.Graphic);
      finally Picture.Free; end;
    end;
    if Document<>nil then begin
      MoviePose(Project,Document,Seconds,Audio,Pose);
      Pixels := RenderRigm(Document,Pose,Round(Project.Height*0.88),W,H);
      L := (Project.Width-W) div 2; T := Max(0,(Project.Height-H) div 2-Project.Height div 30);
      for Y := 0 to H-1 do if (Y+T>=0) and (Y+T<Project.Height) then begin
        Row := Result.ScanLine[Y+T];
        for X := 0 to W-1 do if (X+L>=0) and (X+L<Project.Width) then begin
          P := (Y*W+X)*4; Q := (X+L)*4; A := Pixels[P+3];
          for var Channel := 0 to 2 do Row[Q+2-Channel] := (Pixels[P+Channel]*A+Row[Q+2-Channel]*(255-A)+127) div 255;
          Row[Q+3] := 255;
        end;
      end;
    end;
    if C<>nil then begin
      // Use a dedicated DIB/DC for captions. VCL's bitmap canvas can detach its
      // cached handle after ScanLine writes, leaving the GDI text in another image.
      GdiFlush; DC := CreateCompatibleDC(0); Dib := 0; Previous := 0; CaptionCanvas := nil;
      try
        Info := Default(TBitmapInfo); Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
        Info.bmiHeader.biWidth := Project.Width; Info.bmiHeader.biHeight := -Project.Height;
        Info.bmiHeader.biPlanes := 1; Info.bmiHeader.biBitCount := 32; Info.bmiHeader.biCompression := BI_RGB;
        Dib := CreateDIBSection(DC,Info,DIB_RGB_COLORS,Bits,0,0);
        if (DC=0) or (Dib=0) or (Bits=nil) then RaiseLastOSError;
        Previous := SelectObject(DC,Dib);
        for Y := 0 to Project.Height-1 do Move(Result.ScanLine[Y]^,PByte(Bits)[Y*Project.Width*4],Project.Width*4);
        CaptionCanvas := TCanvas.Create; CaptionCanvas.Handle := DC;
      CaptionCanvas.Font.Name := 'Yu Gothic UI'; CaptionCanvas.Font.Height := -Max(16,Project.Height div 24);
      CaptionCanvas.Font.Color := clWhite; CaptionCanvas.Font.Style := [fsBold];
      CaptionCanvas.Brush.Color := $251E18;
      R := Rect(Project.Width div 20,Project.Height*78 div 100,Project.Width*19 div 20,Project.Height*96 div 100);
      CaptionCanvas.FillRect(R); InflateRect(R,-Project.Width div 40,-Project.Height div 80);
      var Lines := Max(1,R.Height div Max(1,CaptionCanvas.TextHeight('あ')));
      var PageCount: Integer;
      var Subtitle := MovieSubtitlePage(C.Subtitle,CaptionCanvas,R.Width,Lines,
        Local/Max(0.001,Project.CueDuration(C)),PageCount);
      SetTextColor(DC,RGB(255,255,255)); SetBkMode(DC,TRANSPARENT);
      if (Subtitle<>'') and (DrawText(DC,PChar(Subtitle),Length(Subtitle),R,DT_CENTER or DT_NOPREFIX)=0) then
        raise ERigm.CreateFmt('字幕描画に失敗しました (Windows %d)。',[GetLastError]);
      CaptionCanvas.Brush.Style := bsClear; CaptionCanvas.Font.Height := -Max(14,Project.Height div 32);
      CaptionCanvas.TextHeight('あ');
      R := Rect(Project.Width div 30,Project.Height div 30,Project.Width*29 div 30,Project.Height div 7);
      SetTextColor(DC,RGB(255,255,255)); SetBkMode(DC,TRANSPARENT);
      if (C.Scene<>'') and (DrawText(DC,PChar(C.Scene),Length(C.Scene),R,DT_LEFT or DT_WORDBREAK or DT_NOPREFIX)=0) then
        raise ERigm.CreateFmt('シーン名描画に失敗しました (Windows %d)。',[GetLastError]);
        GdiFlush;
        for Y := 0 to Project.Height-1 do Move(PByte(Bits)[Y*Project.Width*4],Result.ScanLine[Y]^,Project.Width*4);
      finally
        if CaptionCanvas<>nil then begin CaptionCanvas.Handle := 0; CaptionCanvas.Free; end;
        if Previous<>0 then SelectObject(DC,Previous);
        if Dib<>0 then DeleteObject(Dib); if DC<>0 then DeleteDC(DC);
      end;
    end;
    GdiFlush; // Publish completed GDI text pixels before the worker's DIB is read by another thread.
   except Result.Free; raise; end;
  finally Pose.Free; end;
end;
end.
