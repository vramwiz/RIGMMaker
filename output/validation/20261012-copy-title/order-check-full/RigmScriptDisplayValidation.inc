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
