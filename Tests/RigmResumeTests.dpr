program RigmResumeTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage, RIGMMakerMainForm, RigmEditorForm,
  RigmMovieForm, RigmMovieSession, RigmMovieTimeline, RigmMovieModel, RigmMovieWorkflow,
  RigmAppSettings, RigmJson;
var Checks: TJSONArray; Root,Source,SourceHash: string;
  Metrics: TJSONObject;
function NativePrintWindow(Window: HWND; DC: HDC; Flags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
function Find(Parent: TWinControl; const Name: string): TControl;
begin Result := nil; for var I := 0 to Parent.ControlCount-1 do begin var C := Parent.Controls[I]; if C.Name=Name then Exit(C); if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end; end; end;
procedure Pump(Ms: Cardinal=100);
begin var UntilAt := GetTickCount64+Ms; repeat Application.ProcessMessages; Sleep(5); until GetTickCount64>=UntilAt; end;
procedure Exec(S: TRigmMovieSession; const Name: string; Args: TJSONObject=nil);
begin
  if Args=nil then Args := TJSONObject.Create;
  try Args.AddPair('projectId',S.Project.Id); AddN(Args,'revision',S.Project.Revision); var R := S.Execute(Name,Args); R.Free; finally Args.Free; end;
end;
procedure Open(S: TRigmMovieSession; const Path: string);
begin var O := TJSONObject.Create; O.AddPair('path',Path); Exec(S,'open',O); end;
procedure Settled(M: TRigmMovieForm);
begin
  var UntilAt := GetTickCount64+30000;
  repeat Pump(40); if not M.Session.Busy and not M.PreviewPending then begin Pump(250); if not M.Session.Busy and not M.PreviewPending then Exit; end; until GetTickCount64>=UntilAt;
  raise Exception.Create('Preview did not settle');
end;
procedure Capture(F: TForm; const Path: string);
begin
  var B := Vcl.Graphics.TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(F.ClientWidth,F.ClientHeight); F.PaintTo(B.Canvas.Handle,0,0); NativePrintWindow(F.Handle,B.Canvas.Handle,3); P.Assign(B); P.SaveToFile(Path); finally P.Free; B.Free; end;
end;
function Cpu100ns: UInt64;
var A,B,K,U: TFileTime;
begin
  GetProcessTimes(GetCurrentProcess,A,B,K,U);
  Result := (UInt64(K.dwHighDateTime) shl 32)+K.dwLowDateTime+(UInt64(U.dwHighDateTime) shl 32)+U.dwLowDateTime;
end;
procedure Tests;
var P: TRigmMovieProject; S,Q: TRigmMovieSession; M: TRigmMovieForm; L: TMainForm;
  Settings: TRigmAppSettings; A: TJSONArray; O: TJSONObject; Path,CopyHash,CueId: string;
begin
  SourceHash := THashSHA2.GetHashStringFromFile(Source);
  Check(SameText(RigmDocumentsDirectory,TPath.Combine(TPath.GetDocumentsPath,'RIGMMaker')),'settings root resolves the Windows Documents known folder');
  P := LoadMovie(Source); Path := TPath.Combine(Root,'resume-copy.rigmovie');
  try SaveMovie(P,Path); finally P.Free; end;
  CopyHash := THashSHA2.GetHashStringFromFile(Path);
  Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'creating portable test copy leaves original project intact');
  S := TRigmMovieSession.Create; M := nil; L := nil;
  try
    Open(S,Path); Check(not S.Project.Modified and not S.Playing,'successful open stays stopped and clean without synthesis or export');
    A := AppSettings.Recent; try Check((A.Count=1) and SameText(JS(TJSONObject(A[0]),'path'),Path),'successful movie open records actual path in MRU'); finally A.Free; end;
    M := TRigmMovieForm.CreateForSession(nil,S); M.Show; Settled(M);
    var Preview := TRigmMoviePreview(Find(M,'MoviePreviewImage'));
    var Timeline := TRigmMovieTimeline(Find(M,'MovieWaveTimeline'));
    var Seek := TTrackBar(Find(M,'MovieSeek'));
    var Play := TButton(Find(M,'MovieTransportPlay')); var Stop := TButton(Find(M,'MovieTransportStop'));
    Check(Play.Visible and Stop.Visible and (Pos('再生',Play.Caption)>0) and (Pos('停止',Stop.Caption)>0),'named play and stop remain visible next to the preview');
    Check(Play.Enabled and not Stop.Enabled,'stopped transport exposes the correct enabled states');
    var Before := M.ViewRefreshCount; var StaticCount := Timeline.StaticBuildCount; var Requests := M.PreviewRequests;
    for var I := 1 to 80 do begin Seek.Position := 10+I*5; if Assigned(Seek.OnChange) then Seek.OnChange(Seek); Pump(6); end;
    Seek.Position := 650; if Assigned(Seek.OnChange) then Seek.OnChange(Seek); Settled(M);
    Check(Abs(S.Time-S.Project.Duration*0.65)<0.00001,'continuous seeks retain the most recent requested position');
    Check(Floor(S.FrameTime*S.Project.Fps)=Floor(S.Time*S.Project.Fps),'last displayed job belongs to the requested frame');
    Check(M.ViewRefreshCount=Before,'seeking does not rebuild property editors');
    Check(Timeline.StaticBuildCount=StaticCount,'seeking retains waveform and timeline background cache');
    Check(M.PreviewRequests-Requests<15,'continuous seeks coalesce expensive image generation');
    AddN(Metrics,'seekRequests',M.PreviewRequests-Requests);
    Pump(1200); var Paints := Preview.PaintCount; var Frames := Preview.FrameCount;
    var TimelinePaints := Timeline.PaintCount; Requests := M.PreviewRequests; Before := M.ViewRefreshCount; var CPU := Cpu100ns;
    Pump(2200); var CPUms := (Cpu100ns-CPU)/10000.0;
    AddN(Metrics,'idleCpuMillisecondsOver2200ms',CPUms); AddN(Metrics,'idlePreviewPaints',Preview.PaintCount-Paints);
    AddN(Metrics,'idleTimelinePaints',Timeline.PaintCount-TimelinePaints);
    Check((Preview.FrameCount=Frames) and (M.PreviewRequests=Requests),'stopped preview submits no recurring render jobs or bitmap updates');
    Check((Preview.PaintCount-Paints<=2) and (Timeline.PaintCount-TimelinePaints<=2),'stopped preview and timeline do not continuously repaint');
    Check(M.ViewRefreshCount=Before,'stopped timer does not rebuild editors');
    Check(CPUms<450,'stopped studio uses under 450ms CPU across 2200ms observation');
    if Assigned(Seek.OnChange) then Seek.OnChange(Seek); Settled(M);
    Check(M.PreviewRequests=Requests,'repeating a seek to the same frame suppresses image regeneration');
    for var DPI in [96,120,144,192,96] do begin
      M.ScaleForPPI(DPI); M.Width := MulDiv(1040,DPI,96); M.Height := MulDiv(720,DPI,96); Pump(100);
      Check(Play.Visible and Stop.Visible and (Play.Left>=0) and (Stop.Left+Stop.Width<=Stop.Parent.ClientWidth), 'transport fits minimum width at '+DPI.ToString+' DPI');
      Check(Play.Height>=MulDiv(26,DPI,96),'transport touch size at '+DPI.ToString+' DPI');
    end;
    Play.Click; Pump(1500); Check(S.Playing and Stop.Enabled and not Play.Enabled,'visible play starts existing saved speech playback');
    Check(S.Time>S.Project.Duration*0.65,'playback advances from selected position');
    Stop.Click; Settled(M); var Stopped := S.Time; Pump(500);
    Check(not S.Playing and SameValue(Stopped,S.Time,0.000001),'visible stop freezes the clock');
    Check(THashSHA2.GetHashStringFromFile(Path)=CopyHash,'seek and playback never auto-save the project');
    AppSettings.RememberPosition(S.Project,S.Time,S.Project.Cues[0].Id);
    Q := TRigmMovieSession.Create;
    try Open(Q,Path); Check(Q.Time=0,'fresh session always opens at time zero'); Check(Q.ResumeCue=S.Project.Cues[0].Id,'fresh session selects the first cue'); finally Q.Free; end;
    A := AppSettings.Recent; try Check(A.Count=1,'reopening and casing variants deduplicate the recent path'); finally A.Free; end;
    Capture(M,TPath.Combine(Root,'studio.png'));
    L := TMainForm.Create(nil); L.Show; Pump(150);
    var Recent := TListView(Find(L,'RecentWorks')); var Resume := TButton(Find(L,'ResumeRecentWork'));
    Check((Recent.Items.Count=1) and Resume.Enabled,'main screen exposes the recent work and resume action');
    TMemo(Find(M,'MovieCueText')).Text := 'unsaved pending input protected during resume'; var Unsaved := TMemo(Find(M,'MovieCueText')).Text;
    Resume.Click; Pump(500);
    Check(TMemo(Find(M,'MovieCueText')).Text=Unsaved,'main history resume preserves pending edits in the existing studio');
    var Host: TRigmEditorForm := nil;
    for var I := 0 to L.ComponentCount-1 do if L.Components[I] is TRigmEditorForm then Host := TRigmEditorForm(L.Components[I]);
    Check((Host<>nil) and SameText(Host.Editor.Movie.Project.FileName,Path),'main history opens a new editor with the requested movie');
    Check(Host.Editor.Movie.Project.WorkflowStage=S.Project.WorkflowStage,'main history restores coherent workflow stage');
    var OpenState := Host.Editor.Movie.Status;
    try Check(not Host.Editor.Movie.Playing and ((not Host.Editor.Movie.Busy) or (JS(JO(OpenState,'job'),'kind')='preview')),'history resume stays stopped while its initial frame renders'); finally OpenState.Free; end;
    Capture(L,TPath.Combine(Root,'main-history.png'));
    TFile.Move(Path,Path+'.held');
    try Pump(1300); Check(not Resume.Enabled and (Pos('ファイルなし',Recent.Items[0].Caption)>0),'missing history path stays visible with resume disabled'); finally TFile.Move(Path+'.held',Path); end;
    L.Free; L := nil;
    // Failed opens cannot enter history or discard the current document.
    var Id := S.Project.Id;
    try Open(S,TPath.Combine(Root,'absent.rigmovie')); except on E: Exception do Check(S.Project.Id=Id,'failed open preserves active project'); end;
    A := AppSettings.Recent; try Check(A.Count=1,'failed open adds no history item'); finally A.Free; end;
    var Legacy := TPath.Combine(Root,'Legacy'); ForceDirectories(Legacy);
    TFile.WriteAllText(TPath.Combine(Legacy,'history.ini'),'[Opened]'+sLineBreak+'0='+Path+sLineBreak+'[Saved]'+sLineBreak+'0='+UpperCase(Path),TEncoding.UTF8);
    var IniHash := THashSHA2.GetHashStringFromFile(TPath.Combine(Legacy,'history.ini'));
    Settings := TRigmAppSettings.Create(Legacy);
    try A := Settings.Recent; try Check((A.Count=1) and SameText(JS(TJSONObject(A[0]),'path'),Path),'legacy opened and saved histories merge without duplicates'); finally A.Free; end; finally Settings.Free; end;
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(Legacy,'history.ini'))=IniHash,'migration retains the legacy INI unchanged');
    Check(THashSHA2.GetHashStringFromFile(Path)=CopyHash,'migration does not move or overwrite project and assets');
    var Corrupt := TPath.Combine(Root,'Corrupt'); ForceDirectories(Corrupt); TFile.WriteAllText(TPath.Combine(Corrupt,'settings.json'),'broken',TEncoding.UTF8);
    Settings := TRigmAppSettings.Create(Corrupt);
    try Settings.RecordMovie(S.Project,S.Time); Check(TFile.ReadAllText(TPath.Combine(Corrupt,'settings.json'),TEncoding.UTF8)='broken','corrupt settings are preserved instead of overwritten'); finally Settings.Free; end;
    P := LoadMovie(Path);
    try P.Title := 'external change'; SaveMovie(P,Path); Q := TRigmMovieSession.Create; try Open(Q,Path); Check(Q.Time=0,'externally changed file does not restore obsolete cursor state'); finally Q.Free; end; finally P.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'all resume tests leave the original work unchanged');
  finally L.Free; M.Free; S.Free; end;
end;
begin
  Root := GetEnvironmentVariable('RIGMMAKER_RESUME_TEST_ROOT'); Source := GetEnvironmentVariable('RIGMMAKER_RESUME_TEST_SOURCE'); ForceDirectories(Root);
  Checks := TJSONArray.Create; Metrics := TJSONObject.Create;
  try
    Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark');
    try Tests; except on E: Exception do begin Writeln(E.Message); Checks.Add(E.Message); ExitCode := 1; end; end;
    var O := TJSONObject.Create;
    try AddB(O,'success',ExitCode=0); AddN(O,'passed',Checks.Count-Ord(ExitCode<>0)); O.AddPair('checks',Checks); Checks := nil;
      O.AddPair('metrics',Metrics); Metrics := nil; O.AddPair('directory',Root); O.AddPair('source',Source); O.AddPair('sourceSha256',SourceHash);
      AddB(O,'desktopScreenshotVerified',False); AddB(O,'physicalMonitorTransitionVerified',False);
      TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),'resume-results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally Checks.Free; Metrics.Free; end;
end.
