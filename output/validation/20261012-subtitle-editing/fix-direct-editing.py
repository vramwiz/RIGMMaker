from pathlib import Path

root = Path(r'D:\DelphiProg\RIGMMaker')
def edit(name, before, after):
    p = root / name
    data = p.read_bytes()
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    assert text.count(before) == 1, (name, before[:100], text.count(before))
    text = text.replace(before, after)
    p.write_bytes((b'\xef\xbb\xbf' if data.startswith(b'\xef\xbb\xbf') else b'') + text.replace('\n', '\r\n').encode('utf-8'))

page = 'Source/Shell/Pages/RigmScriptSubtitleFrame.pas'
edit(page, "'Enter：表示字幕・改行・メモを編集'", "'表示字幕の入力欄へ移動（Enter / 一覧をダブルクリック）'")
edit(page, "FList.OnKeyDown := HandleKey; FList.Name := 'ScriptSubtitleRows';", "FList.OnKeyDown := HandleKey; FList.OnDblClick := Detail; FList.Name := 'ScriptSubtitleRows';")
edit(page,
     'begin if not FSync and FEditing then FWorkspace.BeginScriptTextEdit; end;',
     "begin\n  if FSync or FEditor.ReadOnly or (FLoaded='') then Exit;\n  FEditing := True; FWorkspace.BeginScriptTextEdit;\nend;")
edit(page, 'if FSync or not FEditing then Exit; BeginInput(Sender);', 'if FSync or FEditor.ReadOnly then Exit; BeginInput(Sender);')
edit(page,
     'FEditing := False; FEditor.ReadOnly := True; FNote.ReadOnly := True; FWorkspace.EndScriptTextEdit;',
     'FEditing := False; FWorkspace.EndScriptTextEdit;')
edit(page,
     'FEditing := False; FEditor.ReadOnly := True; FNote.ReadOnly := True; FWorkspace.CompleteSubtitles; FList.SetFocus;',
     'FEditing := False; FWorkspace.CompleteSubtitles; FList.SetFocus;')
edit(page,
     'var SelectionChanged := FLoaded<>Id;\n  FSync := True;',
     "var SelectionChanged := FLoaded<>Id;\n  var Problem := ScriptSubtitleBlockReason(P,False);\n  FSync := True;")
edit(page,
     'if FEditor.Text<>C.Subtitle then FEditor.Text := C.Subtitle;\n      if FNote.Text<>C.SubtitleNote then FNote.Text := C.SubtitleNote;\n      FEditor.ReadOnly := not FEditing; FNote.ReadOnly := not FEditing; FLoaded := Id;\n    end;',
     "if NormalizeScriptText(FEditor.Text)<>C.Subtitle then FEditor.Text := C.Subtitle;\n      if NormalizeScriptText(FNote.Text)<>C.SubtitleNote then FNote.Text := C.SubtitleNote;\n      FLoaded := Id;\n    end;\n    // 選択後・入力完了後も直接編集する。前工程が古い場合だけ入力を止める。\n    FEditor.ReadOnly := Problem<>''; FNote.ReadOnly := Problem<>'';")
edit(page,
     "var Guide := '↑↓：セリフ選択 / ←→：最初の折返し移動 / Enter：表示文・改行・メモの編集。'+#13#10+'Ctrl+Enter / Esc：入力完了。原稿と音声文は保持します。';\n    var Problem := ScriptSubtitleBlockReason(P,False);",
     "var Guide := '表示字幕・改行・メモは右側の欄で直接編集できます。Enter：字幕欄へ移動。'+#13#10+\n      '一覧の↑↓：セリフ選択 / ←→：最初の折返し移動 / Ctrl+Enter・Esc：入力完了。';")

edit('Source/Psd/Validation/RigmScriptSubtitleValidation.inc',
     "not W.ScriptTextEditing and Editor.ReadOnly and (JS(W.ScriptDraft.ScriptWizard,'subtitlesStatus')='complete'),'ready completes details and releases shared input lock'",
     "not W.ScriptTextEditing and not Editor.ReadOnly and not Note.ReadOnly and (JS(W.ScriptDraft.ScriptWizard,'subtitlesStatus')='complete'),'ready completes details while keeping subtitle fields directly editable'")
