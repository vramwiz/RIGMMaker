// ネイティブ入力を使い、文字更新以外の再描画・再配置と入力状態の破棄を監視する。
type
  TRigmDisplaySpy = class
  private
    FControl: TControl;
    FOriginal: TWndMethod;
    procedure WindowMessage(var Message: TMessage);
  public
    RedrawChanges,TextChanges,TextResets,VisibilityChanges,Positions,Paints: Integer;
    constructor Create(Control: TControl);
    destructor Destroy; override;
    procedure Reset;
  end;
constructor TRigmDisplaySpy.Create(Control: TControl);
begin inherited Create; FControl := Control; FOriginal := Control.WindowProc; Control.WindowProc := WindowMessage; end;
destructor TRigmDisplaySpy.Destroy;
begin FControl.WindowProc := FOriginal; inherited; end;
procedure TRigmDisplaySpy.Reset;
begin RedrawChanges := 0; TextChanges := 0; TextResets := 0; VisibilityChanges := 0; Positions := 0; Paints := 0; end;
procedure TRigmDisplaySpy.WindowMessage(var Message: TMessage);
begin
  case Message.Msg of
    WM_SETREDRAW: Inc(RedrawChanges);
    CM_TEXTCHANGED: Inc(TextChanges);
    WM_SETTEXT: Inc(TextResets);
    CM_VISIBLECHANGED: Inc(VisibilityChanges);
    WM_WINDOWPOSCHANGED: Inc(Positions);
    WM_PAINT: Inc(Paints);
  end;
  FOriginal(Message);
end;

