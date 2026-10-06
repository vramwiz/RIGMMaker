unit RigmScriptSubtitleModel;

// 表示字幕とメモのみを既存セリフ正本へ反映する。原稿・音声・配役は変更しない。
interface
uses System.JSON, RigmMovieModel;
procedure PrepareScriptSubtitles(Project: TRigmMovieProject); // 配役確認後、既存表示文を保持して準備する。
procedure SelectSubtitle(Project: TRigmMovieProject; const CueId: string); // 選択を保存する。
procedure MoveSubtitle(Project: TRigmMovieProject; Delta: Integer); // 発話順で選択する。
procedure EditSubtitle(Project: TRigmMovieProject; const CueId, Text, Note: string); // 表示文とメモを原子的に更新する。
procedure SetSubtitleBreak(Project: TRigmMovieProject; const CueId: string; Offset: Integer); // 最初の改行だけを0始まりUTF16位置へ移す。
procedure MoveSubtitleBreak(Project: TRigmMovieProject; const CueId: string; Delta, DefaultOffset: Integer); // 左右で1文字動かす。
function ScriptSubtitleSummary(Project: TRigmMovieProject): TJSONObject; // 呼出側所有、長文なし。
procedure ValidateScriptSubtitles(Project: TRigmMovieProject); // 保存・読込の形式と選択を検査する。
implementation
uses System.SysUtils, System.Math, RigmJson, PsdJson, RigmScriptTextModel, RigmScriptCastingModel;
procedure PrepareScriptSubtitles(Project: TRigmMovieProject);
begin
  ValidateScriptCasting(Project); var Summary := ScriptCastingSummary(Project);
  try if (JS(Summary,'state')='stale') or (JI(Summary,'pending')<>0) or (JI(Summary,'unassigned')<>0) then
    raise Exception.Create('未確認の配役を確定してから字幕へ進んでください。'); finally Summary.Free; end;
  if not (Project.ScriptWizard.GetValue('subtitles') is TJSONObject) then begin
    var O := TJSONObject.Create; O.AddPair('format','RIGMMaker.ScriptSubtitles'); AddN(O,'schemaVersion',1);
    O.AddPair('selectedCue',Project.Cues[0].Id); Project.ScriptWizard.AddPair('subtitles',O);
  end;
  var O := JO(Project.ScriptWizard,'subtitles'); if Project.Cue(JS(O,'selectedCue'))=nil then PsdJson.Put(O,'selectedCue',Project.Cues[0].Id);
  if Project.ScriptWizard.GetValue('subtitlesStatus')=nil then PsdJson.Put(Project.ScriptWizard,'subtitlesStatus','in-progress');
end;
procedure SelectSubtitle(Project: TRigmMovieProject; const CueId: string);
begin
  if Project.Cue(CueId)=nil then raise Exception.Create('字幕のセリフを選んでください。');
  PsdJson.Put(JO(Project.ScriptWizard,'subtitles'),'selectedCue',CueId);
end;
procedure MoveSubtitle(Project: TRigmMovieProject; Delta: Integer);
begin
  var Cue := Project.Cue(JS(JO(Project.ScriptWizard,'subtitles'),'selectedCue'));
  SelectSubtitle(Project,Project.Cues[EnsureRange(Project.Cues.IndexOf(Cue)+Delta,0,Project.Cues.Count-1)].Id);
