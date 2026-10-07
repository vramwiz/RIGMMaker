program NativeEffectsAnalysisProbe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Math, System.JSON,
  RigmMovieModel, RigmVoiceEffectsDsp, RigmEffectsAnalysis, RigmAul2EffectDefinition;
procedure Check(Value: Boolean; const Description: string);
begin if not Value then raise Exception.Create(Description); end;
procedure Near(Value, Expected, Tolerance: Double; const Description: string);
begin Check(Abs(Value-Expected)<=Tolerance,Description+' actual='+FloatToStr(Value)+' expected='+FloatToStr(Expected)); end;
procedure Add(Cue: TRigmMovieCue; const Name: string; Value: Double);
begin Cue.AudioEffects.RemovePair(Name).Free; Cue.AudioEffects.AddPair(Name,TJSONNumber.Create(Value)); end;
procedure RunValidation;
var Analysis: TRigmEffectsAnalysis; Before,After: TArray<Single>; Audible: TArray<SmallInt>;
begin
  // The builder rejects incomplete, duplicate, nonfinite and out-of-order publication.
  Analysis := TRigmEffectsAnalysis.Create;
  try
    var Rejected := False;
    try Analysis.BeginCapture(7999,0); except on E: EArgumentOutOfRangeException do Rejected := True; end;
    Check(Rejected,'rate limit');
    Rejected := False;
    try Analysis.BeginCapture(192000,192000*600+1); except on E: EArgumentOutOfRangeException do Rejected := True; end;
    Check(Rejected,'duration limit');
    Analysis.BeginCapture(24000,1);
    Rejected := False;
    try Analysis.Seal; except on E: EInvalidOp do Rejected := True; end;
    Check(Rejected and not Analysis.Ready,'incomplete publication');
    Rejected := False;
    try Analysis.BeginBlock(1,1); except on E: EInvalidOp do Rejected := True; end;
    Check(Rejected,'wrong first sample');
    Analysis.BeginBlock(0,1);
    SetLength(Before,1); SetLength(After,1); SetLength(Audible,1);
    Before[0] := 0.25; After[0] := NaN;
    Rejected := False;
    try Analysis.CaptureEffect(0,0,True,Before,After,1); except on E: EInvalidOp do Rejected := True; end;
    Check(Rejected and not Analysis.Ready,'nonfinite stage rejected');
    After[0] := 0.25;
    Analysis.CaptureEffect(0,0,False,Before,After,1);
    Rejected := False;
    try Analysis.CaptureEffect(0,0,False,Before,After,1); except on E: EInvalidOp do Rejected := True; end;
    Check(Rejected,'duplicate stage rejected');
    Rejected := False;
    try Analysis.CaptureAudibleBlock(0,Before,Audible,0,1); except on E: EInvalidOp do Rejected := True; end;
    Check(Rejected,'missing stages rejected');
    for var I := 1 to 19 do Analysis.CaptureEffect(0,I,False,Before,After,1);
    Audible[0] := 8192; Analysis.CaptureAudibleBlock(0,Before,Audible,0,1); Analysis.Seal;
    Rejected := False;
    try Analysis.BlockIndexAt(Infinity); except on E: EArgumentOutOfRangeException do Rejected := True; end;
    Check(Rejected,'nonfinite cursor rejected');
    Rejected := False;
    try Analysis.Block(-1); except on E: EArgumentOutOfRangeException do Rejected := True; end;
    Check(Rejected,'negative block rejected');
    Rejected := False;
    try Analysis.WavePoint(1); except on E: EArgumentOutOfRangeException do Rejected := True; end;
    Check(Rejected,'wave range rejected');
    Near(Analysis.ChainTotal.ResidualRms,0,0,'one sample no artificial residue');
    Near(Analysis.WavePoint(0).InputMin,0.25,0,'one sample no zero bias');
  finally Analysis.Free; end;
  Writeln('PASS native bounds/nonfinite/sequence/publication rejection');
