from pathlib import Path

root = Path(r'D:\DelphiProg\RIGMMaker')
def edit(name, before, after):
    p = root / name
    data = p.read_bytes()
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    assert text.count(before) == 1, (name, before[:100], text.count(before))
    text = text.replace(before, after)
    p.write_bytes((b'\xef\xbb\xbf' if data.startswith(b'\xef\xbb\xbf') else b'') + text.replace('\n', '\r\n').encode('utf-8'))

edit('Source/Psd/Validation/ScriptOrderCheck.dpr',
     'RigmScriptTextFrame, RigmScriptSummaryFrame,',
     'RigmScriptTextFrame, RigmScriptSubtitleFrame, RigmScriptSummaryFrame,')
edit('Source/Psd/Validation/ScriptOrderCheck.dpr',
     "  Go('voice');\n  CheckAccentEditing;",
     "  CheckSubtitleDirectEditing;\n  Go('voice');\n  CheckAccentEditing;")
procedure = r'''
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
  Check(Voice.ReadOnly,'subtitle editing keeps the voice text read only');
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
    Check(Editor.ReadOnly and Note.ReadOnly,'obsolete casting keeps subtitle edits disabled with its prerequisite reason');
    PsdJson.Put(Cast,'state',State); Page.RefreshState;
    Check(not Editor.ReadOnly and not Note.ReadOnly,'restoring current casting restores direct input');
    Editor.Text := OtherText; Note.Text := OtherNote;
    W.SelectSubtitle(Cue.Id); Editor.Text := Original; Note.Text := OriginalNote;
    Check(Page.RequestFinish,'subtitle fixture restores its original display text');
    Go('casting'); Go('subtitles');
    Check(not Editor.ReadOnly and not Note.ReadOnly,'returning from another stage keeps subtitles directly editable');
    Capture('subtitle-direct-editing');
  finally Spy.Free; end;
end;
'''
edit('Source/Psd/Validation/RigmScriptDisplayValidation.inc',
     'procedure CheckScriptDisplay;\n', procedure + '\nprocedure CheckScriptDisplay;\n')
