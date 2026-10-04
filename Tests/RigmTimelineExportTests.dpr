program RigmTimelineExportTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Types, System.Math, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Dialogs, Vcl.Graphics, Vcl.Imaging.pngimage,
  Vcl.Themes, Vcl.Styles, RIGMMakerMainForm, RigmMovieForm, RigmMovieTimeline,
  RigmMovieSession, RigmMovieModel, RigmJson;
type
  TDialogDriver = class(TThread)
    Target: string;
    CancelDialog,SawDialog,Filled: Boolean;
    DialogWindow: HWND;
    procedure Execute; override;
  end;
var Root,Source,Failure: string; Checks: TJSONArray;
procedure Check(OK: Boolean; const Text: string);
begin if not OK then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS: '+Text); Flush(Output); end;
function DialogEnum(W: HWND; Param: LPARAM): BOOL; stdcall;
begin
  Result := True; var Pid: DWORD; GetWindowThreadProcessId(W,@Pid);
  var Name: array[0..127] of Char; GetClassName(W,Name,Length(Name));
  if (Pid=GetCurrentProcessId) and IsWindowVisible(W) and (string(Name)='#32770') then begin
    TDialogDriver(Param).DialogWindow := W; Result := False;
  end;
end;
procedure TDialogDriver.Execute;
begin
  var Deadline := GetTickCount64+10000;
  repeat
    DialogWindow := 0; EnumWindows(@DialogEnum,LPARAM(Self));
    if DialogWindow<>0 then begin
      SawDialog := True;
      if CancelDialog then PostMessage(DialogWindow,WM_COMMAND,IDCANCEL,0)
      else begin
        var Edit := GetDlgItem(DialogWindow,1152);
        if Edit=0 then Edit := GetDlgItem(DialogWindow,1148);
        if Edit<>0 then begin
          SendMessage(Edit,WM_SETTEXT,0,LPARAM(PChar(Target))); Filled := True;
          PostMessage(DialogWindow,WM_COMMAND,IDOK,0);
        end else PostMessage(DialogWindow,WM_COMMAND,IDCANCEL,0);
      end;
      Exit;
    end;
    Sleep(20);
  until GetTickCount64>Deadline;
end;
procedure Pump(Ms: Cardinal);
begin var UntilTick := GetTickCount64+Ms; repeat Application.ProcessMessages; Sleep(5); until GetTickCount64>=UntilTick; end;
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
procedure Capture(C: TWinControl; const Name: string);
begin
  var B := Vcl.Graphics.TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(C.Width,C.Height); C.PaintTo(B.Canvas,0,0); P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally P.Free; B.Free; end;
end;
procedure SelectPath(Menu: TMenuItem; const Target: string; CancelDialog: Boolean=False);
begin
  var Driver := TDialogDriver.Create(True); Driver.Target := Target; Driver.CancelDialog := CancelDialog;
  try Driver.Start; Menu.Click; Driver.WaitFor;
    Check(Driver.SawDialog,'real GUI menu opens a native save-file dialog');
    Check(CancelDialog or Driver.Filled,'owned native save dialog accepts the selected file path');
  finally Driver.Free; end;
