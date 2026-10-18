program ReadingCorrectionCheck;
{$APPTYPE CONSOLE}
// モデルだけの所有fixture。HTTP・実台本・音声ファイルへの書込みは行わない。
uses System.SysUtils, System.JSON, RigmMovieModel, RigmScriptReadingModel, RigmJson, PsdJson;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Writeln('PASS ',Message); end;
function JsonOf(P: TRigmMovieProject): string;
begin var O := P.Json; try Result := O.ToJSON; finally O.Free; end; end;
function AddCue(P: TRigmMovieProject; const Text,Reading: string): TRigmMovieCue;
begin
  Result := TRigmMovieCue.Create; Result.Text := Text; Result.Subtitle := Text; Result.VoiceReading := Reading;
  Result.AudioKey := 'old-audio'; Result.VoiceQuery := '{}'; Result.VoiceQueryKey := StringOfChar('a',64);
  Result.VoiceHeardKey := 'old-heard'; Result.EffectAudioKey := 'old-effect';
  Result.WaveFile := 'old.wav'; Result.LabFile := 'old.lab'; Result.EffectWaveFile := 'old-effect.wav'; Result.AudioSeconds := 3;
  P.Cues.Add(Result);
end;
procedure Run;
begin
  var P := TRigmMovieProject.Create;
  try
    P.ScriptWizard := TJSONObject.Create.AddPair('stage','subtitles');
    var A := AddCue(P,'神獣の赤ちゃん。','');
    var B := AddCue(P,'神獣を見守ります。','しんじゅうを見守ります。');
    var C := AddCue(P,'森の神獣と幻獣。','森の神獣とげんじゅう！');
    AddCue(P,'世界樹の森。','');
    var D := ScriptReadingDictionary(P);
    try
      var Before := JsonOf(P); var Candidates := ScriptReadingCorrections(P,D);
      try
        Check((Candidates.Count=3) and (JsonOf(P)=Before),'checking readings is read-only and skips corrected kana');
        Check((JS(TJSONObject(Candidates[0]),'subtitle')=A.Subtitle) and
          (JS(TJSONObject(Candidates[0]),'after')='しんじゅうの赤ちゃん。'),'subtitle stays kanji while proposed reading is kana');
        Check(JS(TJSONObject(Candidates[1]),'after')='森のしんじゅうとげんじゅう！','other manually edited pronunciation and punctuation survive');
        var Bad := Candidates.Clone as TJSONArray;
        try
          PsdJson.Put(TJSONObject(Bad[1]),'after','辞書と異なる読み'); var Rejected := False;
          try ApplyScriptReadingCorrections(P,D,Bad); except on E: Exception do Rejected := True; end;
          Check(Rejected and (JsonOf(P)=Before),'invalid later candidate rejects whole batch without partial changes');
        finally Bad.Free; end;
        var OtherBefore := B.Json; var UncheckedBefore := C.Json;
        var Selected := TJSONArray.Create;
        try
          Selected.AddElement(Candidates[0].Clone as TJSONObject);
          Check(ApplyScriptReadingCorrections(P,D,Selected)=1,'only selected cue is corrected');
          Check((A.Text='神獣の赤ちゃん。') and (A.Subtitle=A.Text) and (A.VoiceReading='しんじゅうの赤ちゃん。'),
            'applying reading leaves manuscript and subtitle unchanged');
          Check((A.AudioKey='') and (A.VoiceQuery='') and (A.VoiceQueryKey='') and (A.VoiceHeardKey='') and
            (A.EffectAudioKey='') and (A.WaveFile='old.wav') and (A.LabFile='old.lab') and
            (A.EffectWaveFile='old-effect.wav') and (A.AudioSeconds=3),'only selected audio acceptance is invalidated and old files remain');
          var OtherAfter := B.Json; var UncheckedAfter := C.Json;
          try Check((OtherBefore.ToJSON=OtherAfter.ToJSON) and (UncheckedBefore.ToJSON=UncheckedAfter.ToJSON),
            'manually corrected and unchecked cues retain full audio and accent data');
          finally OtherAfter.Free; UncheckedAfter.Free; end;
          var Saved := ScriptReadingDictionary(P);
          try Check(Saved.ToJSON=D.ToJSON,'project dictionary survives JSON storage'); finally Saved.Free; end;
          var State := JsonOf(P); var Rejected := False;
          try ApplyScriptReadingCorrections(P,D,Selected); except on E: Exception do Rejected := True; end;
          Check(Rejected and (JsonOf(P)=State),'stale candidate cannot overwrite a later reading');
        finally Selected.Free; OtherBefore.Free; UncheckedBefore.Free; end;
      finally Candidates.Free; end;
      D.AddElement(TJSONObject.Create.AddPair('word','神獣王').AddPair('reading','しんじゅうおう'));
      Check(CorrectScriptReading('神獣王と神獣',D)='しんじゅうおうとしんじゅう','longer word overrides shorter dictionary match');
      D.AddElement(TJSONObject.Create.AddPair('word','しんじゅう').AddPair('reading','げんじゅう'));
      Check(CorrectScriptReading('神獣',D)='しんじゅう','replacement output is not recursively replaced');
      Check(CorrectScriptReading('未登録の名前',D)='未登録の名前','unknown proper names are not guessed');
      D.AddElement(TJSONObject.Create.AddPair('word','神獣').AddPair('reading','かみじゅう'));
      var Rejected := False;
      try ValidateReadingDictionary(D); except on E: Exception do Rejected := True; end;
      Check(Rejected,'duplicate dictionary entries are rejected');
    finally D.Free; end;
  finally P.Free; end;
  P := TRigmMovieProject.Create;
  try
    P.ScriptWizard := TJSONObject.Create;
    var Summary := TJSONObject.Create.AddPair('materialized',TJSONBool.Create(True)).AddPair('sceneId','summary')
      .AddPair('draft',TJSONObject.Create).AddPair('appliedDraft',TJSONObject.Create);
    P.ScriptWizard.AddPair('summaryData',Summary);
    var A := AddCue(P,'神獣',''); A.Scene := 'summary';
    var B := AddCue(P,StringOfChar('あ',1995),''); B.Scene := 'summary';
    var D := ScriptReadingDictionary(P);
    try
      var Candidates := ScriptReadingCorrections(P,D);
      try
        var Before := JsonOf(P); var Rejected := False;
        try ApplyScriptReadingCorrections(P,D,Candidates); except on E: Exception do Rejected := True; end;
        Check(Rejected and (JsonOf(P)=Before),'combined summary reading overflow is rejected atomically');
        B.Text := '幻獣'; B.Subtitle := B.Text;
        var Fresh := ScriptReadingCorrections(P,D);
        try
          Check(ApplyScriptReadingCorrections(P,D,Fresh)=2,'summary correction applies when combined text fits');
          Check((JS(JO(Summary,'draft'),'reading')='しんじゅう'+#13#10+'げんじゅう') and
            (JS(JO(Summary,'appliedDraft'),'reading')=JS(JO(Summary,'draft'),'reading')),
            'summary draft and applied reading stay synchronized');
        finally Fresh.Free; end;
      finally Candidates.Free; end;
    finally D.Free; end;
  finally P.Free; end;
end;
begin
  try Run;
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
