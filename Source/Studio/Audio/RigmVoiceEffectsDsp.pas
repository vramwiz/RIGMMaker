unit RigmVoiceEffectsDsp;
// Copied Aul2 DSP retains its original order. Lock and reset isolate every cue/worker.
interface
uses System.SysUtils, RigmMovieModel, RigmEffectsAnalysis;
procedure ApplyCueVoiceEffects(Cue: TRigmMovieCue; SampleRate: Integer; var Samples: TArray<SmallInt>; Cancel: TFunc<Boolean>=nil; Analysis: TRigmEffectsAnalysis=nil);
implementation
uses System.Math, RigmVoiceEffectSettings, RigmAul2Adapter, RigmAul2Delay, RigmAul2Eq, RigmAul2Compressor, RigmAul2VoiceDrive, RigmAul2Distortion, RigmAul2Noise, RigmAul2BitCrusher, RigmAul2Tremble, RigmAul2Wobble, RigmAul2Pitch, RigmAul2RingMod, RigmAul2Muffle, RigmAul2Whisper, RigmAul2AutoGain, RigmAul2NoiseGate, RigmAul2Ghost, RigmAul2Chorus, RigmAul2Reverb, RigmAul2Output, RigmAul2Limiter;
type
  TProcessAudio = function(Audio: PFILTER_PROC_AUDIO; SampleNum, ChannelNum: Integer): Boolean;
  TOfflineSamples = class
  public
    Data: TArray<Single>; Count: Integer;
    procedure ReadSamples(Dest: Pointer; Channel: Integer);
    procedure WriteSamples(Source: Pointer; Channel: Integer);
  end;
var EffectLock: TObject;
procedure TOfflineSamples.ReadSamples(Dest: Pointer; Channel: Integer);
begin if Channel<>0 then raise Exception.Create('Standalone cue effects are mono'); Move(Data[0],Dest^,Count*SizeOf(Single)); end;
procedure TOfflineSamples.WriteSamples(Source: Pointer; Channel: Integer);
begin if Channel<>0 then raise Exception.Create('Standalone cue effects are mono'); Move(Source^,Data[0],Count*SizeOf(Single)); end;
procedure ResetCopiedChain;
begin
  ResetCopiedDelay;
  ResetCopiedEq;
  ResetCopiedCompressor;
  ResetCopiedVoiceDrive;
  ResetCopiedDistortion;
  ResetCopiedNoise;
  ResetCopiedBitCrusher;
  ResetCopiedTremble;
  ResetCopiedWobble;
  ResetCopiedPitch;
  ResetCopiedRingMod;
  ResetCopiedMuffle;
  ResetCopiedWhisper;
  ResetCopiedAutoGain;
  ResetCopiedNoiseGate;
  ResetCopiedGhost;
  ResetCopiedChorus;
  ResetCopiedReverb;
  ResetCopiedOutput;
  ResetCopiedLimiter;
end;
procedure ApplyCueVoiceEffects(Cue: TRigmMovieCue; SampleRate: Integer; var Samples: TArray<SmallInt>; Cancel: TFunc<Boolean>; Analysis: TRigmEffectsAnalysis);
var Buffer: TOfflineSamples; A: TFILTER_PROC_AUDIO;
  BeforeEffect, Original: TArray<Single>; BlockIndex: Integer;
  procedure ProcessMeasured(Process: TProcessAudio; EffectIndex: Integer);
  begin
    Move(Buffer.Data[0],BeforeEffect[0],Buffer.Count*SizeOf(Single));
    var Applied := Process(@A,Buffer.Count,1);
    Analysis.CaptureEffect(BlockIndex,EffectIndex,Applied,BeforeEffect,Buffer.Data,Buffer.Count);
  end;
