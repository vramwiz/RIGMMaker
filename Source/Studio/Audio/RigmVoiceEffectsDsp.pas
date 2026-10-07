unit RigmVoiceEffectsDsp;
// Copied Aul2 DSP retains its original order. Lock and reset isolate every cue/worker.
interface
uses System.SysUtils, RigmMovieModel;
procedure ApplyCueVoiceEffects(Cue: TRigmMovieCue; SampleRate: Integer; var Samples: TArray<SmallInt>; Cancel: TFunc<Boolean>=nil);
implementation
uses System.Math, RigmVoiceEffectSettings, RigmAul2Adapter, RigmAul2Delay, RigmAul2Eq, RigmAul2Compressor, RigmAul2VoiceDrive, RigmAul2Distortion, RigmAul2Noise, RigmAul2BitCrusher, RigmAul2Tremble, RigmAul2Wobble, RigmAul2Pitch, RigmAul2RingMod, RigmAul2Muffle, RigmAul2Whisper, RigmAul2AutoGain, RigmAul2NoiseGate, RigmAul2Ghost, RigmAul2Chorus, RigmAul2Reverb, RigmAul2Output, RigmAul2Limiter;
type
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
procedure ApplyCueVoiceEffects(Cue: TRigmMovieCue; SampleRate: Integer; var Samples: TArray<SmallInt>; Cancel: TFunc<Boolean>);
begin
  ValidateVoiceEffectSettings(Cue.AudioEffects);
  if not VoiceEffectsEnabled(Cue.AudioEffects) or (Length(Samples)=0) then Exit;
  if (SampleRate<8000) or (SampleRate>192000) or (Length(Samples)>Int64(SampleRate)*600) then raise Exception.Create('Invalid cue PCM duration or sample rate');
  // Detach from immutable shared mix buffers before mutation.
  Samples := Copy(Samples); var Buffer := TOfflineSamples.Create;
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
    var A: TFILTER_PROC_AUDIO; A.Scene := @S; A.Object_ := @O;
    A.GetSampleData := Buffer.ReadSamples; A.SetSampleData := Buffer.WriteSamples;
    SetLength(Buffer.Data,4096); var Position := 0;
    while Position<Length(Samples) do begin
      if Assigned(Cancel) and Cancel() then raise EAbort.Create('Audio effects cancelled');
      Buffer.Count := Min(4096,Length(Samples)-Position); O.SampleNum := Buffer.Count; O.SampleIndex := Position;
      for var I := 0 to Buffer.Count-1 do Buffer.Data[I] := Samples[Position+I]/32768.0;
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
      for var I := 0 to Buffer.Count-1 do begin
        var V := Buffer.Data[I]; if IsNan(V) or IsInfinite(V) then raise Exception.Create('Nonfinite processed sample');
        Samples[Position+I] := EnsureRange(Round(EnsureRange(Double(V),-1.0,32767.0/32768.0)*32768.0),-32768,32767);
      end;
      Inc(Position,Buffer.Count);
    end;
  finally
    ResetCopiedChain; TMonitor.Exit(EffectLock); Buffer.Free;
  end;
end;
initialization
  EffectLock := TObject.Create;
finalization
  EffectLock.Free;
end.
