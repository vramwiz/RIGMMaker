// ジョブの読み取り結果をGUI向けの進捗文へ変換する。ジョブの開始や状態変更は行わない。
unit RigmMovieJobPresentation;
interface
uses System.JSON;
// Jobの工程・進捗・残り時間・エラーから表示文を返す。入力JSONは変更しない。
function MovieJobText(Job: TJSONObject): string;
implementation
uses System.SysUtils, System.Math, System.Generics.Collections, RigmJson;
function MovieJobText(Job: TJSONObject): string;
var Phase,State: string; Completed,Total,Remaining: Double;
begin
  Phase := JS(Job,'phase'); State := JS(Job,'state');
  if Phase='prepare-character' then Phase := 'キャラクター読込'
  else if Phase='prepare-audio' then Phase := '音声の準備'
  else if Phase='render' then Phase := '映像の作成'
  else if Phase='encode' then Phase := '動画の圧縮'
  else begin
    Phase := JS(Job,'kind');
    if Phase='production' then Phase := '一括制作'
    else if Phase='preview' then Phase := 'プレビュー'
    else if Phase='audio' then Phase := '音声生成'
    else if Phase='assets' then Phase := '素材読込'
    else if Phase='waveform' then Phase := '波形の作成'
    else if Phase='speakers' then Phase := '話者取得'
    else if Phase='playback-audio' then Phase := '再生の準備';
  end;
  if State='blocked' then State := '不足情報待ち' else if State='succeeded' then State := '完了' else if State='failed' then State := '失敗'
  else if State='cancelled' then State := '取消済み' else if JB(Job,'cancelRequested') then State := '取消中'
  else State := '処理中';
  Completed := JN(Job,'phaseCompleted'); Total := JN(Job,'phaseTotal');
  if Total=0 then begin Completed := JN(Job,'completed'); Total := JN(Job,'total'); end;
  Result := Phase+' '+State;
  if Total>0 then Result := Result+Format(' %.0f%%',[Min(100,Completed/Total*100)]);
  if JN(Job,'elapsedSeconds')>0 then Result := Result+Format(' 経過 %.0f秒',[JN(Job,'elapsedSeconds')]);
  Remaining := JN(Job,'remainingSeconds',-1);
  if not JB(Job,'done') then begin
    if Remaining>=0 then Result := Result+Format(' この工程の残り約%.0f秒',[Remaining])
    else Result := Result+' 残り時間を計算中';
  end;
  if JS(Job,'error')<>'' then Result := Result+' '+JS(Job,'error');
  if Job.GetValue('production')<>nil then begin
    var Needs := JA(JO(Job,'production'),'needs');
    if Needs.Count>0 then Result := Result+' '+JS(TJSONObject(Needs[0]),'message');
  end;
end;
end.
