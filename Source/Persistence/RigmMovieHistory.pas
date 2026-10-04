unit RigmMovieHistory;

interface
uses System.JSON;
function IsMovieRecovery(const Root,Path: string): Boolean;
procedure NormalizeMovieHistory(const Root: string; Recent,Recoveries: TJSONArray);
procedure AddMovieRecovery(Recent,Recoveries: TJSONArray; Entry: TJSONObject);

implementation
uses System.SysUtils, System.IOUtils, System.StrUtils, System.Generics.Collections, RigmJson;

procedure Put(O: TJSONObject; const Key,Value: string);
begin if (O.GetValue(Key)<>nil) and (JS(O,Key)=Value) then Exit; O.RemovePair(Key).Free; O.AddPair(Key,Value); end;
function Absolute(const Path: string): string;
begin if Path='' then Exit(''); Result := ExpandFileName(Path); end;
function IsMovieRecovery(const Root,Path: string): Boolean;
begin
  var Full := Absolute(Path); var Name := ExtractFileName(Full);
  Result := StartsText('recovery-',Name) and SameText(ExtractFileExt(Name),'.rigmovie') and
    (SameText(ExtractFileDir(Full),TPath.Combine(Root,'Recovery')) or
     SameText(ExtractFileDir(Full),TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),'RIGMMaker\MovieRecovery')));
end;
function ProjectId(const Path: string): string;
begin
  Result := '';
  try
    if not FileExists(Path) or (TFile.GetSize(Path)>16*1024*1024) then Exit;
    var O := ParseObject(TFile.ReadAllText(Path,TEncoding.UTF8));
    try if JS(O,'format')='RIGM-MOVIE' then Result := JS(O,'projectId'); finally O.Free; end;
  except Result := ''; end;
end;
procedure AddMovieRecovery(Recent,Recoveries: TJSONArray; Entry: TJSONObject);
begin
  // This journal references copies; neither normalization nor replacement deletes files.
  var Path := Absolute(JS(Entry,'path')); Put(Entry,'path',Path);
  for var I := Recoveries.Count-1 downto 0 do
    if SameText(JS(TJSONObject(Recoveries[I]),'path'),Path) then begin
      var Existing := TJSONObject(Recoveries[I]);
      if JS(Entry,'sourcePath')='' then Put(Entry,'sourcePath',JS(Existing,'sourcePath'));
      if CompareStr(JS(Existing,'accessed'),JS(Entry,'accessed'))>=0 then begin
        if JS(Existing,'sourcePath')='' then Put(Existing,'sourcePath',JS(Entry,'sourcePath'));
        Entry.Free; Exit;
      end;
      Recoveries.Remove(I).Free;
    end;
  Recoveries.AddElement(Entry);
  var Source := JS(Entry,'sourcePath');
  if Source<>'' then for var V in Recent do begin
    var O := TJSONObject(V);
    if SameText(JS(O,'path'),Source) then begin
      var Current := O.GetValue('recovery');
      if (Current=nil) or (CompareStr(JS(Entry,'accessed'),JS(TJSONObject(Current),'accessed'))>=0) then begin
        O.RemovePair('recovery').Free; O.AddPair('recovery',Entry.Clone as TJSONObject);
      end;
      Break;
    end;
  end;
end;
procedure NormalizeMovieHistory(const Root: string; Recent,Recoveries: TJSONArray);
var Normal,Pending: TJSONArray; Seen: TDictionary<string,Boolean>;
begin
  Normal := TJSONArray.Create; Pending := TJSONArray.Create; Seen := TDictionary<string,Boolean>.Create;
  try
    for var V in Recent do begin
      if not(V is TJSONObject) then Continue;
      var O := TJSONObject(V).Clone as TJSONObject; var Path := Absolute(JS(O,'path'));
      if Path='' then begin O.Free; Continue; end;
      Put(O,'path',Path);
      if IsMovieRecovery(Root,Path) then begin Pending.AddElement(O); Continue; end;
      var Key := LowerCase(Path);
      if Seen.ContainsKey(Key) then begin O.Free; Continue; end;
      Seen.Add(Key,True);
      if JS(O,'projectId')='' then Put(O,'projectId',ProjectId(Path));
      Normal.AddElement(O);
    end;
    while Recent.Count>0 do Recent.Remove(Recent.Count-1).Free;
    for var V in Normal do if Recent.Count<20 then Recent.AddElement(V.Clone as TJSONObject);
    for var V in Recoveries do Pending.AddElement(V.Clone as TJSONObject);
    while Recoveries.Count>0 do Recoveries.Remove(Recoveries.Count-1).Free;
    for var V in Pending do begin
      var O := TJSONObject(V).Clone as TJSONObject;
      var Id := JS(O,'projectId'); if Id='' then begin Id := ProjectId(JS(O,'path')); Put(O,'projectId',Id); end;
      var Source := JS(O,'sourcePath');
      if IsMovieRecovery(Root,Source) then Source := '';
      if (Source='') and (Id<>'') then begin
        var Matches := 0;
        for var Candidate in Recent do if JS(TJSONObject(Candidate),'projectId')=Id then begin
          Source := JS(TJSONObject(Candidate),'path'); Inc(Matches);
        end;
        // Save-As files can share an ID. Never collapse distinct ordinary files or guess an ambiguous origin.
        if Matches<>1 then Source := '';
      end;
      Put(O,'sourcePath',Absolute(Source)); AddMovieRecovery(Recent,Recoveries,O);
    end;
    while Recoveries.Count>20 do Recoveries.Remove(Recoveries.Count-1).Free;
  finally Seen.Free; Pending.Free; Normal.Free; end;
end;
end.
