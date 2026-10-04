program RigmUiRevisionTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.Math, System.Generics.Collections,
  System.Types, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Menus, Vcl.Themes, Vcl.Styles, Vcl.Graphics, Vcl.Imaging.pngimage, RIGMMakerMainForm,
  RigmMovieModel, RigmMovieSession, RigmMovieForm, RigmMovieTimeline, RigmMovieHistory, RigmAppSettings,
  RigmPropertyScrollBox, RigmJson;
type
  TObserver = class
    Control: TWinControl;
    Previous: TWndMethod;
    Paints,Erases: Integer;
    Children: TObjectList<TObserver>;
    constructor Create(C: TWinControl);
    destructor Destroy; override;
    procedure Message(var M: TMessage);
    function TotalPaints: Integer;
  end;
  TErrors = class
    procedure Handle(Sender: TObject; E: Exception);
  end;
var Root,Source,AsyncError: string; Checks,Metrics: TJSONArray;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); Flush(Output); end;
constructor TObserver.Create(C: TWinControl);
begin
  inherited Create; Control := C; Previous := C.WindowProc; C.WindowProc := Message;
  Children := TObjectList<TObserver>.Create(True);
  for var I := 0 to C.ControlCount-1 do if C.Controls[I] is TWinControl then Children.Add(TObserver.Create(TWinControl(C.Controls[I])));
end;
destructor TObserver.Destroy;
begin Children.Free; Control.WindowProc := Previous; inherited; end;
procedure TObserver.Message(var M: TMessage);
begin if M.Msg=WM_PAINT then Inc(Paints); if M.Msg=WM_ERASEBKGND then Inc(Erases); Previous(M); end;
function TObserver.TotalPaints: Integer;
begin Result := Paints; for var Child in Children do Inc(Result,Child.TotalPaints); end;
procedure TErrors.Handle(Sender: TObject; E: Exception);
begin AsyncError := E.ClassName+': '+E.Message; Writeln('ASYNC ERROR: '+AsyncError); Flush(Output); end;
procedure Pump(Ms: Cardinal);
begin var UntilTick := GetTickCount64+Ms; repeat Application.ProcessMessages; if AsyncError<>'' then raise Exception.Create(AsyncError); Sleep(5); until GetTickCount64>=UntilTick; end;
function Find(P: TWinControl; const Name: string): TControl;
begin
  Result := nil; for var I := 0 to P.ControlCount-1 do begin
    var C := P.Controls[I]; if C.Name=Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end;
  end;
end;
function Studio(P: TWinControl): TRigmMovieForm;
begin
  Result := nil; for var I := 0 to P.ControlCount-1 do begin
    var C := P.Controls[I]; if (C is TRigmMovieForm) and C.Visible then Exit(TRigmMovieForm(C));
    if C is TWinControl then begin Result := Studio(TWinControl(C)); if Result<>nil then Exit; end;
  end;
end;
procedure WaitIdle(M: TRigmMovieForm);
begin
  var Deadline := GetTickCount64+15000;
  repeat Pump(40); until (not M.Session.Busy and not M.PreviewPending) or (GetTickCount64>Deadline);
  Check(not M.Session.Busy and not M.PreviewPending,'preview settles without an exception or blocked worker');
