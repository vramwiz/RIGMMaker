unit RigmScriptClosingModel;
interface
uses System.JSON, RigmMovieModel;
procedure PrepareScriptClosing(Project: TRigmMovieProject);
procedure ValidateScriptClosing(Project: TRigmMovieProject);
procedure SetScriptClosingDraft(Project: TRigmMovieProject; Draft: TJSONObject);
procedure MaterializeScriptClosing(Project: TRigmMovieProject);
function ScriptClosingCards(Project: TRigmMovieProject): TJSONArray;
function ScriptClosingScene(Project: TRigmMovieProject): string;
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Math, System.StrUtils, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, RigmJson, RigmModel, PsdJson, RigmMovieEndCards, RigmMovieComposition;
function ScriptClosingScene(Project: TRigmMovieProject): string;
begin Result := ''; for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'section')='closing' then begin var C := Project.Cue(JS(TJSONObject(V),'cueId')); if C<>nil then Exit(C.Scene); end; end;
procedure ValidateDraft(D: TJSONObject);
begin
  if not(D.GetValue('title') is TJSONString) or (Length(JS(D,'title'))>128) then raise Exception.Create('締め題名は128文字以内です。'); ValidateVoiceReading(JS(D,'title'));
  for var Key in ['representative','endImage','thumbnailImage'] do if not(D.GetValue(Key) is TJSONString) or (Length(JS(D,Key))>32760) then raise Exception.Create('締め画像の保存形式が不正です。');
  for var Key in ['representativeChoice','endChoice','thumbnailChoice'] do if not(D.GetValue(Key) is TJSONString) or not MatchStr(JS(D,Key),['','none','use']) then raise Exception.Create('画像の採用か省略を選んでください。');
  for var Key in ['endSeconds','thumbnailSeconds'] do if not(D.GetValue(Key) is TJSONString) or (Length(JS(D,Key))>32) then raise Exception.Create('表示秒数は数値文字列です。');
  if not(D.GetValue('rect') is TJSONObject) or not(D.GetValue('reserved') is TJSONArray) or (JA(D,'reserved').Count<1) or (JA(D,'reserved').Count>6) then raise Exception.Create('終了画像と回避領域の配置が必要です。');
  // 途中の数値文字列も保存する。厳密な割合検査は確認完了時。
  var A := TJSONArray.Create; try A.AddElement(JO(D,'rect').Clone as TJSONObject); for var V in JA(D,'reserved') do A.AddElement(V.Clone as TJSONValue);
    for var V in A do begin if not(V is TJSONObject) then raise Exception.Create('配置行の形式が不正です。'); for var Key in ['x','y','width','height'] do if not(TJSONObject(V).GetValue(Key) is TJSONString) or (Length(JS(TJSONObject(V),Key))>32) then raise Exception.Create('配置は数値文字列です。'); end;
  finally A.Free; end;
end;
procedure PrepareScriptClosing(Project: TRigmMovieProject);
begin
  if Project.ScriptWizard.GetValue('closingData')=nil then begin
    var O := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptClosing","schemaVersion":1,"status":"draft","draft":{"title":"","representative":"","representativeChoice":"","endChoice":"","endImage":"","endSeconds":"5","thumbnailChoice":"","thumbnailImage":"","thumbnailSeconds":"2","rect":{"x":"0.05","y":"0.08","width":"0.32","height":"0.72"},"reserved":[{"x":"0.44","y":"0.15","width":"0.25","height":"0.36"},{"x":"0.72","y":"0.15","width":"0.25","height":"0.36"},{"x":"0.65","y":"0.65","width":"0.14","height":"0.24"}]}}');
    PsdJson.Put(JO(O,'draft'),'title',Project.Title); Project.ScriptWizard.AddPair('closingData',O);
  end; ValidateScriptClosing(Project);
