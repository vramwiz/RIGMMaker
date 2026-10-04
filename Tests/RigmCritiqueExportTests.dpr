program RigmCritiqueExportTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, System.Hash, System.Types, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Menus, Vcl.Dialogs, Vcl.Graphics, Vcl.Imaging.pngimage,
  Vcl.Themes, Vcl.Styles, RIGMMakerMainForm, RigmMovieForm, RigmMovieSession, RigmMovieModel, RigmJson;
type
  TSaveDriver = class(TThread)
    Target: string; SawDialog,Filled: Boolean;
    procedure Execute; override;
  end;
var Source,Root: string; Checks: TJSONArray; DialogWindow: HWND;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS '+Name); Flush(Output); end;
procedure Pump(Ms: Cardinal);
begin var Deadline := GetTickCount64+Ms; repeat Application.ProcessMessages; Sleep(5); until GetTickCount64>=Deadline; end;
function Find(P: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to P.ControlCount-1 do begin
    var C := P.Controls[I]; if C.Name=Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end;
  end;
end;
function Studio(P: TWinControl): TRigmMovieForm;
begin
  Result := nil;
  for var I := 0 to P.ControlCount-1 do begin
    var C := P.Controls[I]; if (C is TRigmMovieForm) and C.Visible then Exit(TRigmMovieForm(C));
    if C is TWinControl then begin Result := Studio(TWinControl(C)); if Result<>nil then Exit; end;
  end;
end;
procedure Capture(C: TWinControl; const Name: string);
begin
  var B := Vcl.Graphics.TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(C.Width,C.Height); C.PaintTo(B.Canvas,0,0); P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally P.Free; B.Free; end;
end;
function EnumDialog(W: HWND; Param: LPARAM): BOOL; stdcall;
begin
  Result := True; var Pid: DWORD; GetWindowThreadProcessId(W,@Pid);
  var Name: array[0..127] of Char; GetClassName(W,Name,Length(Name));
  if (Pid=GetCurrentProcessId) and IsWindowVisible(W) and (string(Name)='#32770') then begin DialogWindow := W; Result := False; end;
end;
procedure TSaveDriver.Execute;
begin
  var Deadline := GetTickCount64+10000;
  repeat
    DialogWindow := 0; EnumWindows(@EnumDialog,0);
    if DialogWindow<>0 then begin
      SawDialog := True; var Edit := GetDlgItem(DialogWindow,1152);
      if Edit=0 then Edit := GetDlgItem(DialogWindow,1148);
      if Edit<>0 then begin SendMessage(Edit,WM_SETTEXT,0,LPARAM(PChar(Target))); Filled := True;
        PostMessage(DialogWindow,WM_COMMAND,IDOK,0); end
      else PostMessage(DialogWindow,WM_COMMAND,IDCANCEL,0);
      Exit;
    end;
    Sleep(20);
  until GetTickCount64>Deadline;
end;
procedure WaitExport(M: TRigmMovieForm);
begin
  var Deadline := GetTickCount64+1200000;
  repeat Pump(40); until not M.Session.Busy or (GetTickCount64>Deadline);
  Check(not M.Session.Busy,'owned export reaches a terminal state'); Pump(300);
end;
procedure Test;
begin
  var Before := THashSHA2.GetHashStringFromFile(Source);
  var Fixture := LoadMovie(Source); var FixturePath := TPath.Combine(Root,'saved-real-speech-proxy.rigmovie');
  try
    while Fixture.Cues.Count>1 do Fixture.Cues.Delete(Fixture.Cues.Count-1);
    while Fixture.Scenes.Count>1 do Fixture.Scenes.Delete(Fixture.Scenes.Count-1);
    Fixture.Width := 640; Fixture.Height := 360; Fixture.Fps := 30; Fixture.EncodeProfile := 'fast';
    SaveMovie(Fixture,FixturePath);
  finally Fixture.Free; end;
  var L := TMainForm.Create(nil);
  try
    L.Show; ShowWindow(L.Handle,SW_SHOWNOACTIVATE);
    L.ScaleForPPI(96); L.Width := 1480; L.Height := 950; Pump(100);
    var A := TJSONObject.Create;
    try A.AddPair('path',FixturePath); var R := L.ExecuteWorkspace('open-work',A); R.Free; finally A.Free; end;
    var M := Studio(L); Check(M<>nil,'actual saved work opens in the product movie GUI'); Pump(300);
    var Target := TPath.Combine(Root,'cancelled.mp4');
    A := TJSONObject.Create; A.AddPair('path',Target);
    try var R := M.Session.Execute('export',A); R.Free; finally A.Free; end;
    Pump(300);
    var Panel := TPanel(Find(M,'MovieExportFeedback')); var Progress := TProgressBar(Find(M,'MovieExportProgress'));
    var Action := TButton(Find(M,'MovieExportFeedbackAction')); var LabelControl := TLabel(Find(M,'MovieExportFeedbackText'));
    Capture(L,'first-export-observation');
    A := TJSONObject.Create; var Observation := M.Session.Execute('job-status',A); A.Free;
    try
      Writeln('OBSERVATION '+Observation.ToJSON);
      Writeln('WINDOW panelVisible=',Panel.Visible,' panelNativeVisible=',IsWindowVisible(Panel.Handle),
        ' movieVisible=',M.Visible,' movieNativeVisible=',IsWindowVisible(M.Handle),' rootNativeVisible=',IsWindowVisible(L.Handle));
      Writeln('UI error=',TLabel(Find(M,'MovieStatus')).Caption,' export=',LabelControl.Caption); Flush(Output);
    finally Observation.Free; end;
    Check(Panel.Visible and IsWindowVisible(Panel.Handle),'pipe-started export displays a real visible GUI feedback panel');
    Check(Progress.Visible and IsWindowVisible(Progress.Handle),'MP4 export exposes a native progress bar');
    Check((Panel.Top>=0) and (Panel.Top+Panel.Height<=M.ClientHeight),'progress feedback stays inside the movie form');
    Check((Action.Tag=9) and Action.Enabled,'cancel is available only while the export is active');
    Capture(L,'export-cancel-progress'); Action.Click; WaitExport(M);
    A := TJSONObject.Create; var Job := M.Session.Execute('job-status',A); A.Free;
    try Check(JS(Job,'state')='cancelled','GUI cancel stops the same pipe-started export'); finally Job.Free; end;
    Check(not FileExists(Target) and (M.ExportNotificationRequests=0),'cancel publishes neither a broken MP4 nor a completion notification');
    Check(Action.Tag=13,'cancelled export offers selecting a new destination');
    var Encoder := M.Session.Project.FfmpegExe;
    M.Session.Project.FfmpegExe := TPath.Combine(Root,'missing-ffmpeg.exe');
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'failed.mp4'));
    try var R := M.Session.Execute('export',A); R.Free; finally A.Free; end;
    WaitExport(M); M.Session.Project.FfmpegExe := Encoder;
    A := TJSONObject.Create; Job := M.Session.Execute('job-status',A); A.Free;
    try Check(JS(Job,'state')='failed','missing configured encoder reaches a failed export'); finally Job.Free; end;
    Check((Action.Tag=13) and (M.ExportNotificationRequests=0),'failed export offers retry and sends no completion notification');
    Target := TPath.Combine(Root,'real-speech-GUI.mp4');
    var Driver := TSaveDriver.Create(True); Driver.Target := Target;
    try Driver.Start; TMenuItem(L.FindComponent('MovieMenuAction13')).Click; Driver.WaitFor;
      Check(Driver.SawDialog and Driver.Filled,'real MP4 File menu accepts a new path through the native save dialog');
    finally Driver.Free; end;
    A := TJSONObject.Create; Job := M.Session.Execute('job-status',A); A.Free;
    var ExportId: string;
    try ExportId := JS(Job,'jobId'); finally Job.Free; end;
    Pump(300); Check(M.Session.Busy,'native save dialog starts the actual MP4 export');
    var SawFrames := False; var SawEncode := False; var SawEncoder := False; var MaximumProgress := 0;
    var Deadline := GetTickCount64+1200000;
    repeat
      Pump(200);
      if Pos('フレーム',LabelControl.Caption)>0 then begin
        if not SawFrames then Capture(L,'export-render-progress'); SawFrames := True;
      end;
      A := TJSONObject.Create; Job := M.Session.Execute('job-status',A); A.Free;
      try
        if JI(Job,'encoderProcessId')>0 then SawEncoder := True;
        if JS(Job,'phase')='encode' then begin
          if not SawEncode then Capture(L,'export-encode-progress'); SawEncode := True;
        end;
      finally Job.Free; end;
      if Progress.Position>MaximumProgress then MaximumProgress := Progress.Position;
    until not M.Session.Busy or (GetTickCount64>Deadline);
    WaitExport(M);
    A := TJSONObject.Create; A.AddPair('jobId',ExportId); Job := M.Session.Execute('job-status',A); A.Free;
    try
      Check((JS(Job,'state')='succeeded') and JB(Job,'collected') and JB(Job,'encoderExited'),'real speech MP4 succeeds after collecting the job and FFmpeg exit');
      Check(FileExists(Target),'selected real MP4 is present');
      Check(SawFrames and (MaximumProgress>0),'GUI displays actual rendered frame counts and a moving progress bar');
      Check(SawEncoder,'GUI tracks the active encoder while frames stream');
    finally Job.Free; end;
    Check((Action.Tag=40) and LabelControl.Hint.Contains(Target),'completion identifies the selected output and provides a folder action');
    Check((Progress.Position=1000) and (M.ExportNotificationRequests=1),'one successful export reaches 100 percent and requests one Windows success notification');
    Pump(1000); Check(M.ExportNotificationRequests=1,'repeated UI polling does not send duplicate notifications');
    Capture(L,'export-complete');
    Check(THashSHA2.GetHashStringFromFile(Source)=Before,'the original work remains byte-identical');
    var Report := TJSONObject.Create;
    try
      AddB(Report,'success',True); AddN(Report,'passed',Checks.Count);
      Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('source',Source); Report.AddPair('sourceSha256',Before);
      Report.AddPair('output',Target); Report.AddPair('outputSha256',THashSHA2.GetHashStringFromFile(Target));
      AddN(Report,'windowsNotificationRequests',M.ExportNotificationRequests); AddN(Report,'windowsBalloonShowEvents',M.ExportNotificationsShown);
      AddB(Report,'humanDesktopVerification',False); AddB(Report,'encoderObserved',SawEncoder); AddB(Report,'finalEncodePhaseObserved',SawEncode);
      AddN(Report,'fixtureSeconds',M.Session.Project.Duration); AddN(Report,'fixtureWidth',M.Session.Project.Width); AddN(Report,'fixtureHeight',M.Session.Project.Height);
      TFile.WriteAllText(TPath.Combine(Root,'results.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
  finally L.Free; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows'); UseLatestCommonDialogs := False;
  Source := ParamStr(1); Root := ParamStr(2); ForceDirectories(Root); Checks := TJSONArray.Create;
  try try Test; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Checks.Free; end;
end.