// 第12段階の字幕欄は選択直後から直接入力できる。ユーザー作品には触れない。
procedure CheckSubtitleDirectEditing;
begin
  var Page := StageFrame(TRigmScriptSubtitleFrame) as TRigmScriptSubtitleFrame;
  var Editor := Page.FindComponent('ScriptSubtitleText') as TMemo;
  var Note := Page.FindComponent('ScriptSubtitleNote') as TMemo;
  var Voice := Page.FindComponent('ScriptSubtitleVoice') as TMemo;
  var Tools := Page.FindComponent('ScriptSubtitleToolbar') as TToolBar;
  var Ready := Tools.FindComponent('ScriptSubtitleReady') as TToolButton;
  var Cue := W.ScriptDraft.Cues[0]; var Other := W.ScriptDraft.Cues[1];
  W.SelectSubtitle(Cue.Id);
  Check(not Editor.ReadOnly and not Note.ReadOnly,'subtitle and note accept direct input on opening stage twelve');
  Check(not Voice.ReadOnly and (NormalizeScriptText(Voice.Text)=Cue.VoiceReading),'subtitle stage exposes an independent editable reading');
  var Original := Cue.Subtitle; var OriginalNote := Cue.SubtitleNote;
  var OtherText := Other.Subtitle; var OtherNote := Other.SubtitleNote;
  var Raw := ScriptFingerprint(W.ScriptDraft); var Audio := W.ScriptDraft.AudioFingerprint(Cue); var Scene := Cue.Scene;
  var Spy := TRigmDisplaySpy.Create(Editor);
  try
    Editor.SetFocus; Editor.SelStart := Length(Editor.Text);
    SendMessage(Editor.Handle,WM_CHAR,Ord('a'),0);
    var Addition := '日本語の字幕'+#13#10+'直接貼り付け';
    SendMessage(Editor.Handle,EM_REPLACESEL,1,LPARAM(PChar(Addition)));
    Application.ProcessMessages;
    Check((Cue.Subtitle<>Original) and (Cue.Subtitle=NormalizeScriptText(Editor.Text)),
      'native typing and multiline paste edit the selected subtitle without Enter or an edit button');
    Check((Spy.TextResets=0) and Editor.Focused and Editor.CanUndo,
      'subtitle typing preserves native focus caret and undo without replacing memo text');
    Editor.SelStart := 2; Editor.SelLength := 3; Spy.Reset;
    for var I := 1 to 10 do W.OnScriptChanged(W);
    Check((Editor.SelStart=2) and (Editor.SelLength=3) and (Spy.TextResets=0),
      'subtitle state notifications preserve selection and do not rewrite the input');
    Editor.Undo;
    Check(Cue.Subtitle=NormalizeScriptText(Editor.Text),'subtitle undo updates the same cue');
    Note.SetFocus; Note.SelStart := Length(Note.Text); SendMessage(Note.Handle,WM_CHAR,Ord('n'),0);
    Check(Cue.SubtitleNote=NormalizeScriptText(Note.Text),'note accepts native input without a separate editing mode');
    Check((ScriptFingerprint(W.ScriptDraft)=Raw) and (W.ScriptDraft.AudioFingerprint(Cue)=Audio) and (Cue.Scene=Scene),
      'direct subtitle edits preserve manuscript audio fingerprint and scene');
    var OriginalReading := Cue.VoiceReading; var Display := Cue.Subtitle;
    var ReadingSpy := TRigmDisplaySpy.Create(Voice);
    try
      Voice.SetFocus; Voice.SelectAll;
      var Reading := 'あゆむがかげろうこうこうへむかいます。';
      SendMessage(Voice.Handle,EM_REPLACESEL,1,LPARAM(PChar(Reading)));
      Check((Cue.VoiceReading=Reading) and (Cue.Subtitle=Display) and (ScriptFingerprint(W.ScriptDraft)=Raw),
        'native reading input changes synthesis text independently of subtitle and manuscript');
      Voice.SelStart := 2; Voice.SelLength := 3; ReadingSpy.Reset;
      for var I := 1 to 10 do W.OnScriptChanged(W);
      Check((Voice.SelStart=2) and (Voice.SelLength=3) and (ReadingSpy.TextResets=0),
        'reading state notifications retain local text selection and caret');
      Voice.Text := OriginalReading;
      Check(W.ScriptDraft.AudioFingerprint(Cue)=Audio,'clearing reading restores original synthesis text');
    finally ReadingSpy.Free; end;
    W.SelectSubtitle(Other.Id);
    Check(not Editor.ReadOnly and not Note.ReadOnly and (Editor.Text=OtherText),
      'selecting another subtitle immediately opens writable subtitle and note fields');
    Editor.SetFocus; Editor.SelStart := Length(Editor.Text); SendMessage(Editor.Handle,WM_CHAR,Ord('b'),0);
    Check(Other.Subtitle=NormalizeScriptText(Editor.Text),'typing after row selection updates the new cue');
    Ready.Click;
    Check(not Editor.ReadOnly and not Note.ReadOnly and (JS(W.ScriptDraft.ScriptWizard,'subtitlesStatus')='complete'),
      'completing subtitle input retains directly editable fields');
    Editor.SetFocus; Editor.SelStart := Length(Editor.Text); SendMessage(Editor.Handle,WM_CHAR,Ord('c'),0);
    Check(JS(W.ScriptDraft.ScriptWizard,'subtitlesStatus')='in-progress','editing completed subtitles reopens confirmation automatically');
    Check(Page.RequestFinish and not Editor.ReadOnly,'saving input does not relock the subtitle field');
    Note.Text := StringOfChar('x',2049);
    Check(not Page.RequestFinish and (Length(Note.Text)=2049) and (Page.InputError<>''),
      'invalid note prevents leaving and preserves the local input');
    Note.Text := OtherNote;
    Check(Page.RequestFinish and (Page.InputError=''),'correcting invalid note permits saving again');
    var Cast := JO(W.ScriptDraft.ScriptWizard,'casting'); var State := JS(Cast,'state');
    PsdJson.Put(Cast,'state','stale'); Page.RefreshState;
    Check(Editor.ReadOnly and Note.ReadOnly and Voice.ReadOnly,'obsolete casting keeps subtitle and reading edits disabled with its prerequisite reason');
    PsdJson.Put(Cast,'state',State); Page.RefreshState;
    Check(not Editor.ReadOnly and not Note.ReadOnly and not Voice.ReadOnly,'restoring current casting restores subtitle and reading input');
    Editor.Text := OtherText; Note.Text := OtherNote;
    W.SelectSubtitle(Cue.Id); Editor.Text := Original; Note.Text := OriginalNote;
    Check(Page.RequestFinish,'subtitle fixture restores its original display text');
    Go('casting'); Go('subtitles');
    Check(not Editor.ReadOnly and not Note.ReadOnly,'returning from another stage keeps subtitles directly editable');
    Capture('subtitle-direct-editing');
  finally Spy.Free; end;
end;

