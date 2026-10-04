unit RigmMovieProduction;
interface
uses System.JSON, RigmMovieModel;
function MovieProductionSignature(Args: TJSONObject): string;
function MovieProductionProject(Current: TRigmMovieProject; Args: TJSONObject;
  const RequestKey: string): TRigmMovieProject;
function MovieProductionNeeds(Preparation: TJSONObject; const Deliver: string;
  Project: TRigmMovieProject=nil): TJSONArray;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.Math, System.Generics.Collections, RigmJson, RigmModel,
  RigmMovieActing, RigmMovieOutput;

procedure Put(O: TJSONObject; const Key: string; V: TJSONValue);
begin O.RemovePair(Key).Free; O.AddPair(Key,V); end;
procedure Merge(O,Values: TJSONObject; const Keys: array of string);
begin for var Key in Keys do if Values.GetValue(Key)<>nil then Put(O,Key,Values.GetValue(Key).Clone as TJSONValue); end;
function Canonical(V: TJSONValue): string;
begin
  if V is TJSONObject then begin
    var Keys: TArray<string>; SetLength(Keys,TJSONObject(V).Count);
    for var I := 0 to High(Keys) do Keys[I] := TJSONObject(V).Pairs[I].JsonString.Value;
    System.Generics.Collections.TArray.Sort<string>(Keys);
    Result := '{';
    for var Key in Keys do begin
      if Length(Result)>1 then Result := Result+',';
      var Name := TJSONString.Create(Key); try Result := Result+Name.ToJSON+':'+Canonical(TJSONObject(V).GetValue(Key)); finally Name.Free; end;
    end; Result := Result+'}';
  end else if V is TJSONArray then begin
    Result := '['; for var Item in TJSONArray(V) do begin if Length(Result)>1 then Result := Result+','; Result := Result+Canonical(Item); end; Result := Result+']';
  end else Result := V.ToJSON;
end;
function MovieProductionSignature(Args: TJSONObject): string;
begin
  var O := Args.Clone as TJSONObject;
  try
    for var Key in ['projectId','revision','requestKey'] do O.RemovePair(Key).Free;
    Result := THashSHA2.GetHashString(Canonical(O));
  finally O.Free; end;
end;
function MovieProductionProject(Current: TRigmMovieProject; Args: TJSONObject;
  const RequestKey: string): TRigmMovieProject;