end;
procedure RunEquivalence;
var Cue: TRigmMovieCue; Analysis: TRigmEffectsAnalysis; Original,Fast,Measured,Repeated: TArray<SmallInt>;
begin
  Cue := TRigmMovieCue.Create;
  try
    SetLength(Original,8203);
    for var I := 0 to High(Original) do Original[I] := Round(9000*Sin(I*2*Pi*440/24000));
    Original[4090] := 22000;
    for var Effect := 0 to 19 do begin
      Cue.AudioEffects.Free; Cue.AudioEffects := TJSONObject.Create;
      var Definition: TControllerEffectDefinition;
      GetControllerEffectDefinition(Effect,Definition);
      Add(Cue,Definition.UseItemName,1);
      if Effect=0 then begin Add(Cue,'Dly: Time(ms)',1); Add(Cue,'Dly: Wet',0.5); end;
      if Effect=18 then Add(Cue,'Out: Gain(dB)',-6);
      Fast := Original;
      ApplyCueVoiceEffects(Cue,24000,Fast);
      Analysis := TRigmEffectsAnalysis.Create;
      try
        Measured := Original; ApplyCueVoiceEffects(Cue,24000,Measured,nil,Analysis);
        Check(Analysis.Ready,'each effect capture ready');
        Check(Analysis.EffectTotal(Effect).Applied,'each effect applies');
        for var I := 0 to High(Original) do begin
          if I=4090 then Check(Original[I]=22000,'isolation original pulse')
          else Check(Original[I]=Round(9000*Sin(I*2*Pi*440/24000)),'isolation original PCM');
          Check(Fast[I]=Measured[I],'measured/fast PCM equality');
        end;
      finally Analysis.Free; end;
      Repeated := Original; ApplyCueVoiceEffects(Cue,24000,Repeated);
      for var I := 0 to High(Fast) do Check(Fast[I]=Repeated[I],'repeat resets kernel');
    end;
  finally Cue.Free; end;
  Writeln('PASS all20 actual kernels measured/fast equivalence, source isolation and reset');