end;
procedure ValidateScriptClosing(Project: TRigmMovieProject);
begin var O := JO(Project.ScriptWizard,'closingData'); if (JS(O,'format')<>'RIGMMaker.ScriptClosing') or (JI(O,'schemaVersion')<>1) or not(O.GetValue('draft') is TJSONObject) or not MatchStr(JS(O,'status'),['draft','complete']) then raise Exception.Create('締め設定の保存形式が不正です。'); ValidateDraft(JO(O,'draft')); end;
procedure SetScriptClosingDraft(Project: TRigmMovieProject; Draft: TJSONObject);
begin ValidateDraft(Draft); PrepareScriptClosing(Project); var O := JO(Project.ScriptWizard,'closingData'); if JO(O,'draft').ToJSON=Draft.ToJSON then Exit; PsdJson.Put(O,'draft',Draft.Clone as TJSONObject); PsdJson.Put(O,'status','draft'); end;
function Number(const Value,LabelText: string): Double;
begin if not TryStrToFloat(Value,Result,TFormatSettings.Invariant) or not Finite(Result) then raise Exception.Create(LabelText+'を数値で入力してください。'); end;
function Rectangle(O: TJSONObject): TJSONObject;
begin Result := TJSONObject.Create; try for var Key in ['x','y','width','height'] do AddN(Result,Key,Number(JS(O,Key),'割合座標')); ValidateCardRect(Result); except Result.Free; raise; end; end;
function ScriptClosingCards(Project: TRigmMovieProject): TJSONArray;
begin
  ValidateScriptClosing(Project); var D := JO(JO(Project.ScriptWizard,'closingData'),'draft'); Result := TJSONArray.Create;
  try
    for var Kind in ['end','thumbnail'] do begin var Choice := JS(D,Kind+'Choice'); if not MatchStr(Choice,['none','use']) then raise Exception.Create('終了画像とサムネイルは採用/省略を明示してください。'); if Choice='none' then Continue;
      var Path := JS(D,Kind+'Image'); if (Path='') or not FileExists(ResolveMoviePath(Project.FileName,Path)) then raise Exception.Create('採用する画像がありません。既存画像を選んでください。');
      var Card := TJSONObject.Create; Result.AddElement(Card); Card.AddPair('kind',Kind); Card.AddPair('image',Path); AddN(Card,'duration',Number(JS(D,Kind+'Seconds'),'表示秒数'));
      if Kind='end' then begin Card.AddPair('rect',Rectangle(JO(D,'rect'))); var A := TJSONArray.Create; Card.AddPair('reserved',A); for var V in JA(D,'reserved') do A.AddElement(Rectangle(TJSONObject(V))); end
      else Card.AddPair('rect',PsdJson.ObjectText('{"x":0,"y":0,"width":1,"height":1}'));
    end; ValidateMovieEndCards(Result);
  except Result.Free; raise; end;
end;
procedure MaterializeScriptClosing(Project: TRigmMovieProject);
  procedure Image(const Value: string);
  begin
    var Path := ResolveMoviePath(Project.FileName,Value);
    if not FileExists(Path) or not MatchText(ExtractFileExt(Path),['.png','.jpg','.jpeg','.bmp']) then raise Exception.Create('既存PNG/JPEG/BMPを選んでください。');
    if TFile.GetSize(Path)>33554432 then raise Exception.Create('画像は32MB以内です。');
    var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite); var Picture := TPicture.Create;
    try Picture.LoadFromFile(Path); if (Picture.Width<1) or (Picture.Height<1) or (Picture.Width>8192) or (Picture.Height>8192) or (Int64(Picture.Width)*Picture.Height>16777216) then raise Exception.Create('画像は8192px/辺、16MP以内です。');
    finally Picture.Free; Guard.Free; end;
  end;
begin
  PrepareScriptClosing(Project); var D := JO(JO(Project.ScriptWizard,'closingData'),'draft'); var Choice := JS(D,'representativeChoice'); if not MatchStr(Choice,['none','use']) then raise Exception.Create('締めの代表画像を採用/省略で選んでください。');
  var Path := JS(D,'representative'); if (Choice='use') and ((Path='') or not FileExists(ResolveMoviePath(Project.FileName,Path))) then raise Exception.Create('締め代表画像がありません。');
  var Cards := ScriptClosingCards(Project); try
    if Choice='use' then Image(Path); for var V in Cards do Image(JS(TJSONObject(V),'image'));
    for var S in Project.Scenes do S.Animation.RemovePair('closingCard').Free;
    for var V in JA(JO(Project.ScriptWizard,'casting'),'rows') do if JS(TJSONObject(V),'section')='closing' then begin
      var C := Project.Cue(JS(TJSONObject(V),'cueId')); if C=nil then Continue; var S := Project.Scene(C.Scene); if S=nil then Continue;
      var Closing := TJSONObject.Create; Closing.AddPair('title',JS(D,'title')); Closing.AddPair('representativeChoice',Choice); Closing.AddPair('image',Path); PsdJson.Put(S.Animation,'closingCard',Closing);
    end;
    Project.EndCards.Free; Project.EndCards := Cards; Cards := nil; PsdJson.Put(JO(Project.ScriptWizard,'closingData'),'status','complete');
  finally Cards.Free; end;
end;
end.
