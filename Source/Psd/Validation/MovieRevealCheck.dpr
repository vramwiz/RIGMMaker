program MovieRevealCheck;
{$APPTYPE CONSOLE}
// 専用プロセスのウィンドウメッセージを観測し、配置・一覧更新中の部品が画面に露出しないことを確認する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Themes, Vcl.Styles,
  RigmWizardMainForm, RigmWizardWorkspace, RigmMovieWorkspaceFrame, RigmMovieEditorFrame,
  RigmMovieModel, RigmMovieSession, RigmMovieTimeline, RigmPageNavigation;
{$R *.res}
var Root,Error: string; Checks,Observations: TJSONArray; Hook: HHOOK;
  Observing: Boolean; Mutations,VisibleMutations,IncompleteShows: Integer;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); Checks.Add(Text); Writeln('PASS ',Text); end;
function Observe(Code: Integer; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
begin
  if (Code>=0) and Observing then begin
    var Event := PCWPStruct(LParam);
    if (Event.message=WM_SIZE) or (Event.message=WM_SHOWWINDOW) or (Event.message=WM_SETTEXT) or
      (Event.message=CB_RESETCONTENT) or (Event.message=LVM_DELETEALLITEMS) or (Event.message=LVM_INSERTITEMW) then begin
      var Control := FindControl(Event.hwnd);
      while (Control<>nil) and not (Control is TRigmMovieEditorFrame) do Control := Control.Parent;
      if (Control<>nil) and Control.HandleAllocated then begin
        var Showing := IsWindowVisible(Control.Handle);
        if (Event.message=WM_SHOWWINDOW) then begin
          if Showing and (Control.FindComponent('MovieOperations')=nil) then Inc(IncompleteShows);
        end else begin
          Inc(Mutations); if Showing then Inc(VisibleMutations);
        end;
      end;
    end;
  end;
  Result := CallNextHookEx(Hook,Code,WParam,LParam);
end;
procedure BeginObservation;
begin Mutations := 0; VisibleMutations := 0; IncompleteShows := 0; Observing := True; end;
procedure EndObservation(const Context: string);
begin
  Observing := False;
  var RecordValue := TJSONObject.Create; RecordValue.AddPair('context',Context);
  RecordValue.AddPair('nativeUpdates',TJSONNumber.Create(Mutations));
  RecordValue.AddPair('exposedUpdates',TJSONNumber.Create(VisibleMutations));
  RecordValue.AddPair('unfinishedShows',TJSONNumber.Create(IncompleteShows)); Observations.Add(RecordValue);
  Check(Mutations>0,Context+' observes actual native layout or data updates');
  Check(IncompleteShows=0,Context+' never exposes the unfinished editor');
  Check(VisibleMutations=0,Context+' hides intermediate native layout and data updates');
end;
function Fixture(const Name: string; Count: Integer): TRigmMovieProject;
begin
  Result := TRigmMovieProject.Create; Result.Title := Name; Result.EngineUrl := 'http://127.0.0.1:1';
  for var I := 1 to Count do begin
    var Cue := TRigmMovieCue.Create; Result.Cues.Add(Cue); Cue.SpeakerId := Result.Speakers[0].Id;
    Cue.Text := '専用の表示確認 '+I.ToString; Cue.Subtitle := Cue.Text; Cue.AudioSeconds := 2; Cue.Pause := 0.3;
  end;
  SaveMovie(Result,TPath.Combine(Root,Name+'.rigmovie'));
end;
procedure Run;
begin
  var Main := TRigmWizardMainForm.Create(nil);
  try
    // 現在の表示倍率で論理サイズを指定する。倍率そのものは変更しない。
    Main.SetBounds(0,0,MulDiv(1440,Main.CurrentPPI,96),MulDiv(900,Main.CurrentPPI,96));
    Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
    var Host := Main.PageInstance(apHome).Parent;
    var Session1 := Main.Workspace.ActiveSession; Session1.SetProject(Fixture('first',24));
    var Before := Session1.Project.Json;
    try
      BeginObservation;
      try Main.NavigateTo(apMovieEdit); finally Observing := False; end;
      EndObservation('initial opening');
      var Page := Main.PageInstance(apMovieEdit) as TRigmMovieWorkspaceFrame;
      var Editor1 := Page.CurrentEditor;
      Check(IsWindowVisible(Editor1.Handle) and IsWindowVisible(Host.Handle),'complete editor is visible after activation');
      Check(not Host.IsDrawingLocked and not Page.IsDrawingLocked,'opening releases drawing guards');
      Check((Editor1.FindComponent('MovieCueList') as TListView).Items.Count=24,'first visible editor contains all dialogue');
      Check((Editor1.FindComponent('MovieCueText') as TMemo).Text=Session1.Project.Cues[0].Text,'first visible editor has selected dialogue');
      var Bounds := Editor1.BoundsRect; Main.Update;
      Check(EqualRect(Bounds,Editor1.BoundsRect) and (Editor1.Width=Page.ClientWidth) and
        (Editor1.Height=Page.ClientHeight),'first visible editor already has its final parent bounds');
      var Timeline := Editor1.FindComponent('MovieWaveTimeline') as TRigmMovieTimeline;
      var Scroll := Editor1.FindComponent('MovieEditingScroll') as TScrollBox;
      var SizeValue := TJSONObject.Create; SizeValue.AddPair('context','initial viewport');
      SizeValue.AddPair('ppi',TJSONNumber.Create(Main.CurrentPPI));
      SizeValue.AddPair('viewportHeight',TJSONNumber.Create(Scroll.ClientHeight));
      SizeValue.AddPair('editingHeight',TJSONNumber.Create(TControl(Editor1.FindComponent('MovieEditingArea')).Height));
      Observations.Add(SizeValue);
      Check(Timeline.ClientHeight>=Timeline.MinimumHeightPixels,'first visible editor contains all four timeline tracks');
      Check(Timeline.ClientToScreen(Point(0,Timeline.ClientHeight)).Y<=Scroll.ClientToScreen(Point(0,Scroll.ClientHeight)).Y,
        'first visible timeline is inside the editing viewport');
      BeginObservation;
      try Page.SetActive(True); finally Observing := False; end;
      EndObservation('direct refresh');
      Main.NavigateTo(apHome);
      Check(not Page.Visible and not IsWindowVisible(Editor1.Handle),'movie remains hidden on another page');
      BeginObservation;
      try Main.NavigateTo(apMovieEdit); finally Observing := False; end;
      EndObservation('reopening');
      Check(Page.CurrentEditor=Editor1,'reopening reuses the original editor');
      Main.Workspace.NewWork; var Session2 := Main.Workspace.ActiveSession;
      Session2.SetProject(Fixture('second',7));
      BeginObservation;
      try Main.NavigateTo(apMovieEdit); finally Observing := False; end;
      EndObservation('new session');
      var Editor2 := Page.CurrentEditor;
      Check((Editor2<>Editor1) and IsWindowVisible(Editor2.Handle) and not Editor1.Visible,'session switch reveals only the selected editor');
      Check((Editor2.FindComponent('MovieCueList') as TListView).Items.Count=7,'switched editor has the correct dialogue');
      BeginObservation;
      try Main.Workspace.OpenWork(Session1.Project.FileName); finally Observing := False; end;
      EndObservation('existing session');
      Check((Page.CurrentEditor=Editor1) and not Editor2.Visible,'returning to an existing session restores its editor');
      var Memo := Editor1.FindComponent('MovieCueText') as TMemo; Memo.Text := '未適用の入力を保持';
      Main.NavigateTo(apHome); Main.NavigateTo(apMovieEdit);
      Check(Memo.Text='未適用の入力を保持','reopening preserves unapplied dialogue');
      var After := Session1.Project.Json;
      try Check(Before.ToJSON=After.ToJSON,'showing and switching preserve the source project'); finally After.Free; end;
      // 下書きのない別ビューに不正な専用cueを一時挿入し、同期例外でも描画が復帰することを確認。
      Main.Workspace.OpenWork(Session2.Project.FileName); Session2.Project.Cues.Add(nil);
      var Failed := False;
      try
        BeginObservation;
        try Main.NavigateTo(apMovieEdit); except on E: EAccessViolation do Failed := True; end;
      finally Observing := False; Session2.Project.Cues.Remove(nil); end;
      Check(Failed,'owned malformed cue exercises failed activation');
      Check(not Host.IsDrawingLocked and not Page.IsDrawingLocked,'failed activation releases both drawing guards');
      Check(IsWindowVisible(Host.Handle) and IsWindowVisible(Page.Handle),'failed activation restores the parent display');
      BeginObservation;
      try Main.NavigateTo(apMovieEdit); finally Observing := False; end;
      EndObservation('recovery after failure');
      Check((Editor2.FindComponent('MovieCueList') as TListView).Items.Count=7,'editor remains usable after failed activation');
      Host.LockDrawing;
      try
        BeginObservation;
        try Page.SetActive(True); finally Observing := False; end;
        EndObservation('nested refresh');
        Check(Host.IsDrawingLocked and not Page.IsDrawingLocked and not IsWindowVisible(Editor2.Handle),
          'inner refresh preserves the caller drawing guard');
      finally Host.UnlockDrawing(True); end;
      Check(IsWindowVisible(Editor2.Handle),'caller can reveal the final editor after nested refresh');
      Main.NavigateTo(apHome); Page.SetActive(True);
      Check(not Page.Visible and not IsWindowVisible(Editor2.Handle),'refresh does not reveal a logically hidden movie page');
    finally Before.Free; end;
  finally Main.Free; end;
end;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark'); Root := ParamStr(1);
  Checks := TJSONArray.Create; Observations := TJSONArray.Create;
  try
    if (Root='') or FileExists(TPath.Combine(Root,'result.json')) then raise Exception.Create('Fresh owned root required');
    Hook := SetWindowsHookEx(WH_CALLWNDPROC,@Observe,0,GetCurrentThreadId);
    if Hook=0 then RaiseLastOSError;
    try Run; finally Observing := False; UnhookWindowsHookEx(Hook); end;
  except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
  var Report := TJSONObject.Create;
  try Report.AddPair('checks',Checks); Report.AddPair('observations',Observations); Report.AddPair('error',Error);
    TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end.