end;
procedure Run;
var Cue: TRigmMovieCue; Data,Original: TArray<SmallInt>; Analysis,CopyAnalysis: TRigmEffectsAnalysis;
begin
  Cue := TRigmMovieCue.Create;
  try
    // Bypass every kernel; include endpoints, partial last block and positive-only envelope.
    SetLength(Data,8203); for var I := 0 to High(Data) do Data[I] := 8192;
    Data[0] := -32768; Data[High(Data)] := 32767; Original := Copy(Data);
    Analysis := TRigmEffectsAnalysis.Create;
    try
      ApplyCueVoiceEffects(Cue,24000,Data,nil,Analysis);
      Check(Analysis.Ready and (Analysis.BlockCount=3),'bypass capture ready/block count');
      Check(Analysis.Block(2).SampleCount=11,'partial last block');
      for var I := 0 to High(Data) do Check(Data[I]=Original[I],'bypass original sample');
      for var I := 0 to 19 do begin
        Check(not Analysis.EffectTotal(I).Applied,'bypass applied');
        Near(Analysis.EffectTotal(I).ResidualRms,0,0,'bypass residual');
      end;
      Near(Analysis.ChainTotal.ResidualRms,0,0,'chain bypass residual');
      Check(Analysis.WavePointCount=2048,'wave point cap');
      Near(Analysis.WavePoint(0).InputMin,-1,0,'wave original negative endpoint');
      Near(Analysis.WavePoint(2047).OutputMax,32767/32768,0,'wave output positive endpoint');
      Near(Analysis.WavePoint(100).InputMin,0.25,0,'positive bin minimum');
      Near(Analysis.WavePoint(100).InputMax,0.25,0,'positive bin maximum');
      var Covered: Int64 := 0;
      for var I := 0 to Analysis.WavePointCount-1 do begin
        Check(Analysis.WavePoint(I).FirstSample=Covered,'wave contiguous coverage');
        Inc(Covered,Analysis.WavePoint(I).SampleCount);
      end;
      Check(Covered=Length(Data),'wave total coverage');
      Check(Analysis.BlockIndexAt(-1)=0,'cursor negative');
      Check(Analysis.BlockIndexAt(100)=2,'cursor after end');
      Check(Analysis.BlockIndexAt(4096.5/24000)=1,'cursor boundary');
      CopyAnalysis := Analysis.Clone;
      try
        Check(CopyAnalysis.Ready and (CopyAnalysis.BlockCount=3),'clone metadata');
        Near(CopyAnalysis.ChainTotal.InputRms,Analysis.ChainTotal.InputRms,0,'clone value');
        var Rejected := False;
        try CopyAnalysis.BeginCapture(24000,0); except on E: EInvalidOp do Rejected := True; end;
        Check(Rejected,'sealed mutation rejection');
      finally CopyAnalysis.Free; end;
    finally Analysis.Free; end;
    Writeln('PASS native bypass/partial blocks/envelope/cursors/seal/clone');
    // Actual copied output DSP at -6 dB.
    Add(Cue,'Out: Use',1); Add(Cue,'Out: Gain(dB)',-6);
    SetLength(Data,5000); for var I := 0 to High(Data) do Data[I] := 16384;
    Analysis := TRigmEffectsAnalysis.Create;
    try
      ApplyCueVoiceEffects(Cue,24000,Data,nil,Analysis);
      var Gain := Power(10,-6/20);
      Near(Analysis.EffectTotal(18).InputRms,0.5,0,'gain stage input');
      Near(Analysis.EffectTotal(18).OutputRms,0.5*Gain,0.000001,'gain stage output');
      Near(Analysis.EffectTotal(18).ResidualRms,0.5*(1-Gain),0.000001,'gain stage residual');
      Check(Analysis.EffectTotal(18).Applied,'gain applied flag');
      Near(Analysis.ChainTotal.OutputRms,Data[0]/32768,0,'audible gain RMS');
      Check(Data[0]=Round(0.5*Gain*32768),'audible gain quantization');
    finally Analysis.Free; end;
    Writeln('PASS native copied Output -6dB and audible quantization');
    // Raw stage peak may exceed unity; final chain must describe clipped PCM.
    Add(Cue,'Out: Gain(dB)',24);
    SetLength(Data,17); for var I := 0 to High(Data) do Data[I] := 30000;
    Analysis := TRigmEffectsAnalysis.Create;
    try
      ApplyCueVoiceEffects(Cue,48000,Data,nil,Analysis);
      Check(Analysis.EffectTotal(18).OutputPeak>1,'raw gain overload measured');
      Near(Analysis.ChainTotal.OutputPeak,32767/32768,0,'final clipped peak');
      Near(Analysis.WavePoint(0).OutputMax,32767/32768,0,'final clipped wave');
    finally Analysis.Free; end;
    Writeln('PASS raw-stage versus clipped audible PCM diagnostics');
    Cue.AudioEffects.RemovePair('Out: Use').Free; Cue.AudioEffects.RemovePair('Out: Gain(dB)').Free;
    // Actual copied delay crossing a 4096-sample block boundary.
    Add(Cue,'Dly: Use',1); Add(Cue,'Dly: Time(ms)',1);
    Add(Cue,'Dly: Dry',0); Add(Cue,'Dly: Wet',1); Add(Cue,'Dly: Feedback',0);
    SetLength(Data,8203); FillChar(Data[0],Length(Data)*SizeOf(SmallInt),0); Data[4090] := 16384;
    Analysis := TRigmEffectsAnalysis.Create;
    try
      ApplyCueVoiceEffects(Cue,24000,Data,nil,Analysis);
      for var I := 0 to High(Data) do begin
        if I=4114 then Check(Data[I]=16384,'delay boundary output pulse')
        else Check(Data[I]=0,'delay no unexpected output');
      end;
      Check(Analysis.EffectTotal(0).Applied,'delay applied');
      Check(Analysis.Block(1).Effects[0].OutputPeak=0.5,'delay boundary diagnostics');
      Check(Analysis.EffectTotal(0).ResidualRms>0,'delay residual measured');
    finally Analysis.Free; end;
    Writeln('PASS native copied Delay across block boundary');
    // Cancelled, empty and nonfinite sequence safety.
    Analysis := TRigmEffectsAnalysis.Create;
    try
      SetLength(Data,2); var Rejected := False;
      try ApplyCueVoiceEffects(Cue,24000,Data,function: Boolean begin Result := True; end,Analysis);
      except on E: EAbort do Rejected := True; end;
      Check(Rejected and not Analysis.Ready,'cancelled analysis not published');
    finally Analysis.Free; end;
    Analysis := TRigmEffectsAnalysis.Create;
    try
      Data := nil; ApplyCueVoiceEffects(Cue,24000,Data,nil,Analysis);
      Check(Analysis.Ready and (Analysis.BlockCount=0) and (Analysis.WavePointCount=0),'empty sealed capture');
      Check(Analysis.BlockIndexAt(0)=-1,'empty cursor');
      Near(Analysis.ChainTotal.OutputRms,0,0,'empty RMS');
    finally Analysis.Free; end;
    Writeln('PASS cancellation and empty audio');
  finally Cue.Free; end;
end;
begin
  try Run; RunValidation; RunEquivalence; Writeln('ALL NATIVE EFFECT ANALYSIS PROBES PASSED');
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
