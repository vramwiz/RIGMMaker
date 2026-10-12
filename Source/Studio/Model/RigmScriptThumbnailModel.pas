unit RigmScriptThumbnailModel;
// 最後に作る必須サムネイルの参照素材・タイトル・末尾カードを扱う。発話と音声は変更しない。
interface
uses System.JSON, RigmMovieModel;
const RigmThumbnailSeconds = 10;
      RigmThumbnailFadeSeconds = 1;
procedure PrepareScriptThumbnail(Project: TRigmMovieProject);
function ThumbnailLogo(Project: TRigmMovieProject): string;
function ThumbnailSources(Project: TRigmMovieProject): TJSONObject; // 呼出側所有。画像と使用キャラの参照。
function ThumbnailSourceKey(Project: TRigmMovieProject): string;
procedure MaterializeScriptThumbnail(Project: TRigmMovieProject); // 既存thumbnailだけ置換し、終了カードを保持。
function ScriptThumbnailCard(Project: TRigmMovieProject): TJSONObject; // 呼出側所有。
procedure RequireScriptThumbnail(Project: TRigmMovieProject); // 台本からの出力で必須。従来の単独動画は対象外。
implementation
uses System.SysUtils, System.IOUtils, System.Hash, RigmJson, PsdJson, RigmMovieImageTransfer, RigmThumbnailCache, RigmScriptScenesModel;
function ThumbnailLogo(Project: TRigmMovieProject): string;
begin
  var Name := Project.Title;
  if Project.ScriptWizard<>nil then Name := JS(Project.ScriptWizard,'titleInput',Name);
  Result := '漫画　'+Name;
end;
function ThumbnailSources(Project: TRigmMovieProject): TJSONObject;
  procedure Image(Images: TJSONArray; const Kind,Id,Path: string);
  begin
    if Path='' then Exit;
    var O := TJSONObject.Create; Images.AddElement(O); O.AddPair('kind',Kind); O.AddPair('sceneId',Id);
    var Full := ResolveMoviePath(Project.FileName,Path); O.AddPair('path',Full);
    if FileExists(Full) then O.AddPair('sha256',CheckedMovieImageHash(Full)) else O.AddPair('sha256','missing');
  end;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('logo',ThumbnailLogo(Project)); AddN(Result,'width',Project.Width); AddN(Result,'height',Project.Height);
    var Images := TJSONArray.Create; Result.AddPair('images',Images);
    Image(Images,'background',RigmCommonBackgroundId,Project.ThemeBackground);
    for var S in Project.Scenes do Image(Images,'scene',S.Id,S.Image);
    if (Project.ScriptWizard<>nil) and (Project.ScriptWizard.GetValue('closingData') is TJSONObject) then begin
      var Closing := JO(JO(Project.ScriptWizard,'closingData'),'draft');
      if JS(Closing,'representativeChoice')='use' then Image(Images,'representative','closing',JS(Closing,'representative'));
      if JS(Closing,'endChoice')='use' then Image(Images,'end','end',JS(Closing,'endImage'));
    end;
    var Characters := TJSONArray.Create; Result.AddPair('characters',Characters);
    if (Project.ScriptWizard<>nil) and (Project.ScriptWizard.GetValue('selectedCharacters') is TJSONArray) then
      for var V in JA(Project.ScriptWizard,'selectedCharacters') do begin
        var C := TJSONObject(V); var O := TJSONObject.Create; Characters.AddElement(O);
        O.AddPair('name',JS(C,'name')); O.AddPair('renderFormat',JS(C,'renderFormat'));
        var Path := TPath.Combine(ExtractFileDir(ExtractFileDir(ExtractFileDir(Project.FileName))),JS(C,'path'));
        PsdJson.Put(O,'path',Path); if FileExists(Path) then O.AddPair('sourceSignature',CharacterSourceSignature(Path));
      end;
  except Result.Free; raise; end;
end;
function ThumbnailSourceKey(Project: TRigmMovieProject): string;
begin
  var O := ThumbnailSources(Project);
  try
    // 保存で画像の参照先が移っても、素材内容と並びが同じなら要求・確定を維持する。
    for var V in JA(O,'images') do TJSONObject(V).RemovePair('path').Free;
    Result := THashSHA2.GetHashString(O.ToJSON);
  finally O.Free; end;
end;
procedure PrepareScriptThumbnail(Project: TRigmMovieProject);
begin
  var S := Project.Thumbnail;
  if S.Image='' then begin
    for var V in Project.EndCards do if JS(TJSONObject(V),'kind')='thumbnail' then S.Image := JS(TJSONObject(V),'image');
    if (S.Image='') and (Project.ScriptWizard.GetValue('closingData') is TJSONObject) then
      S.Image := JS(JO(JO(Project.ScriptWizard,'closingData'),'draft'),'thumbnailImage');
  end;
  if (S.ImagePrompt='') and not S.ImageApproved then S.ImagePrompt := 'これまでに作ったシーン画像を組み合わせた、動画の最後に表示するサムネイルを作成。'+#13#10+
    '使用中のキャラクターも必ず使い、見た目を参照素材に合わせる。'+#13#10+
    '「漫画」＋マンガの名前を大きく読みやすいロゴとして配置する。';
end;
function ScriptThumbnailCard(Project: TRigmMovieProject): TJSONObject;
begin
  Result := PsdJson.ObjectText('{"kind":"thumbnail","duration":10,"transitionSeconds":1,"rect":{"x":0,"y":0,"width":1,"height":1}}');
  Result.AddPair('image',Project.Thumbnail.Image); Result.AddPair('sourceFingerprint',ThumbnailSourceKey(Project));
end;
procedure MaterializeScriptThumbnail(Project: TRigmMovieProject);
begin
  for var I := Project.EndCards.Count-1 downto 0 do
    if JS(TJSONObject(Project.EndCards[I]),'kind')='thumbnail' then Project.EndCards.Remove(I).Free;
  if Project.Thumbnail.Image='' then Exit;
  Project.EndCards.AddElement(ScriptThumbnailCard(Project));
end;
procedure RequireScriptThumbnail(Project: TRigmMovieProject);
begin
  if Project.ScriptWizard=nil then Exit;
  var S := Project.Thumbnail;
  if not ScriptScenesReady(Project,True) or not S.ImageApproved or (S.Image='') then raise Exception.Create('第16段階の最後で必須のサムネイル画像を作成し、確定してください。');
  CheckedMovieImageHash(ResolveMoviePath(Project.FileName,S.Image),True);
  var Found := False;
  for var V in Project.EndCards do if (JS(TJSONObject(V),'kind')='thumbnail') and
    (JS(TJSONObject(V),'image')=S.Image) and (JS(TJSONObject(V),'sourceFingerprint')=ThumbnailSourceKey(Project)) and
    (Abs(JN(TJSONObject(V),'duration')-RigmThumbnailSeconds)<0.000001) and
    (Abs(JN(TJSONObject(V),'transitionSeconds')-RigmThumbnailFadeSeconds)<0.000001) then begin
    var R := JO(TJSONObject(V),'rect');
    if (JN(R,'x')=0) and (JN(R,'y')=0) and (JN(R,'width')=1) and (JN(R,'height')=1) then Found := True;
  end;
  if not Found then raise Exception.Create('サムネイルを画像工程で確認し、動画末尾へ反映してください。');
end;
end.
