program MovieEditingCheck;
{$APPTYPE CONSOLE}
// 専用作品でタイムラインの表示・一覧シーク・未適用入力の保護を確認する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types, System.Math,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Graphics, Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardMainForm, RigmMovieWorkspaceFrame, RigmMovieEditorFrame, RigmMovieForm,
  RigmMovieTimeline, RigmMovieSession, RigmMovieModel, RigmPageNavigation, RigmJson;
{$R *.res}
var Root,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
function Fixture: TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create;
  for var I := 0 to 29 do begin
    var C := TRigmMovieCue.Create; Result.Cues.Add(C); C.SpeakerId := Result.Speakers[0].Id;
    C.Text := '専用セリフ '+I.ToString; C.Subtitle := C.Text; C.AudioSeconds := 3.125; C.Pause := 0.3;
  end;
end;
procedure Capture(Host: TWinControl; const Name: string);
begin
  var B := TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(Host.ClientWidth,Host.ClientHeight); Host.PaintTo(B.Canvas,0,0); P.Assign(B); P.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally P.Free; B.Free; end;
end;
procedure CheckEditor(Host,Editor: TWinControl; Session: TRigmMovieSession; Ppi: Integer; const Context: string);
begin
  var Before := Session.Project.Json;
  try
    var Timeline := Editor.FindComponent('MovieWaveTimeline') as TRigmMovieTimeline;
    var Feedback := Editor.FindComponent('MovieExportFeedback') as TPanel;
    (Editor.FindComponent('MovieExportFeedbackText') as TLabel).Caption := '専用作品：動画の出力状況を表示する領域';
    (Editor.FindComponent('MovieExportFeedbackAction') as TButton).Caption := '取消';
    var Scroll := Editor.FindComponent('MovieEditingScroll') as TScrollBox;
    for var H in [900,720] do begin
      Host.SetBounds(0,0,MulDiv(1440,Ppi,96),MulDiv(H,Ppi,96));
      for var Showing in [False,True] do begin
        Feedback.Visible := Showing; Host.Update;
        Check(Timeline.ClientHeight>=Timeline.MinimumHeightPixels,Context+' four timeline tracks at height '+H.ToString+' feedback '+Showing.ToString);
        var Bottom := Timeline.ClientToScreen(Point(0,Timeline.ClientHeight));
        var Limit := Scroll.ClientToScreen(Point(0,Scroll.ClientHeight));
        Check(Bottom.Y<=Limit.Y,Context+' timeline remains inside the visible editing viewport '+H.ToString+' '+Showing.ToString);
      end;
    end;
    Host.SetBounds(0,0,MulDiv(1440,Ppi,96),MulDiv(900,Ppi,96)); Feedback.Visible := True;
    var Splitter := Editor.FindComponent('MovieTimelineSplitter') as TSplitter;
    Splitter.OnBeforeResize(Splitter);
    try
      var Size := MulDiv(100,Ppi,96); var Accept := True; Splitter.OnCanResize(Splitter,Size,Accept);
      Check(Accept and (Size>=Timeline.MinimumHeightPixels+MulDiv(64,Ppi,96)),Context+' splitter cannot hide timeline tracks');
      Size := (Editor.FindComponent('MovieEditingArea') as TPanel).ClientHeight-Splitter.Height-MulDiv(165,Ppi,96); Accept := True;
      Splitter.OnCanResize(Splitter,Size,Accept);
      Check(Accept,Context+' splitter can expand timeline while preserving the preview minimum');
    finally Splitter.OnAfterResize(Splitter); end;
    Timeline.SetSpan(10); Timeline.SetTime(0);
    var List := Editor.FindComponent('MovieCueList') as TListView;
    var Cue := Session.Project.Cues.Last; List.Items[List.Items.Count-1].Selected := True;
    var Start := Session.Project.CueStart(Cue);
    Check((Session.Time>=Start) and (Session.Time<Start+1/Session.Project.Fps),Context+' selecting a late cue seeks to its first video frame');
    Check(SameValue(Session.Time,Timeline.Time,0.000001) and (Timeline.SelectedCueId=Cue.Id),Context+' timeline playhead and selected cue match the list');
    Check((Timeline.SecondsAt(Timeline.HeaderWidthPixels)>0) and
      (Timeline.SecondsAt(Timeline.HeaderWidthPixels)<=Session.Time),Context+' zoomed timeline pans to the selected cue');
    var Memo := Editor.FindComponent('MovieCueText') as TMemo;
    Check(Memo.Text=Cue.Text,Context+' property text follows the selected cue');
    Timeline.SetTime(Session.Time+1); Timeline.OnSeek(Timeline); List.OnClick(List);
    Check((Session.Time>=Start) and (Session.Time<Start+1/Session.Project.Fps),Context+' clicking the already selected cue returns to its first frame');
    Timeline.SetTime(Session.Project.CueStart(Session.Project.Cues[10])+0.4);
    var ClickTime := Timeline.Time; Timeline.SelectCue(Session.Project.Cues[10].Id);
    Timeline.OnSelectCue(Timeline); Timeline.OnSeek(Timeline);
    Check(Abs(Session.Time-ClickTime)<=1/Session.Project.Fps,Context+' timeline click keeps its time');
    var Selected := Timeline.SelectedCueId; var Time := Session.Time; Memo.Text := '適用前の入力を保持';
    List.Items[5].Selected := True;
    Check((Memo.Text='適用前の入力を保持') and (Timeline.SelectedCueId=Selected) and SameValue(Session.Time,Time),Context+' unapplied input blocks selection and seek together');
    if Ppi=144 then Capture(Host,Context+'-timeline');
    var After := Session.Project.Json;
    try Check(Before.ToJSON=After.ToJSON,Context+' layout and selection preserve the source project'); finally After.Free; end;
  finally Before.Free; end;
end;
procedure Embedded(Ppi: Integer);
begin
  var Main := TRigmWizardMainForm.Create(nil);
  try
    Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Main.ScaleForPPI(Ppi); Main.Scaled := False;
    Main.NavigateTo(apMovieEdit);
    var Editor := TRigmMovieWorkspaceFrame(Main.PageInstance(apMovieEdit)).CurrentEditor;
    Editor.Session.SetProject(Fixture); Editor.SetActive(True); Editor.SetActive(False);
    CheckEditor(Main,Editor,Editor.Session,Ppi,'embedded-'+Ppi.ToString);
  finally Main.Free; end;
end;
procedure Standalone(Ppi: Integer);
begin
  var Session := TRigmMovieSession.Create;
  try
    Session.SetProject(Fixture); var Form := TRigmMovieForm.CreateForSession(nil,Session);
    try
      for var I := 0 to Form.ComponentCount-1 do if Form.Components[I] is TTimer then TTimer(Form.Components[I]).Enabled := False;
      Form.Show; ShowWindow(Form.Handle,SW_SHOWNOACTIVATE); Form.ScaleForPPI(Ppi); Form.Scaled := False;
      CheckEditor(Form,Form,Session,Ppi,'standalone-'+Ppi.ToString);
    finally Form.Free; end;
  finally Session.Free; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Root := ParamStr(1); Checks := TJSONArray.Create;
  try
    if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh owned root required');
    for var Ppi in [96,144,192] do Embedded(Ppi);
    for var Ppi in [96,144,192] do Standalone(Ppi);
  except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  var Report := TJSONObject.Create;
  try Report.AddPair('checks',Checks); Report.AddPair('error',Error); TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end.
