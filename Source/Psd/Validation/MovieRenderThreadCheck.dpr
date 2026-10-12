program MovieRenderThreadCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils, System.Types,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmMovieText, RigmMovieModel, RigmMovieComposition, RigmMovieCompositor;
var Root: string; Checks: Integer;
procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create(Name);
  Inc(Checks); Writeln('PASS ',Name); Flush(Output);
end;
procedure CollectWhile(const Work: TProc; const Name: string);
var Done: Integer; Failure: string;
begin
  Done := 0; Failure := '';
  var T := TThread.CreateAnonymousThread(procedure
    begin
      try Work(); except on E: Exception do Failure := E.ClassName+': '+E.Message; end;
      TInterlocked.Exchange(Done,1);
    end);
  T.FreeOnTerminate := False; T.Start;
  var Collections := 0;
  while TInterlocked.CompareExchange(Done,0,0)=0 do begin FreeMemoryContexts; Inc(Collections); Sleep(0); end;
  T.WaitFor; T.Free;
  Check(Failure='',Name+' (VCL context collections='+IntToStr(Collections)+'): '+Failure);
end;
procedure LabelFrames(LockDestination: Boolean);
begin
  var B := TBitmap.Create;
  try
    B.PixelFormat := pf32bit; B.SetSize(600,140);
    if LockDestination then B.Canvas.Lock;
    try
      B.Canvas.Font.Name := 'Yu Gothic UI'; B.Canvas.Font.Height := -24; B.Canvas.Font.Color := clWhite;
      for var I := 1 to 4700 do begin
        B.Canvas.Brush.Color := clAqua; B.Canvas.FillRect(Rect(0,0,600,140));
        DrawMovieLabel(B.Canvas,'章名と補足文',Rect(20,20,580,120),DT_LEFT);
      end;
    finally if LockDestination then B.Canvas.Unlock; end;
  finally B.Free; end;
end;
function Project(W,H: Integer): TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create; Result.Width := W; Result.Height := H; Result.Fps := 30;
  Result.FileName := TPath.Combine(Root,'owned.rigmovie');
  var S := TRigmMovieScene.Create; Result.Scenes.Add(S); S.Title := '章名';
  S.Description := '無音の描画検証'; S.DisplayMode := 'both'; S.Image := TPath.Combine(Root,'generated.png');
  var C := TRigmMovieCue.Create; Result.Cues.Add(C); C.Scene := S.Id; C.Text := ''; C.Pause := 157;
  C.Subtitle := '字幕の描画'; C.AudioSeconds := 0; C.WaveFile := ''; C.LabFile := '';
end;
procedure CompositionFrames(W,H,Count: Integer);
begin
  var P := Project(W,H);
  try
    for var I := 0 to Count-1 do begin
      var B := RenderComposition(P,I/30,nil);
      try if (B.Width<>W) or (B.Height<>H) then raise Exception.Create('Frame dimensions changed');
      finally B.Free; end;
    end;
  finally P.Free; end;
end;
procedure Pixels;
begin
  var B := TBitmap.Create;
  try
    B.PixelFormat := pf32bit; B.SetSize(600,140); B.Canvas.Font.Name := 'Yu Gothic UI';
    B.Canvas.Font.Height := -24; B.Canvas.Font.Color := clWhite;
    B.Canvas.Brush.Color := clAqua; B.Canvas.FillRect(Rect(0,0,600,140));
    Check(DrawMovieLabel(B.Canvas,'短い章名',Rect(20,20,580,120),DT_LEFT)>0,'label draws');
    var Pixel := ColorToRGB(B.Canvas.Pixels[18,18]);
    Check((GetRValue(Pixel)=0) and (Abs(Integer(GetGValue(Pixel))-89)<=2) and
      (Abs(Integer(GetBValue(Pixel))-89)<=2),'65 percent black backdrop preserves transparency');
    Check(ColorToRGB(B.Canvas.Pixels[500,20])=ColorToRGB(clAqua),'unused area keeps original colour');
    var PNG := TPngImage.Create;
    try PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'label.png')); finally PNG.Free; end;
    B.Canvas.Brush.Color := clAqua; B.Canvas.FillRect(Rect(0,0,600,140));
    DrawMovieLabel(B.Canvas,'',Rect(20,20,580,120),DT_LEFT);
    Check(ColorToRGB(B.Canvas.Pixels[18,18])=ColorToRGB(clAqua),'empty label has no backdrop');
    PNG := TPngImage.Create;
    try PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'generated.png')); finally PNG.Free; end;
  finally B.Free; end;
end;
procedure Diagnostic;
begin
  var C := TCanvas.Create; var Found := False;
  try
    C.Handle := HDC($12345678); C.Font.Height := -20;
    try DrawMovieText(C,'診断',Rect(0,0,100,50),DT_LEFT);
    except on E: EOSError do Found := E.Message.Contains('SaveDC') and (E.ErrorCode<>0); end;
  finally C.Handle := 0; C.Free; end;
  Check(Found,'invalid owned DC reports API name and Win32 code');
end;
begin
  try
    Root := ParamStr(1); if Root='' then raise Exception.Create('Owned output directory required'); ForceDirectories(Root);
    Pixels; Diagnostic;
    CollectWhile(procedure begin CompositionFrames(320,180,1); end,'warm thumbnail and image/font cache');
    CollectWhile(procedure begin CompositionFrames(1920,1080,1); end,'warm full-HD font cache');
    FreeMemoryContexts; var Before := GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS);
    Writeln('Warm baseline GDI=',Before); Flush(Output);
    CollectWhile(procedure begin LabelFrames(True); end,'4700 label frames with destination locked');
    CollectWhile(procedure begin LabelFrames(False); end,'4700 label frames with destination managed by helper');
    CollectWhile(procedure begin CompositionFrames(320,180,4700); end,'4700 composited silent frames');
    CollectWhile(procedure begin CompositionFrames(1920,1080,100); end,'100 full-HD composited silent frames');
    // Compare repeated worker lifetimes after every rendering mode has warmed its caches.
    FreeMemoryContexts; var BeforeTurnover := GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS);
    Writeln('Before worker turnover GDI=',BeforeTurnover); Flush(Output);
    for var I := 1 to 20 do CollectWhile(procedure begin CompositionFrames(320,180,5); end,'worker turnover '+IntToStr(I));
    var After := GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS);
    Check(After<=BeforeTurnover+1,Format('worker turnover does not grow GDI objects before=%d after=%d (cold warmup=%d)',[BeforeTurnover,After,Before]));
    Writeln('PASS checks=',Checks,'; audio decoding, encoding and playback were not called');
  except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message); Halt(1); end; end;
end.