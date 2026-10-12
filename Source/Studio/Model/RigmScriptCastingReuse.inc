// 原稿の一致範囲から既存セリフを復元する。行位置がずれても個別の分割・音声を保つ。
type
  TScriptSourcePart = record
    Offset: Integer;
    Text: string;
  end;
  TScriptSourceMatch = record
    Before,After,Count: Integer;
  end;
function ScriptSourceParts(const Text: string): TArray<TScriptSourcePart>;
begin
  var Parts := TList<TScriptSourcePart>.Create;
  try
    var Start := 0;
    while Start<Length(Text) do begin
      var Finish := Text.IndexOf(#13#10,Start); if Finish<0 then Finish := Length(Text);
      if Trim(Text.Substring(Start,Finish-Start))<>'' then while Start<Finish do begin
        var Count := Min(2000,Finish-Start); if not ScriptTextBoundary(Text,Start+Count) then Dec(Count);
        var Part: TScriptSourcePart; Part.Offset := Start; Part.Text := Text.Substring(Start,Count); Parts.Add(Part);
        Inc(Start,Count);
      end;
      Start := Finish+2;
    end;
    Result := Parts.ToArray;
  finally Parts.Free; end;
end;
procedure MatchScriptSourceEdges(Matches: TList<TScriptSourceMatch>; const X,Y: TScriptSourcePart);
begin
  var Prefix := 0;
  while (Prefix<Min(Length(X.Text),Length(Y.Text))) and (X.Text[Prefix+1]=Y.Text[Prefix+1]) do Inc(Prefix);
  while (Prefix>0) and (not ScriptTextBoundary(X.Text,Prefix) or not ScriptTextBoundary(Y.Text,Prefix)) do Dec(Prefix);
  if Prefix>0 then begin var M: TScriptSourceMatch; M.Before := X.Offset; M.After := Y.Offset; M.Count := Prefix; Matches.Add(M); end;
  var Suffix := 0;
  while (Suffix<Min(Length(X.Text),Length(Y.Text))-Prefix) and
    (X.Text[Length(X.Text)-Suffix]=Y.Text[Length(Y.Text)-Suffix]) do Inc(Suffix);
  while (Suffix>0) and (not ScriptTextBoundary(X.Text,Length(X.Text)-Suffix) or
    not ScriptTextBoundary(Y.Text,Length(Y.Text)-Suffix)) do Dec(Suffix);
  if Suffix>0 then begin var M: TScriptSourceMatch; M.Before := X.Offset+Length(X.Text)-Suffix;
    M.After := Y.Offset+Length(Y.Text)-Suffix; M.Count := Suffix; Matches.Add(M); end;
end;
function MatchScriptSource(const Before,After: string): TArray<TScriptSourceMatch>;
begin
  var A := ScriptSourceParts(Before); var B := ScriptSourceParts(After);
  if (Length(A)>2000) or (Length(B)>2000) then raise Exception.Create('セリフは既存モデルの2000件上限以内にしてください。');
  var Matches := TList<TScriptSourceMatch>.Create;
  try
    // セリフ上限内の行列（最大約8MB）。同じ文が繰り返されても順序を保って一対一に対応する。
    var Width := Length(B)+1; var Scores: TArray<Word>; SetLength(Scores,(Length(A)+1)*Width);
    for var I := High(A) downto 0 do for var J := High(B) downto 0 do
      if A[I].Text=B[J].Text then Scores[I*Width+J] := Scores[(I+1)*Width+J+1]+1
      else Scores[I*Width+J] := Max(Scores[(I+1)*Width+J],Scores[I*Width+J+1]);
    var I := 0; var J := 0; var OldStart := 0; var NewStart := 0;
    while (I<Length(A)) or (J<Length(B)) do begin
      if (I<Length(A)) and (J<Length(B)) and (A[I].Text=B[J].Text) then begin
        // 対応する変更行内の一致部分も残し、同じ行を人が分割していた場合に備える。
        if I-OldStart=J-NewStart then for var K := 0 to I-OldStart-1 do MatchScriptSourceEdges(Matches,A[OldStart+K],B[NewStart+K]);
        var M: TScriptSourceMatch; M.Before := A[I].Offset; M.After := B[J].Offset; M.Count := Length(A[I].Text); Matches.Add(M);
        Inc(I); Inc(J); OldStart := I; NewStart := J;
      end else if (I<Length(A)) and ((J=Length(B)) or (Scores[(I+1)*Width+J]>=Scores[I*Width+J+1])) then Inc(I)
      else Inc(J);
    end;
    if I-OldStart=J-NewStart then for var K := 0 to I-OldStart-1 do
      MatchScriptSourceEdges(Matches,A[OldStart+K],B[NewStart+K]);
    var Joined := TList<TScriptSourceMatch>.Create;
    try
      for var M in Matches do begin
        if Joined.Count>0 then begin
          var Last := Joined.Last; var Gap := M.Before-Last.Before-Last.Count;
          if (Gap>=0) and (M.After-Last.After-Last.Count=Gap) and
            (Before.Substring(Last.Before+Last.Count,Gap)=After.Substring(Last.After+Last.Count,Gap)) then begin
            Last.Count := M.Before+M.Count-Last.Before; Joined[Joined.Count-1] := Last; Continue;
          end;
        end;
        Joined.Add(M);
      end;
      Result := Joined.ToArray;
    finally Joined.Free; end;
  finally Matches.Free; end;
end;
procedure AddReconciledScriptSection(Project: TRigmMovieProject; Old: TJSONObject; const Section,Text: string;
  Cues: TObjectList<TRigmMovieCue>; Rows: TJSONArray; Scenes: TObjectList<TRigmMovieScene>; const FixedSceneId: string='');
  procedure KeepScene(const Id: string);
  begin
    for var Scene in Scenes do if Scene.Id=Id then Exit;
    var Existing := Project.Scene(Id);
    if Existing=nil then raise Exception.Create('既存セリフのシーンがありません。');
    var Q := Existing.Json; try Scenes.Add(TRigmMovieScene.FromJson(Q)); finally Q.Free; end;
  end;
  function ParagraphAt(Offset: Integer): Integer;
  begin if FixedSceneId<>'' then Exit(0); Result := Text.LastIndexOf(#13#10+#13#10,Max(0,Offset-1))+4; if Result<4 then Result := 0; end;
begin
  var Previous := TList<TJSONObject>.Create; var Reused := TList<TPoint>.Create;
  var ParagraphScenes := TDictionary<Integer,string>.Create;
  try
    var Before := '';
    if Old<>nil then begin
      for var V in JA(Old,'sections') do if JS(TJSONObject(V),'id')=Section then Before := JS(TJSONObject(V),'text');
      for var V in JA(Old,'rows') do if JS(TJSONObject(V),'section')=Section then Previous.Add(TJSONObject(V));
    end;
    var Matches := MatchScriptSource(Before,Text);
    for var I := 0 to Previous.Count-1 do begin
      var Row := Previous[I]; var C := Project.Cue(JS(Row,'cueId')); if C=nil then Continue;
      var Offset := JI(Row,'offset'); var Count := JI(Row,'length');
      if (Offset<0) or (Count<>Length(C.Text)) or (Offset>Length(Before)-Count) or
        (Before.Substring(Offset,Count)<>C.Text) then Continue;
      for var M in Matches do if (Offset>=M.Before) and (Offset+Count<=M.Before+M.Count) then begin
        var NewOffset := M.After+Offset-M.Before;
        if Text.Substring(NewOffset,Count)<>C.Text then Break;
        // 1行全体の前後に追記した場合は、その行を更新する。手動分割した部分境界は保持する。
        if ((Offset=0) or (Before[Offset]=#10)) and (NewOffset>0) and (Text[NewOffset]<>#10) then Break;
        if ((Offset+Count=Length(Before)) or (Before[Offset+Count+1]=#13)) and
          (NewOffset+Count<Length(Text)) and (Text[NewOffset+Count+1]<>#13) then Break;
        Reused.Add(Point(I,NewOffset)); var Paragraph := ParagraphAt(NewOffset);
        if not ParagraphScenes.ContainsKey(Paragraph) then ParagraphScenes.Add(Paragraph,C.Scene);
        Break;
      end;
    end;
    var OldCursor := 0; var NewCursor := 0;
    // 番兵により末尾を含む全変更範囲を同じ処理で追加する。
    Reused.Add(Point(Previous.Count,Length(Text)));
    for var At in Reused do begin
      var GapCues := TObjectList<TRigmMovieCue>.Create(True); var GapRows := TJSONArray.Create;
      try
        AddLineCues(Text,Section,'',NewCursor,At.Y,GapCues,GapRows);
        var PairRows := At.X-OldCursor=GapCues.Count;
        for var I := 0 to GapCues.Count-1 do begin
          var Fresh := GapCues[I]; var FreshRow := TJSONObject(GapRows[I]);
          var C: TRigmMovieCue; var Row: TJSONObject;
          if PairRows then begin
            var OldRow := Previous[OldCursor+I]; var Existing := Project.Cue(JS(OldRow,'cueId'));
            var Q := Existing.Json; try C := TRigmMovieCue.FromJson(Q); finally Q.Free; end;
            Row := OldRow.Clone as TJSONObject;
            if C.Text<>Fresh.Text then begin
              if C.Subtitle=C.Text then C.Subtitle := Fresh.Text;
              C.Text := Fresh.Text; C.VoiceReading := ''; C.VoiceQuery := ''; C.VoiceQueryKey := '';
              C.AudioKey := ''; C.VoiceHeardKey := ''; PsdJson.Put(Row,'confirmed',TJSONBool.Create(False));
            end;
            KeepScene(C.Scene);
          end else begin
            var Q := Fresh.Json; try C := TRigmMovieCue.FromJson(Q); finally Q.Free; end;
            Row := FreshRow.Clone as TJSONObject;
            var Paragraph := ParagraphAt(JI(FreshRow,'offset')); var SceneId := FixedSceneId;
            if (SceneId='') and (OldCursor>0) and (ParagraphAt(NewCursor)=Paragraph) then
              SceneId := Project.Cue(JS(Previous[OldCursor-1],'cueId')).Scene
            else if (SceneId='') and (At.X<Previous.Count) and (ParagraphAt(At.Y)=Paragraph) then
              SceneId := Project.Cue(JS(Previous[At.X],'cueId')).Scene;
            if (SceneId='') and not ParagraphScenes.TryGetValue(Paragraph,SceneId) then begin
              var Scene := TRigmMovieScene.Create; Scene.Title := Section+' '+(ParagraphScenes.Count+1).ToString;
              Scenes.Add(Scene); SceneId := Scene.Id; ParagraphScenes.Add(Paragraph,SceneId);
            end else KeepScene(SceneId);
            C.Scene := SceneId;
          end;
          Cues.Add(C); Rows.AddElement(Row); PsdJson.Put(Row,'cueId',C.Id);
          PsdJson.Put(Row,'offset',TJSONNumber.Create(JI(FreshRow,'offset'))); PsdJson.Put(Row,'length',TJSONNumber.Create(Length(C.Text)));
        end;
      finally GapRows.Free; GapCues.Free; end;
      if At.X<Previous.Count then begin
        var Row := Previous[At.X].Clone as TJSONObject; var Existing := Project.Cue(JS(Row,'cueId'));
        var Q := Existing.Json; try Cues.Add(TRigmMovieCue.FromJson(Q)); finally Q.Free; end;
        Rows.AddElement(Row); PsdJson.Put(Row,'offset',TJSONNumber.Create(At.Y)); KeepScene(Existing.Scene);
        NewCursor := At.Y+Length(Existing.Text); OldCursor := At.X+1;
      end;
    end;
  finally ParagraphScenes.Free; Reused.Free; Previous.Free; end;
end;
