unit RigmMoviePosting;

// 投稿文は映像・音声の入力とは分離し、作品と一緒に保存する。
interface
uses System.JSON, RigmMovieModel;
const MovieParentWorks = 'sm33517192 nc256993';
function MoviePostingInfo(Project: TRigmMovieProject): TJSONObject; // 呼出側所有。未作成なら既定値。
function MoviePostingDescription(Project: TRigmMovieProject): string;
procedure ValidateMoviePosting(Info: TJSONObject);
implementation
uses System.SysUtils, System.DateUtils, System.IOUtils, RigmJson, RigmModel;

procedure ValidateMoviePosting(Info: TJSONObject);
begin
  if Info=nil then Exit;
  for var Key in ['title','description','createdDate'] do
    if not (Info.GetValue(Key) is TJSONString) then raise ERigm.Create('投稿用情報の文字列がありません。');
  if (Length(JS(Info,'title'))>1000) or (Length(JS(Info,'description'))>20000) or
    (Length(JS(Info,'createdDate'))<>10) then raise ERigm.Create('投稿用情報が長すぎるか、作成日が不正です。');
  for var Ch in JS(Info,'title') do if Ord(Ch)<32 then raise ERigm.Create('投稿タイトルは1行で入力してください。');
  for var Ch in JS(Info,'description') do if (Ord(Ch)<32) and not CharInSet(Ch,[#9,#10,#13]) then
    raise ERigm.Create('概要に無効な制御文字があります。');
  var D: TDateTime;
  if not TryISO8601ToDate(JS(Info,'createdDate')+'T00:00:00Z',D) then raise ERigm.Create('投稿用情報の作成日が不正です。');
end;

function ConfirmedWork(Project: TRigmMovieProject): TJSONObject;
begin
  Result := nil; if Project.ScriptWizard=nil then Exit;
  var R := Project.ScriptWizard.GetValue('research');
  if R is TJSONObject then begin
    if not JB(TJSONObject(R),'humanConfirmed') then Exit;
    for var V in JA(TJSONObject(R),'candidates') do
      if JS(TJSONObject(V),'id')=JS(TJSONObject(R),'selectedCandidateId') then Exit(TJSONObject(V));
    Exit;
  end;
  var Integration := Project.ScriptWizard.GetValue('researchIntegration');
  if (Integration is TJSONObject) and (TJSONObject(Integration).GetValue('work') is TJSONObject) then
    Result := JO(TJSONObject(Integration),'work');
end;

function MoviePostingDescription(Project: TRigmMovieProject): string;
begin
  Result := ''; var Work := ConfirmedWork(Project); if Work=nil then Exit;
  Result := JS(Work,'name');
  if JS(Work,'author')<>'' then Result := Result+#13#10+'作者:'+JS(Work,'author');
  if JS(Work,'niconicoUrl')<>'' then Result := Result+#13#10+JS(Work,'niconicoUrl');
  if JS(Work,'postingSummary')<>'' then Result := Result+#13#10+#13#10+JS(Work,'postingSummary');
end;

function MoviePostingInfo(Project: TRigmMovieProject): TJSONObject;
begin
  if Project.Posting<>nil then Exit(Project.Posting.Clone as TJSONObject);
  var Created := Date; var Stamp := ''; var UTC: TDateTime;
  if Project.ScriptWizard<>nil then Stamp := JS(Project.ScriptWizard,'createdAt');
  if TryISO8601ToDate(Stamp,UTC,True) then Created := TTimeZone.Local.ToLocalTime(UTC)
  else if (Project.FileName<>'') and FileExists(Project.FileName) then Created := TFile.GetCreationTime(Project.FileName);
  Result := TJSONObject.Create;
  Result.AddPair('createdDate',FormatDateTime('yyyy-mm-dd',Created));
  Result.AddPair('title','【ニコニコ漫画】ニコニコ漫画の作品を紹介する　'+Project.Title+'  #60 【'+
    FormatDateTime('yyyy"年"m"月"d"日"',Created)+'】');
  Result.AddPair('description',MoviePostingDescription(Project));
end;
end.