end;
procedure Test;
begin
  var Before := THashSHA2.GetHashStringFromFile(Source); var L := TMainForm.Create(nil);
  try
    L.Show; Pump(100); var A := TJSONObject.Create;
    try A.AddPair('path',Source); var Reply := L.ExecuteWorkspace('open-work',A); Reply.Free; finally A.Free; end;
    var M := Studio(L); Check(M<>nil,'owned product opens the actual four-scene image work');
    var Timeline := TRigmMovieTimeline(Find(M,'MovieWaveTimeline'));
    var Menu := TMenuItem(L.FindComponent('MovieMenuAction13'));
    Check((Menu<>nil) and (Menu.Parent.Caption='動画を書き出す') and Menu.Caption.StartsWith('MP4'),'File menu has an explicit MP4 export entry');
    Check(Menu.ShortCut=TextToShortCut('Ctrl+Shift+E'),'MP4 export has its own keyboard shortcut');
    Check(Find(M,'MovieTransportExport').Visible,'preview transport exposes MP4 export');
    A := TJSONObject.Create; var Data := M.Session.Execute('timeline',A);
    try
      Check(JA(Data,'cues').Count=4,'actual work contains four readable timeline objects');
      for var V in JA(Data,'cues') do begin var C := TJSONObject(V);
        Check((JS(C,'sceneTitle')<>'') and (JS(C,'imageName')<>''),'scene clip exposes actual scene title and image filename');
        Check((JS(C,'characterName')<>'') and (JS(C,'motionLabel')<>''),'actor clip exposes character name and pose/motion');
        Check((JS(C,'speakerName')<>'') and (JS(C,'text')<>'') and (JS(C,'subtitle')<>''),'audio/subtitle clips expose speaker and authored content');
      end;
    finally Data.Free; A.Free; end;
    for var DPI in [96,120,144,192] do for var Width in [640,1200] do begin
      L.ScaleForPPI(DPI); L.Width := MulDiv(Width,DPI,96); L.Height := MulDiv(700,DPI,96); Pump(160);
      Capture(Timeline,'timeline-'+DPI.ToString+'-'+Width.ToString);
      Check(Timeline.RenderedTextHeight>=MulDiv(16,DPI,96),'timeline text has readable physical glyph height '+DPI.ToString+'/'+Width.ToString);
      Check(Timeline.RulerHeightPixels>=Timeline.RenderedTextHeight+MulDiv(12,DPI,96),'ruler row keeps readable time text and padding '+DPI.ToString+'/'+Width.ToString);
      Check(Timeline.Height>=Timeline.RulerHeightPixels+MulDiv(34*4,DPI,96),'all four labeled rows fit '+DPI.ToString+'/'+Width.ToString);
      Check(Timeline.RenderedLabelCount>=8,'actual object content labels are drawn '+DPI.ToString+'/'+Width.ToString);
      var Export := Find(M,'MovieTransportExport');
      Check(Export.Left+Export.Width<=Export.Parent.ClientWidth,'MP4 entry stays inside narrow preview transport '+DPI.ToString+'/'+Width.ToString);
      var Builds := Timeline.StaticBuildCount; var Thumbnails := Timeline.ThumbnailCount;
      for var I := 1 to 30 do begin Timeline.SetTime(I/30); Timeline.Repaint; end;
      Check((Timeline.StaticBuildCount=Builds) and (Timeline.ThumbnailCount=Thumbnails),'playhead redraw retains label/thumbnail cache '+DPI.ToString+'/'+Width.ToString);
    end;
    L.ScaleForPPI(96); L.Width := 1500; L.Height := 950; Pump(200);
    Capture(L,'product-readable-timeline');
    var OldOutput := M.Session.Project.OutputTarget; var Revision := M.Session.Project.Revision;
    SelectPath(Menu,'',True); Check((M.Session.Project.OutputTarget=OldOutput) and (M.Session.Project.Revision=Revision),'canceling file selection keeps the owned work unchanged');
    var CancelTarget := TPath.Combine(Root,'Exports\cancel-probe.mp4'); ForceDirectories(ExtractFilePath(CancelTarget));
    SelectPath(Menu,CancelTarget); Pump(200);
    Check(M.Session.Busy and Find(M,'MovieExportFeedback').Visible,'native menu starts export and displays progress');
    Capture(L,'product-export-progress');
    var Action := TButton(Find(M,'MovieExportFeedbackAction')); Check(Action.Tag=9,'visible export action can cancel the active job'); Action.Click;
    var Deadline := GetTickCount64+20000; repeat Pump(40); until not M.Session.Busy or (GetTickCount64>Deadline);
    A := TJSONObject.Create; var Job := M.Session.Execute('job-status',A);
    try Check(JS(Job,'state')='cancelled','GUI cancel reaches a collected cancelled export'); finally Job.Free; A.Free; end;
    Check(not FileExists(CancelTarget),'cancelled output does not publish a broken MP4');
    var Target := TPath.Combine(Root,'Exports\gui-menu-real-speech.mp4');
    M.Session.Project.WorkflowStage := 'setup';
    SelectPath(Menu,Target); Check(M.Session.Busy,'native MP4 menu starts from setup without requiring stage changes');
    A := TJSONObject.Create; Job := M.Session.Execute('job-status',A);
    var ExportId: string;
    try ExportId := JS(Job,'jobId'); finally Job.Free; A.Free; end;
    Deadline := GetTickCount64+1200000; repeat Pump(40); until not M.Session.Busy or (GetTickCount64>Deadline); Pump(300);
    A := TJSONObject.Create; A.AddPair('jobId',ExportId); Job := M.Session.Execute('job-status',A);
    try
      Check(JS(Job,'state')='succeeded','GUI menu writes the entire real image/voice MP4');
      Check(JB(Job,'collected') and JB(Job,'encoderExited'),'GUI observes collected output and FFmpeg exit');
      Check(FileExists(Target),'selected GUI MP4 destination exists');
    finally Job.Free; A.Free; end;
    Check((Action.Tag=40) and (Action.Caption='保存先を開く'),'GUI completion provides an output-folder action');
    Check(TLabel(Find(M,'MovieExportFeedbackText')).Hint.Contains(Target),'completion exposes the exact selected output path');
    Capture(L,'product-export-complete');
    Check(THashSHA2.GetHashStringFromFile(Source)=Before,'all GUI tests leave the user source work byte-identical');
    var O := TJSONObject.Create;
    try AddB(O,'success',True); AddN(O,'passed',Checks.Count); O.AddPair('source',Source); O.AddPair('sourceSha256',Before);
      O.AddPair('export',Target); O.AddPair('exportSha256',THashSHA2.GetHashStringFromFile(Target)); O.AddPair('checks',Checks.Clone as TJSONArray);
      AddB(O,'realNativeSaveDialog',True); AddB(O,'humanDesktopVerification',False); TFile.WriteAllText(TPath.Combine(Root,'results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
  finally L.Free; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows'); UseLatestCommonDialogs := False;
  Root := ParamStr(2); Source := ParamStr(1); ForceDirectories(Root); Checks := TJSONArray.Create;
  try try Test; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Checks.Free; end;
end.