end;
function Entry(const Path: string): TJSONObject;
begin Result := TJSONObject.Create; Result.AddPair('path',Path); Result.AddPair('title','same title'); Result.AddPair('accessed','2026-10-04T00:00:00Z'); end;
procedure HistoryTests;
begin
  var Dir := TPath.Combine(Root,'History'); ForceDirectories(TPath.Combine(Dir,'Recovery'));
  var A := TPath.Combine(Dir,'work-a.rigmovie'); var B := TPath.Combine(Dir,'work-b.rigmovie'); var C := TPath.Combine(Dir,'work-c.rigmovie');
  var Recovery := TPath.Combine(Dir,'Recovery\recovery-legacy.rigmovie');
  var P := LoadMovie(Source);
  try SaveMovie(P,A); var Snapshot := P.Clone; try SaveMovie(Snapshot,Recovery); finally Snapshot.Free; end;
    P.Id := TGUID.NewGuid.ToString; SaveMovie(P,B);
  finally P.Free; end;
  var BeforeA := THashSHA2.GetHashStringFromFile(A); var BeforeB := THashSHA2.GetHashStringFromFile(B); var BeforeR := THashSHA2.GetHashStringFromFile(Recovery);
  var Recent := TJSONArray.Create; Recent.AddElement(Entry(Recovery)); Recent.AddElement(Entry(A)); Recent.AddElement(Entry(UpperCase(A))); Recent.AddElement(Entry(B));
  var O := TJSONObject.Create;
  try O.AddPair('application','RIGMMaker'); O.AddPair('recent',Recent); TFile.WriteAllText(TPath.Combine(Dir,'settings.json'),O.ToJSON,TEncoding.UTF8); finally O.Free; end;
  var Settings := TRigmAppSettings.Create(Dir);
  try
    var R := Settings.Recent;
    try
      Check(R.Count=2,'legacy history deduplicates each actual file and excludes recovery copies');
      Check(SameText(JS(TJSONObject(R[0]),'path'),A) and SameText(JS(TJSONObject(R[1]),'path'),B),'same-folder works retain separate history entries');
      Check(TJSONObject(R[0]).GetValue('recovery')<>nil,'matching legacy recovery links to its unique original project ID');
    finally R.Free; end;
    R := Settings.Recoveries; try Check((R.Count=1) and SameText(JS(TJSONObject(R[0]),'sourcePath'),A),'recovery journal preserves its source association'); finally R.Free; end;
    var SettingsHash := THashSHA2.GetHashStringFromFile(TPath.Combine(Dir,'settings.json'));
    Settings.NormalizeHistory; Check(SettingsHash=THashSHA2.GetHashStringFromFile(TPath.Combine(Dir,'settings.json')),'history normalization is idempotent');
    Check((BeforeA=THashSHA2.GetHashStringFromFile(A)) and (BeforeB=THashSHA2.GetHashStringFromFile(B)) and (BeforeR=THashSHA2.GetHashStringFromFile(Recovery)),'normalization changes only history and preserves every work/recovery file');
    P := LoadMovie(A);
    try
      Settings.RecordMovie(P,2); Settings.RememberPosition(P,3,'cue'); P.WorkflowStage := 'setup'; Settings.RecordMovie(P,4);
      R := Settings.Recent; try Check((R.Count=2) and SameValue(JN(TJSONObject(R[0]),'time'),4),'page stage and cursor changes update one file entry'); finally R.Free; end;
      var Copy := P.Clone; try SaveMovie(Copy,C); Settings.RecordMovie(Copy,1); finally Copy.Free; end;
      R := Settings.Recent; try Check(R.Count=3,'Save-As files sharing a project ID remain separate ordinary files'); finally R.Free; end;
      var NewRecovery := TPath.Combine(Dir,'Recovery\recovery-new.rigmovie'); var Copy2 := P.Clone;
      try SaveMovie(Copy2,NewRecovery); Settings.RecordRecovery(P,NewRecovery,5,'cue'); finally Copy2.Free; end;
      R := Settings.Recent; try Check(R.Count=3,'automatic recovery creation never adds an ordinary history item'); finally R.Free; end;
      R := Settings.Recoveries; try Check(SameText(JS(TJSONObject(R[0]),'sourcePath'),A) or SameText(JS(TJSONObject(R[1]),'sourcePath'),A),'explicit recovery association stays exact despite ambiguous Save-As IDs'); finally R.Free; end;
      var Reopened := LoadMovie(NewRecovery);
      try Settings.RecordRecovery(Reopened,NewRecovery,6,'cue'); finally Reopened.Free; end;
      R := Settings.Recoveries;
      try
        var Found := False;
        for var V in R do if SameText(JS(TJSONObject(V),'path'),NewRecovery) then Found := SameText(JS(TJSONObject(V),'sourcePath'),A);
        Check(Found,'reopening a recovery retains its explicit original path despite shared Save-As IDs');
      finally R.Free; end;
    finally P.Free; end;
  finally Settings.Free; end;
