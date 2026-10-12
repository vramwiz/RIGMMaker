program MovieDpiCheck;
{$APPTYPE GUI}
// 所有する空の作品だけで、動画編集画面の遅延生成・DPI変更・入力保持を検証する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardMainForm, RigmWizardWorkspace, RigmMovieWorkspaceFrame,
  RigmMovieEditorFrame, RigmMovieForm, RigmMovieSession, RigmMovieModel,
  RigmPageNavigation;
{$R *.res}
type TControlAccess = class(TControl);
var Root,Error: string; Checks,Metrics: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
  Checks.Add(Text); Writeln('PASS ',Text);
end;
procedure Capture(Host: TWinControl; const Name: string);
begin
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try
    Bitmap.SetSize(Host.ClientWidth,Host.ClientHeight); Host.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
procedure Fonts(Editor: TWinControl; Ppi: Integer; const Context: string);
begin
  for var Name in ['MovieCueText','MovieCueSubtitle','MovieCueSpeaker','MovieTransportPlay',
    'MovieScriptExample','MovieTitle','MovieSceneDescription'] do begin
    var Control := TControlAccess(Editor.FindComponent(Name));
    Check(Control<>nil,Context+' '+Name+' exists');
    var Metric := TJSONObject.Create; Metrics.AddElement(Metric);
    Metric.AddPair('context',Context); Metric.AddPair('name',Name);
    Metric.AddPair('hostPpi',TJSONNumber.Create(Ppi));
    Metric.AddPair('controlPpi',TJSONNumber.Create(Control.CurrentPPI));
    Metric.AddPair('fontPpi',TJSONNumber.Create(Control.Font.PixelsPerInch));
    Metric.AddPair('height',TJSONNumber.Create(Control.Font.Height));
    Writeln(Context,' ',Name,' control=',Control.CurrentPPI,' font=',Control.Font.PixelsPerInch,' height=',Control.Font.Height);
    Check(Abs(Abs(Control.Font.Height)-MulDiv(13,Ppi,96))<=1,Context+' '+Name+' font scales once');
    Check((Control.CurrentPPI=Ppi) and (Control.Font.PixelsPerInch=Ppi),Context+' '+Name+' shares host DPI');
  end;
end;
procedure Properties(Editor: TRigmMovieEditorFrame; Ppi: Integer; const Context: string);
begin
  var Text := TMemo(Editor.FindComponent('MovieCueText'));
  var Subtitle := TMemo(Editor.FindComponent('MovieCueSubtitle'));
  var Play := TButton(Editor.FindComponent('MovieTransportPlay'));
  Check(Text.Width>=MulDiv(200,Ppi,96),Context+' dialogue keeps usable width');
  Check(Subtitle.Top>=Text.Top+Text.Height,Context+' dialogue and subtitle do not overlap');
  Check(Play.Height>=MulDiv(24,Ppi,96),Context+' transport button has scaled height');
end;
procedure Embedded(Ppi: Integer);
begin
  var Main := TRigmWizardMainForm.Create(nil);
  try
    Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update;
    // 単一物理モニター上で尺度を再現する。変更自体はVCL標準で実行し、
    // 直後はScaled=FalseでCurrentPPIのGetDpiForWindow参照を抑える。
    Main.ScaleForPPI(Ppi); Main.Scaled := False;
    Main.SetBounds(0,0,MulDiv(1360,Ppi,96),MulDiv(900,Ppi,96));
    Check(Main.CurrentPPI=Ppi,'host DPI '+Ppi.ToString);
    Main.NavigateTo(apMovieEdit);
    var Page := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit));
    var Editor := Page.CurrentEditor; Editor.SetActive(False);
    Application.ProcessMessages;
    var Context := 'lazy-'+Ppi.ToString;
    Capture(Main,Context);
    Fonts(Editor,Ppi,Context); Properties(Editor,Ppi,Context);
    var Session := Editor.Session; var Before := Session.Project.Json;
    try
      var Draft := TMemo(Editor.FindComponent('MovieCueText')); Draft.Text := 'DPI変更で保持する未適用入力';
      Editor.SelectPropertyPage('scene'); Editor.SelectPropertyPage('dialogue');
      Check(Draft.Text='DPI変更で保持する未適用入力',Context+' page change keeps draft');
      for var NextPpi in [192,144,96,192,96] do begin
        Main.Scaled := True; Main.ScaleForPPI(NextPpi); Main.Scaled := False; Application.ProcessMessages;
        Fonts(Editor,NextPpi,Context+'-to-'+NextPpi.ToString);
        Properties(Editor,NextPpi,Context+'-to-'+NextPpi.ToString);
        Check(Draft.Text='DPI変更で保持する未適用入力',Context+' DPI change keeps draft');
      end;
      var After := Session.Project.Json;
      try Check(Before.ToJSON=After.ToJSON,Context+' layout keeps project unchanged'); finally After.Free; end;
      Check(Page.CurrentEditor=Editor,Context+' keeps editor instance');
    finally Before.Free; end;
  finally Main.Free; end;
end;
procedure PhysicalMonitor;
begin
  var Main := TRigmWizardMainForm.Create(nil);
  try
    Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.Update;
    Main.NavigateTo(apMovieEdit);
    var Editor := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)).CurrentEditor;
    Editor.SetActive(False);
    Fonts(Editor,Main.CurrentPPI,'physical-monitor'); Properties(Editor,Main.CurrentPPI,'physical-monitor');
    Check(not TPanel(Main.FindComponent('WizardHeader')).ShowCaption,'header hides internal name');
    TMemo(Editor.FindComponent('MovieCueText')).Text := 'DPI確認用のセリフです。文字サイズと折り返しを確認します。';
    TMemo(Editor.FindComponent('MovieCueSubtitle')).Text := '字幕の文字サイズも親画面と同じ倍率にします。';
    Capture(Main,'physical-monitor');
  finally Main.Free; end;
end;
procedure Standalone(Ppi: Integer);
begin
  var Session := TRigmMovieSession.Create;
  try
    var Form := TRigmMovieForm.CreateForSession(nil,Session);
    try
      for var I := 0 to Form.ComponentCount-1 do
        if Form.Components[I] is TTimer then TTimer(Form.Components[I]).Enabled := False;
      Form.Show; ShowWindow(Form.Handle,SW_SHOWNOACTIVATE); Form.Update;
      Form.ScaleForPPI(Ppi); Form.Scaled := False;
      Fonts(Form,Ppi,'standalone-'+Ppi.ToString);
      Capture(Form,'standalone-'+Ppi.ToString);
    finally Form.Free; end;
  finally Session.Free; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark');
  Root := ParamStr(1); Checks := TJSONArray.Create; Metrics := TJSONArray.Create;
  try
    if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh output root required');
    PhysicalMonitor;
    for var Ppi in [96,144,192] do Embedded(Ppi);
    for var Ppi in [96,144,192] do Standalone(Ppi);
  except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  var Report := TJSONObject.Create;
  try
    Report.AddPair('checks',Checks); Report.AddPair('metrics',Metrics); Report.AddPair('error',Error);
    TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end.