begin
  ValidateVoiceEffectSettings(Cue.AudioEffects);
  if (Analysis=nil) and (not VoiceEffectsEnabled(Cue.AudioEffects) or (Length(Samples)=0)) then Exit;
  if (SampleRate<8000) or (SampleRate>192000) or (Length(Samples)>Int64(SampleRate)*600) then raise Exception.Create('Invalid cue PCM duration or sample rate');
  if Analysis<>nil then Analysis.BeginCapture(SampleRate,Length(Samples));
  if Length(Samples)=0 then begin if Analysis<>nil then Analysis.Seal; Exit; end;
  // Detach from immutable shared mix buffers before mutation.
  Samples := Copy(Samples); Buffer := TOfflineSamples.Create;
  try
    if Analysis<>nil then begin SetLength(BeforeEffect,4096); SetLength(Original,4096); end;
    TMonitor.Enter(EffectLock);
    try
    ResetCopiedChain; BeginCopiedSettings;
    AddDelayItems;
    AddEqItems;
    AddCompressorItems;
    AddVoiceDriveItems;
    AddDistortionItems;
    AddNoiseItems;
    AddBitCrusherItems;
    AddTrembleItems;
    AddWobbleItems;
    AddPitchItems;
    AddRingModItems;
    AddMuffleItems;
    AddWhisperItems;
    AddAutoGainItems;
    AddNoiseGateItems;
    AddGhostItems;
    AddChorusItems;
    AddReverbItems;
    AddOutputItems;
    AddLimiterItems;
    ApplyCopiedSettings(Cue.AudioEffects);
    var S: TSCENE_INFO; S.SampleRate := SampleRate;
    var O := Default(TOBJECT_INFO); O.ID := 1; O.EffectID := 1; O.ChannelNum := 1;
    A.Scene := @S; A.Object_ := @O;
    A.GetSampleData := Buffer.ReadSamples; A.SetSampleData := Buffer.WriteSamples;
    SetLength(Buffer.Data,4096); var Position := 0;
    while Position<Length(Samples) do begin
      if Assigned(Cancel) and Cancel() then raise EAbort.Create('Audio effects cancelled');
      Buffer.Count := Min(4096,Length(Samples)-Position); O.SampleNum := Buffer.Count; O.SampleIndex := Position;
      for var I := 0 to Buffer.Count-1 do Buffer.Data[I] := Samples[Position+I]/32768.0;
      if Analysis<>nil then begin
        Move(Buffer.Data[0],Original[0],Buffer.Count*SizeOf(Single));
        BlockIndex := Analysis.BeginBlock(Position,Buffer.Count);
      end;
      if Analysis=nil then begin
        ProcessDelay(@A,Buffer.Count,1);
        ProcessEq(@A,Buffer.Count,1);
        ProcessCompressor(@A,Buffer.Count,1);
        ProcessVoiceDrive(@A,Buffer.Count,1);
        ProcessDistortion(@A,Buffer.Count,1);
        ProcessNoise(@A,Buffer.Count,1);
        ProcessBitCrusher(@A,Buffer.Count,1);
        ProcessTremble(@A,Buffer.Count,1);
        ProcessWobble(@A,Buffer.Count,1);
        ProcessPitch(@A,Buffer.Count,1);
        ProcessRingMod(@A,Buffer.Count,1);
        ProcessMuffle(@A,Buffer.Count,1);
        ProcessWhisper(@A,Buffer.Count,1);
        ProcessAutoGain(@A,Buffer.Count,1);
        ProcessNoiseGate(@A,Buffer.Count,1);
        ProcessGhost(@A,Buffer.Count,1);
        ProcessChorus(@A,Buffer.Count,1);
        ProcessReverb(@A,Buffer.Count,1);
        ProcessOutput(@A,Buffer.Count,1);
        ProcessLimiter(@A,Buffer.Count,1);
      end else begin
        ProcessMeasured(ProcessDelay,0);
        ProcessMeasured(ProcessEq,1);
        ProcessMeasured(ProcessCompressor,2);
        ProcessMeasured(ProcessVoiceDrive,3);
        ProcessMeasured(ProcessDistortion,4);
        ProcessMeasured(ProcessNoise,5);
        ProcessMeasured(ProcessBitCrusher,6);
        ProcessMeasured(ProcessTremble,7);
        ProcessMeasured(ProcessWobble,8);
        ProcessMeasured(ProcessPitch,9);
        ProcessMeasured(ProcessRingMod,10);
        ProcessMeasured(ProcessMuffle,11);
        ProcessMeasured(ProcessWhisper,12);
        ProcessMeasured(ProcessAutoGain,13);
        ProcessMeasured(ProcessNoiseGate,14);
        ProcessMeasured(ProcessGhost,15);
        ProcessMeasured(ProcessChorus,16);
        ProcessMeasured(ProcessReverb,17);
        ProcessMeasured(ProcessOutput,18);
        ProcessMeasured(ProcessLimiter,19);
      end;
      for var I := 0 to Buffer.Count-1 do begin
        var V := Buffer.Data[I]; if IsNan(V) or IsInfinite(V) then raise Exception.Create('Nonfinite processed sample');
        Samples[Position+I] := EnsureRange(Round(EnsureRange(Double(V),-1.0,32767.0/32768.0)*32768.0),-32768,32767);
      end;
      if Analysis<>nil then Analysis.CaptureAudibleBlock(BlockIndex,Original,Samples,Position,Buffer.Count);
      Inc(Position,Buffer.Count);
    end;
    if Analysis<>nil then Analysis.Seal;
    finally ResetCopiedChain; TMonitor.Exit(EffectLock); end;
  finally
    Buffer.Free;
  end;
end;
initialization
  EffectLock := TObject.Create;
finalization
  EffectLock.Free;
end.