end;
procedure CaptureUi(Form: TForm; const Name: string);
begin
  var Bitmap := Vcl.Graphics.TBitmap.Create; var Png := TPngImage.Create;
  try
    Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight); Form.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
procedure UiTests;
begin
  var L := TMainForm.Create(nil); var Toolbar,Properties: TObserver;
  Toolbar := nil; Properties := nil;
  try
    L.Show; ShowWindow(L.Handle,SW_SHOWNOACTIVATE);
    var A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'History\work-a.rigmovie'));
    try var Reply := L.ExecuteWorkspace('open-work',A); Reply.Free; finally A.Free; end;
    var M := Studio(L); Check(M<>nil,'workspace opens the actual embedded movie editor'); WaitIdle(M);
    Check(L.Menu<>nil,'normal workspace has a main menu');
    for var Name in ['MovieMenuAction1','MovieMenuAction2','MovieMenuAction37','RecentWorksMenu'] do Check(L.FindComponent(Name) is TMenuItem,'menu exposes '+Name);
    var FileMenu := TMenuItem(L.FindComponent('MovieFileMenu')); FileMenu.Click;
    var OrdinaryCount := TMenuItem(L.FindComponent('RecentWorksMenu')).Count;
    var RecoveryCount := TMenuItem(L.FindComponent('RecoveryWorksMenu')).Count;
    var RecoveryCopy := M.Session.Project.Clone;
    try
      RecoveryCopy.Id := TGUID.NewGuid.ToString;
      var Path := TPath.Combine(AppSettings.Root,'Recovery\recovery-ui-only.rigmovie');
      SaveMovie(RecoveryCopy,Path); AppSettings.RecordRecovery(RecoveryCopy,Path,0,''); FileMenu.Click;
    finally RecoveryCopy.Free; end;
    Check((TMenuItem(L.FindComponent('RecentWorksMenu')).Count=OrdinaryCount) and
      (TMenuItem(L.FindComponent('RecoveryWorksMenu')).Count=RecoveryCount+1),'recovery menu refreshes independently without adding an ordinary work entry');
    Check(not Find(L,'RecentWorkPanel').Visible,'large history panel stays hidden');
    Check(not Find(M,'MovieToolbar').Visible,'duplicate movie toolbar is not visible');
    Check(not Find(M,'MovieStatus').Visible and not Find(M,'MoviePlaybackState').Visible,'both recurring time and job status lines are absent');
    Check(TPanel(Find(M,'MovieTransport')).Caption='','transport never exposes its internal component name');
    var Right := TRigmPropertyScrollBox(Find(M,'MovieProperties'));
    Writeln('INITIAL DPI: main=',L.CurrentPPI,' movie=',M.CurrentPPI,' right=',Right.CurrentPPI,' hostWidth=',Find(M,'MoviePropertyHost').Width,' required=',L.ScaleValue(340)); Flush(Output);
    Check(Find(M,'MoviePropertyHost').Width>=L.ScaleValue(340),'actual startup embedded property pane uses the host DPI before any simulated scaling');
    Check(M.ScaleValue(96)=L.ScaleValue(96),'new embedded editor starts at the existing workspace DPI');
    Check(Find(M,'MoviePropertySplitter') is TSplitter,'right editor provides an adjustable splitter');
    TToolButton(Find(M,'MoviePropertiesScene')).Click; Pump(80);
    var Edit := TEdit(Find(M,'MovieSceneTitle')); var Text := Edit.Text; Edit.SetFocus; Edit.SelStart := Length(Text); Edit.SelText := '-pending'; Text := Edit.Text;
    for var DPI in [96,120,144,192,96] do for var Size in [640,850] do begin
      L.ScaleForPPI(DPI); L.Width := MulDiv(Size,DPI,96); L.Height := MulDiv(480,DPI,96); Pump(140);
      Check(L.ScaleValue(96)=DPI,'workspace simulated layout scale is '+DPI.ToString+'/'+Size.ToString);
      Check(Right.Width>=MulDiv(340,DPI,96),'right panel retains minimum width at '+DPI.ToString+'/'+Size.ToString);
      Check(Right.VertScrollBar.Range>Right.ClientHeight,'right properties remain vertically scrollable at '+DPI.ToString+'/'+Size.ToString);
      Check((Edit.Text=Text) and (GetFocus=Edit.Handle),'resize/DPI retains pending input and focus at '+DPI.ToString+'/'+Size.ToString);
      L.Canvas.Font.Assign(Edit.Font);
      Writeln('DPI layout: main=',L.CurrentPPI,' movie=',M.CurrentPPI,' right=',Right.CurrentPPI,' field=',Edit.CurrentPPI,' height=',Edit.ClientHeight,' text=',L.Canvas.TextHeight('Mg'));
      Check(Edit.ClientHeight>=L.Canvas.TextHeight('Mg'),'input text fits vertically at '+DPI.ToString+'/'+Size.ToString);
      var Timeline := TRigmMovieTimeline(Find(M,'MovieWaveTimeline'));
      Check(Timeline.Height>=Timeline.ScaleValue(96),'all four timeline tracks fit at '+DPI.ToString+'/'+Size.ToString);
      var Overlap := False; var Clipped := False;
      for var I := 0 to Right.ControlCount-1 do begin
        var First := Right.Controls[I]; if not First.Visible then Continue;
        if (First.Left<0) or (First.Left+First.Width>Right.ClientWidth) then begin Clipped := True; Writeln('CLIPPED: ',First.Name,' ',First.Left,'/',First.Width,' panel=',Right.ClientWidth); end;
        for var J := I+1 to Right.ControlCount-1 do begin var Second := Right.Controls[J]; var R: TRect;
          if Second.Visible and IntersectRect(R,First.BoundsRect,Second.BoundsRect) then begin Overlap := True; Writeln('OVERLAP: ',First.Name,' / ',Second.Name,' y=',First.Top,'/',Second.Top); end;
        end;
      end;
      Check(not Overlap and not Clipped,'labels and editors fit without overlap at '+DPI.ToString+'/'+Size.ToString);
      if (Size=640) and ((DPI=96) or (DPI=192)) then CaptureUi(L,'ui-narrow-'+DPI.ToString);
    end;
    Check((GetWindowLong(Right.Handle,GWL_STYLE) and WS_VSCROLL)<>0,'right properties expose a native vertical scrollbar');
    L.Width := 1200; L.Height := 800; Right.VertScrollBar.Position := 0; Pump(150);
    var Point := Edit.ClientToScreen(System.Types.Point(3,3));
    var Message: TMsg; ZeroMemory(@Message,SizeOf(Message)); Message.hwnd := Edit.Handle; Message.message := WM_MOUSEWHEEL;
    Message.wParam := WPARAM(Cardinal(Word(SmallInt(-WHEEL_DELTA))) shl 16); Message.lParam := MakeLParam(Point.X,Point.Y);
    PostMessage(Message.hwnd,Message.message,Message.wParam,Message.lParam); Pump(100);
    Check((Right.VertScrollBar.Position>0) and (Edit.Text=Text) and (GetFocus=Edit.Handle),'wheel over a child scrolls properties without changing input or focus');
    var Args := TJSONObject.Create;
    try
      var Reply := M.Session.Execute('waveform-refresh',Args); Reply.Free; WaitIdle(M);
      Reply := M.Session.PreviewFrame(0.5); Reply.Free;
      Reply := M.Session.Execute('job-retry',Args);
      try Check(JS(Reply,'kind')='waveform','automatic frame rendering never replaces the manual job retry target'); finally Reply.Free; end;
      WaitIdle(M);
      Reply := M.Session.PreviewFrame(0.6); Reply.Free;
      TMenuItem(L.FindComponent('MovieMenuAction2')).Click; WaitIdle(M);
      Check((Edit.Text=Text) and FileExists(M.Session.Project.FileName),'Save menu keeps its file target and pending input during an automatic preview');
    finally Args.Free; end;
    CaptureUi(L,'ui-wide-96');
    var Play := TButton(Find(M,'MovieTransportPlay')); var Stop := TButton(Find(M,'MovieTransportStop'));
    Toolbar := TObserver.Create(TWinControl(Find(L,'WorkspaceToolbar'))); Properties := TObserver.Create(Right);
    Play.Click; Pump(800); Check(M.Session.Playing and Stop.Enabled,'playback still starts through the visible transport');
    var Paints := Toolbar.TotalPaints; var PropertyPaints := Properties.TotalPaints; var Layouts := M.PropertyLayouts;
    var StaticUpdates := M.StaticUiUpdates; var Frames := M.PreviewControl.FrameCount; var Time := M.Session.Time;
    Pump(1800);
    Check(M.Session.Time>Time,'playback timer continues advancing while static UI is suppressed');
    Check(M.PreviewControl.FrameCount>Frames,'playback continues updating rendered preview frames');
    Check((M.PropertyLayouts=Layouts) and (M.StaticUiUpdates=StaticUpdates),'playback does not re-layout properties or refresh static diagnosis controls');
    Check((Toolbar.TotalPaints-Paints<=2) and (Properties.TotalPaints-PropertyPaints<=2),'page toolbar and every right property child do not repaint every frame');
    var Metric := TJSONObject.Create; AddN(Metric,'observationMs',1800); AddN(Metric,'toolbarPaints',Toolbar.TotalPaints-Paints); AddN(Metric,'propertyPaints',Properties.TotalPaints-PropertyPaints);
    AddN(Metric,'propertyLayouts',M.PropertyLayouts-Layouts); AddN(Metric,'staticUiUpdates',M.StaticUiUpdates-StaticUpdates); AddN(Metric,'previewFrames',M.PreviewControl.FrameCount-Frames); Metrics.AddElement(Metric);
    Check(Edit.Text=Text,'playback preserves the pending editor text'); Stop.Click; WaitIdle(M);
  finally Properties.Free; Toolbar.Free; L.Free; end;
end;
begin
  Root := GetEnvironmentVariable('RIGMMAKER_UIREV_TEST_ROOT'); Source := GetEnvironmentVariable('RIGMMAKER_UIREV_TEST_SOURCE'); ForceDirectories(Root);
  Checks := TJSONArray.Create; Metrics := TJSONArray.Create; var Errors := TErrors.Create;
  try
    Writeln('START: native UI regression'); Flush(Output);
    Application.Initialize; Application.OnException := Errors.Handle;
    try
      TStyleManager.TrySetStyle('Windows Modern Dark');
      HistoryTests; UiTests;
    except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); Flush(Output); ExitCode := 1; end; end;
    var O := TJSONObject.Create;
    try AddB(O,'success',ExitCode=0); AddN(O,'passed',Checks.Count); O.AddPair('checks',Checks); Checks := nil; O.AddPair('metrics',Metrics); Metrics := nil;
      AddB(O,'humanGuiVisualVerification',False); O.AddPair('captureMethod','VCL PaintTo client area; excludes native menu/nonclient border');
      TFile.WriteAllText(TPath.Combine(Root,'results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally Application.OnException := nil; Errors.Free; Checks.Free; Metrics.Free; end;
end.