var P: TRigmMovieProject; O: TJSONObject; Script: string; JsonScript: Boolean;
begin
  P := nil; O := nil; Result := nil;
  try
    var Value := Args.GetValue('script'); var Path := JS(Args,'scriptPath');
    if Path<>'' then begin
      if TFile.GetSize(Path)>16*1024*1024 then raise ERigm.Create('台本ファイルは16MiB以内です。');
      Script := TFile.ReadAllText(Path,TEncoding.UTF8); JsonScript := JS(Args,'format','text')='json';
    end else begin
      Script := ''; JsonScript := Value is TJSONObject;
      if Value is TJSONString then begin Script := Value.Value; JsonScript := JS(Args,'format','text')='json'; end
      else if JsonScript then Script := Value.ToJSON
      else if Value<>nil then raise ERigm.Create('scriptは台本文字列またはJSONオブジェクトです。');
    end;
    if (Value=nil) and (Path='') then P := Current.Clone
    else if JsonScript then begin
      O := ParseObject(Script); var Existing := Current.Json;
      try
        // Resolve only paths supplied by this JSON script against its location.
        // Inherited project references remain relative to the current project file.
        var Base := Current.FileName; if Path<>'' then Base := ExpandFileName(Path);
        for var Key in ['character','ffmpeg'] do if (O.GetValue(Key)<>nil) and (JS(O,Key)<>'@sample') then
          Put(O,Key,TJSONString.Create(ResolveMoviePath(Base,JS(O,Key))));
        if O.GetValue('cues')<>nil then for var V in JA(O,'cues') do
          for var Key in ['background','waveFile','labFile'] do if TJSONObject(V).GetValue(Key)<>nil then
            Put(TJSONObject(V),Key,TJSONString.Create(ResolveMoviePath(Base,JS(TJSONObject(V),Key))));
        for var Key in ['title','character','engineUrl','width','height','fps','backgroundColor','ffmpeg','encodeProfile','outputTarget','speakers'] do
          if O.GetValue(Key)=nil then O.AddPair(Key,Existing.GetValue(Key).Clone as TJSONValue);
        if O.GetValue('cues')<>nil then for var V in JA(O,'cues') do begin
          var Id := JS(TJSONObject(V),'speaker','narrator'); var Found := False;
          for var S in JA(O,'speakers') do if JS(TJSONObject(S),'id')=Id then Found := True;
          if not Found then begin var S := TRigmMovieSpeaker.Create; try S.Id := Id; S.Name := Id; JA(O,'speakers').AddElement(S.Json); finally S.Free; end; end;
        end;
        P := TRigmMovieProject.FromJson(O);
      finally Existing.Free; FreeAndNil(O); end;
    end else begin
      P := TRigmMovieProject.FromText(Script);
      P.Title := Current.Title; P.CharacterFile := Current.CharacterFile; P.EngineUrl := Current.EngineUrl;
      P.Width := Current.Width; P.Height := Current.Height; P.Fps := Current.Fps;
      P.BackgroundColor := Current.BackgroundColor; P.FfmpegExe := Current.FfmpegExe;
      P.EncodeProfile := Current.EncodeProfile; P.OutputTarget := Current.OutputTarget;
      for var S in P.Speakers do begin
        var Old := Current.Speaker(S.Id);
        if Old<>nil then begin S.Name := Old.Name; S.StyleId := Old.StyleId; S.Speed := Old.Speed; S.Pitch := Old.Pitch; S.Intonation := Old.Intonation; S.Volume := Old.Volume; end;
      end;
      // Reuse audio and authored acting for unchanged cues; changed dialogue gets a new fingerprint.
      for var I := 0 to Min(P.Cues.Count,Current.Cues.Count)-1 do begin
        var C := P.Cues[I]; var Old := Current.Cues[I];
        C.Pause := Old.Pause; C.Expression := Old.Expression; C.Motion := Old.Motion; C.Background := Old.Background;
        C.Parameters.Free; C.Parameters := Old.Parameters.Clone as TJSONObject;
        var ExistingActing := Old.Acting.Json;
        try C.Acting.Free; C.Acting := TRigmMovieActing.FromJson(ExistingActing); finally ExistingActing.Free; end;
        if (C.Text=Old.Text) and (C.SpeakerId=Old.SpeakerId) then begin
          C.Id := Old.Id; C.WaveFile := Old.WaveFile; C.LabFile := Old.LabFile; C.AudioKey := Old.AudioKey; C.AudioSeconds := Old.AudioSeconds;
          C.Subtitle := Old.Subtitle; C.Pause := Old.Pause; C.Expression := Old.Expression; C.Motion := Old.Motion; C.Background := Old.Background;
          C.Parameters.Free; C.Parameters := Old.Parameters.Clone as TJSONObject;
          var Acting := Old.Acting.Json; try C.Acting.Free; C.Acting := TRigmMovieActing.FromJson(Acting); finally Acting.Free; end;
        end;
      end;
    end;
    P.Id := Current.Id; P.FileName := Current.FileName; O := P.Json;
    if Args.GetValue('settings')<>nil then begin
      var Settings := JO(Args,'settings');
      if Settings.GetValue('outputPreset')<>nil then begin
        var W,H,F: Integer; MoviePresetDimensions(JS(Settings,'outputPreset'),W,H,F);
        if W>0 then begin Put(O,'width',TJSONNumber.Create(W)); Put(O,'height',TJSONNumber.Create(H)); Put(O,'fps',TJSONNumber.Create(F)); end;
      end;
      Merge(O,Settings,['title','character','engineUrl','width','height','fps','backgroundColor','ffmpeg','encodeProfile','outputTarget']);
    end;
    if Args.GetValue('voices')<>nil then begin
      for var Pair in JO(Args,'voices') do begin
        var Speaker: TJSONObject := nil;
        for var V in JA(O,'speakers') do if JS(TJSONObject(V),'id')=Pair.JsonString.Value then Speaker := TJSONObject(V);
        if Speaker=nil then raise ERigm.Create('台本に存在しない話者です: '+Pair.JsonString.Value);
        if Pair.JsonValue is TJSONNumber then Put(Speaker,'styleId',Pair.JsonValue.Clone as TJSONNumber)
        else if Pair.JsonValue is TJSONObject then Merge(Speaker,TJSONObject(Pair.JsonValue),['name','styleId','speed','pitch','intonation','volume'])
        else raise ERigm.Create('voicesにはstyleIdまたは声の設定オブジェクトを指定してください。');
      end;
    end;
    if Args.GetValue('acting')<>nil then for var V in JA(O,'cues') do Merge(JO(TJSONObject(V),'acting'),JO(Args,'acting'),
      ['mouthMode','blinkMode','mouthGain','lipLead','blinkStrength','blinkInterval','blinkDuration','blinkPhase','headGain','bodyGain','onset','duration','fadeIn','fadeOut','variants']);
    FreeAndNil(P); P := TRigmMovieProject.FromJson(O); P.FileName := Current.FileName; P.Id := Current.Id;
    var Target := JS(Args,'outputPath');
    if (Target='') and (Args.GetValue('settings')<>nil) then Target := JS(JO(Args,'settings'),'outputTarget');
    if Target='' then begin
      var Directory := ExtractFilePath(ResolveMoviePath(Current.FileName,Current.OutputTarget));
      if Current.OutputTarget='' then Directory := TPath.Combine(TPath.GetDocumentsPath,'RIGMMaker\Movies');
      var Ext := ExtractFileExt(Current.OutputTarget);
      if Ext='' then begin Ext := '.avi'; if FileExists(P.FfmpegExe) then Ext := '.mp4'; end;
      Target := TPath.Combine(Directory,'production-'+THashSHA2.GetHashString(RequestKey).Substring(0,24)+Ext);
    end;
    P.OutputTarget := ResolveMoviePath(Current.FileName,Target);
    P.Validate; Result := P; P := nil;
  finally O.Free; P.Free; end;
end;
function MovieProductionNeeds(Preparation: TJSONObject; const Deliver: string;
  Project: TRigmMovieProject): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var V in JA(Preparation,'issues') do begin
    var O := TJSONObject(V); var Code := JS(O,'code');
    if not JB(O,'blocking') or (Code='audio_pending') then Continue;
    if (Deliver='preview') and (JS(O,'scope')='output') then Continue;
    if (Code='speaker_unavailable') and (Project<>nil) then begin
      var Pending := False;
      for var C in Project.Cues do if (C.SpeakerId=JS(O,'subjectId')) and not Project.AudioReady(C) then Pending := True;
      if not Pending then Continue;
    end;
    Result.AddElement(O.Clone as TJSONObject);
  end;
end;
end.