end;
procedure ValidateText(const Text: string; Limit: Integer);
begin
  if Length(Text)>Limit then raise Exception.CreateFmt('表示字幕は3000文字、メモは2048文字以内にしてください（上限%d）。',[Limit]);
  for var C in Text do if (Ord(C)<32) and not CharInSet(C,[#9,#10,#13]) then raise Exception.Create('無効な制御文字が含まれています。');
  var I := 1;
  while I<=Length(Text) do begin
    if (Ord(Text[I])>=$D800) and (Ord(Text[I])<=$DBFF) then begin
      if (I=Length(Text)) or (Ord(Text[I+1])<$DC00) or (Ord(Text[I+1])>$DFFF) then raise Exception.Create('文字の途中で切れています。'); Inc(I);
    end else if (Ord(Text[I])>=$DC00) and (Ord(Text[I])<=$DFFF) then raise Exception.Create('文字の途中で切れています。'); Inc(I);
  end;
end;
procedure EditSubtitle(Project: TRigmMovieProject; const CueId, Text, Note: string);
begin
  var Cast := JO(Project.ScriptWizard,'casting');
  if (JS(Cast,'state')='stale') or (JS(Cast,'fingerprint')<>CastingFingerprint(Project)) then
    raise Exception.Create('前工程が変わりました。校正・配役を確認し、Nextで字幕へ進んでください。');
  var Cue := Project.Cue(CueId); if Cue=nil then raise Exception.Create('字幕のセリフがありません。');
  var Value := NormalizeScriptText(Text); var Memo := NormalizeScriptText(Note); ValidateText(Value,3000); ValidateText(Memo,2048);
  Cue.Subtitle := Value; Cue.SubtitleNote := Memo; PsdJson.Put(Project.ScriptWizard,'subtitlesStatus','in-progress');
end;
function WithoutFirstBreak(const Text: string; out Position: Integer): string;
begin Position := Text.IndexOf(#13#10); Result := Text; if Position>=0 then Result := Text.Remove(Position,2); end;
procedure SetSubtitleBreak(Project: TRigmMovieProject; const CueId: string; Offset: Integer);
begin
  var Cue := Project.Cue(CueId); if Cue=nil then raise Exception.Create('字幕のセリフがありません。');
  var Old: Integer; var Base := WithoutFirstBreak(Cue.Subtitle,Old); var Next := Base.IndexOf(#13#10);
  if (Offset<1) or (Offset>Length(Base)) or not ScriptTextBoundary(Base,Offset) or
    ((Next>=0) and (Offset>=Next)) then raise Exception.Create('最初の行内の文字境界を指定してください。');
  if Offset<Length(Base) then Base := Base.Insert(Offset,#13#10);
  EditSubtitle(Project,CueId,Base,Cue.SubtitleNote);
end;
procedure MoveSubtitleBreak(Project: TRigmMovieProject; const CueId: string; Delta, DefaultOffset: Integer);
begin
  if Delta=0 then Exit;
  var Cue := Project.Cue(CueId); if Cue=nil then Exit; var Position: Integer; var Base := WithoutFirstBreak(Cue.Subtitle,Position);
  if Length(Base)<2 then Exit; if Position<0 then Position := EnsureRange(DefaultOffset,1,Length(Base));
  var Target := EnsureRange(Position+Sign(Delta),1,Length(Base));
  while not ScriptTextBoundary(Base,Target) do Inc(Target,Sign(Delta));
  SetSubtitleBreak(Project,CueId,Target);
end;
procedure ValidateScriptSubtitles(Project: TRigmMovieProject);
begin
  var O := JO(Project.ScriptWizard,'subtitles');
  if (JS(O,'format')<>'RIGMMaker.ScriptSubtitles') or (JI(O,'schemaVersion')<>1) or
    (Project.Cue(JS(O,'selectedCue'))=nil) then raise Exception.Create('字幕工程の保存形式が不正です。');
  for var C in Project.Cues do begin ValidateText(C.Subtitle,3000); ValidateText(C.SubtitleNote,2048); end;
end;
function ScriptSubtitleSummary(Project: TRigmMovieProject): TJSONObject;
begin
  Result := TJSONObject.Create; if Project.ScriptWizard.GetValue('subtitles')=nil then Exit;
  Result.AddPair('format','RIGMMaker.ScriptSubtitles'); Result.AddPair('selectedCue',JS(JO(Project.ScriptWizard,'subtitles'),'selectedCue'));
  AddN(Result,'count',Project.Cues.Count); Result.AddPair('status',JS(Project.ScriptWizard,'subtitlesStatus'));
end;
end.