procedure CheckScriptDisplay;
begin
  var Page := StageFrame(TRigmScriptTextFrame);
  var Memo := Page.FindComponent('ScriptText1') as TMemo;
  var Tabs := Page.FindComponent('ScriptTextSections') as TTabControl;
  var List := Creator.FindComponent('ScriptStages') as TListBox;
  var Body := Creator.FindComponent('ScriptPageBody') as TPanel;
  Check((Page.FindComponent('ScriptTextToolbar')=nil) and (Page.FindComponent('ScriptTextReady')=nil) and
    (Tabs.Tabs.Count=3),'text page has named section tabs and no obsolete toolbar confirmation');
  Tabs.TabIndex := 1; Tabs.OnChange(Tabs); Application.ProcessMessages;
  var Text := '';
  for var I := 1 to 90 do Text := Text+'本文入力のスクロール確認 '+I.ToString+#13#10;
  W.SetScriptText('body',Text); Memo.SetFocus; Memo.SelStart := Length(Memo.Text);
  SendMessage(Memo.Handle,EM_SCROLLCARET,0,0); Application.ProcessMessages;
  var GuideSpy := TRigmDisplaySpy.Create(Page.FindComponent('ScriptTextGuide') as TControl);
  var ListSpy := TRigmDisplaySpy.Create(List); var BodySpy := TRigmDisplaySpy.Create(Body);
  var MemoSpy := TRigmDisplaySpy.Create(Memo); var PageSpy := TRigmDisplaySpy.Create(TControl(Page));
  try
    var Addition := '日本語の入力。'+#13#10+'貼り付けた文章。';
    SendMessage(Memo.Handle,EM_REPLACESEL,1,LPARAM(PChar(Addition)));
    for var I := 1 to 20 do SendMessage(Memo.Handle,WM_CHAR,Ord('a'),0);
    Application.ProcessMessages;
    Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=NormalizeScriptText(Memo.Text),'native typing and multiline paste immediately update the script model');
    Check((GuideSpy.TextChanges=0) and (ListSpy.RedrawChanges=0) and (ListSpy.Paints=0) and
      (BodySpy.VisibilityChanges=0) and (PageSpy.Positions=0),
      'typing does not rewrite the guide, repaint the stage list, hide the body or reposition the page');
    Check((MemoSpy.TextResets=0) and Memo.Focused and Memo.CanUndo,'typing preserves focus and the native undo buffer without replacing memo text');
    Memo.SelStart := 18; Memo.SelLength := 9;
    SendMessage(Memo.Handle,EM_LINESCROLL,0,24);
    var FirstLine := SendMessage(Memo.Handle,EM_GETFIRSTVISIBLELINE,0,0);
    var Top := List.TopIndex; var Bounds := Memo.BoundsRect;
    for var I := 1 to 10 do W.OnScriptChanged(W);
    Check((Memo.SelStart=18) and (Memo.SelLength=9) and Memo.Focused and
      (SendMessage(Memo.Handle,EM_GETFIRSTVISIBLELINE,0,0)=FirstLine) and (Memo.BoundsRect=Bounds) and (List.TopIndex=Top),
      'repeated state notifications preserve selection, scrolling, focus and editor bounds');
    Check((GuideSpy.TextChanges=0) and (ListSpy.RedrawChanges=0) and (MemoSpy.TextResets=0),
      'unchanged state notifications leave the guide, list and memo untouched');
    Memo.Undo;
    Check(JS(ScriptSection(W.ScriptDraft,'body'),'text')=NormalizeScriptText(Memo.Text),'native undo remains synchronized with the script model');
    W.SetScriptText('opening','外部更新した前段。');
    Tabs.TabIndex := 0; Tabs.OnChange(Tabs);
    Check((W.CurrentScriptStage='text') and ((Page.FindComponent('ScriptText0') as TMemo).Text='外部更新した前段。'),
      'section tabs switch the memo while remaining in stage five and accepting external text');
    BodySpy.Reset; Go('placement'); Application.ProcessMessages;
    Check(Body.Visible and (BodySpy.VisibilityChanges=2) and not TControl(Page).Visible,
      'backward stage change hides the parent once and restores it with inactive text page hidden');
    BodySpy.Reset; Go('text'); Application.ProcessMessages;
    Check(Body.Visible and (BodySpy.VisibilityChanges=2) and TControl(Page).Visible and
      (TControl(Page).Parent=Creator.FindComponent('ScriptStageScroll')),
      'forward stage change restores the initialized page inside the stage host');
    Check(List.DoubleBuffered,'stage list uses buffered drawing');
    Capture('text-stable');
  finally PageSpy.Free; MemoSpy.Free; BodySpy.Free; ListSpy.Free; GuideSpy.Free; end;
end;
