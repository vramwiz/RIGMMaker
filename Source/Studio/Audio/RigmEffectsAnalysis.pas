unit RigmEffectsAnalysis;

// Immutable measured diagnostics for one cue. Configuration curves remain separate.
interface

uses System.SysUtils;

const
  RIGM_EFFECT_ANALYSIS_COUNT = 20;
  RIGM_EFFECT_ANALYSIS_BLOCK_SIZE = 4096;
  RIGM_EFFECT_ANALYSIS_MAX_WAVE_POINTS = 2048;

type
  TRigmEffectsMeasure = record
    InputPeak, OutputPeak, InputRms, OutputRms, ResidualRms: Double;
    SampleCount: Int64;
    Applied: Boolean;
  end;

  TRigmEffectsBlock = record
    FirstSample: Int64;
    SampleCount, Rate: Integer;
    Chain: TRigmEffectsMeasure;
    Effects: array[0..RIGM_EFFECT_ANALYSIS_COUNT-1] of TRigmEffectsMeasure;
  end;

  TRigmEffectsWavePoint = record
    FirstSample: Int64;
    SampleCount: Integer;
    InputMin, InputMax, OutputMin, OutputMax: Double;
  end;

  TRigmEffectsAnalysis = class
  private type
    TAccumulator = record
      Count: Int64;
      InputPeak, OutputPeak, InputSquares, OutputSquares, ResidualSquares: Double;
      Applied: Boolean;
    end;
  private
    FStarted, FReady, FOpenBlock: Boolean;
    FRate, FSampleCount, FBlockCount, FCurrentBlock, FCapturedSamples: Integer;
    FEffectMask: Cardinal;
    FBlocks: TArray<TRigmEffectsBlock>;
    FWave: TArray<TRigmEffectsWavePoint>;
    FEffectTotals: array[0..RIGM_EFFECT_ANALYSIS_COUNT-1] of TAccumulator;
    FChainTotal: TAccumulator;
    procedure RequireReady;
    procedure RequireOpenBlock(BlockIndex, Count: Integer);
    procedure ValidateEffectIndex(EffectIndex: Integer);
    function GetWavePointCount: Integer;
    class function FinishMeasure(const Value: TAccumulator): TRigmEffectsMeasure; static;
    class procedure Accumulate(var Target: TAccumulator; const Value: TAccumulator); static;
    class function MeasurePair(const Before, After: TArray<Single>; Count: Integer;
      Applied: Boolean): TAccumulator; static;
  public
    // Capture methods belong only to the worker. After Seal all mutation is rejected.
    procedure BeginCapture(SampleRate, TotalSamples: Integer);
    function BeginBlock(FirstSample: Int64; Count: Integer): Integer;
    procedure CaptureEffect(BlockIndex, EffectIndex: Integer; Applied: Boolean;
      const Before, After: TArray<Single>; Count: Integer);
    procedure CaptureAudibleBlock(BlockIndex: Integer; const Original: TArray<Single>;
      const Audible: TArray<SmallInt>; Offset, Count: Integer);
    procedure Seal;
    function Clone: TRigmEffectsAnalysis;
    function Block(Index: Integer): TRigmEffectsBlock;
    function BlockIndexAt(Seconds: Double): Integer;
    function EffectAt(EffectIndex: Integer; Seconds: Double): TRigmEffectsMeasure;
    function ChainAt(Seconds: Double): TRigmEffectsMeasure;
    function EffectTotal(EffectIndex: Integer): TRigmEffectsMeasure;
    function ChainTotal: TRigmEffectsMeasure;
    function WavePoint(Index: Integer): TRigmEffectsWavePoint;
    property Ready: Boolean read FReady;
    property Rate: Integer read FRate;
    property SampleCount: Integer read FSampleCount;
    property BlockCount: Integer read FBlockCount;
    property WavePointCount: Integer read GetWavePointCount;
  end;

implementation

uses System.Math;

procedure TRigmEffectsAnalysis.RequireReady;
begin
  if not FReady then raise EInvalidOp.Create('Audio diagnostics are not complete');
end;

procedure TRigmEffectsAnalysis.ValidateEffectIndex(EffectIndex: Integer);
begin
  if (EffectIndex<0) or (EffectIndex>=RIGM_EFFECT_ANALYSIS_COUNT) then
    raise EArgumentOutOfRangeException.Create('Invalid audio diagnostic effect index');
end;

procedure TRigmEffectsAnalysis.RequireOpenBlock(BlockIndex, Count: Integer);
begin
  if FReady or not FStarted or not FOpenBlock or (BlockIndex<>FCurrentBlock) or
    (Count<>FBlocks[FCurrentBlock].SampleCount) then
    raise EInvalidOp.Create('Audio diagnostic block is not open');
end;

class function TRigmEffectsAnalysis.FinishMeasure(
  const Value: TAccumulator): TRigmEffectsMeasure;
begin
  Result := Default(TRigmEffectsMeasure);
  Result.SampleCount := Value.Count; Result.Applied := Value.Applied;
  Result.InputPeak := Value.InputPeak; Result.OutputPeak := Value.OutputPeak;
  if Value.Count>0 then begin
    Result.InputRms := Sqrt(Value.InputSquares/Value.Count);
    Result.OutputRms := Sqrt(Value.OutputSquares/Value.Count);
    Result.ResidualRms := Sqrt(Value.ResidualSquares/Value.Count);
  end;
end;

class procedure TRigmEffectsAnalysis.Accumulate(var Target: TAccumulator;
  const Value: TAccumulator);
begin
  Inc(Target.Count,Value.Count);
  Target.InputPeak := Max(Target.InputPeak,Value.InputPeak);
  Target.OutputPeak := Max(Target.OutputPeak,Value.OutputPeak);
  Target.InputSquares := Target.InputSquares+Value.InputSquares;
  Target.OutputSquares := Target.OutputSquares+Value.OutputSquares;
  Target.ResidualSquares := Target.ResidualSquares+Value.ResidualSquares;
  Target.Applied := Target.Applied or Value.Applied;
end;

class function TRigmEffectsAnalysis.MeasurePair(const Before, After: TArray<Single>;
  Count: Integer; Applied: Boolean): TAccumulator;
begin
  if (Count<1) or (Count>Length(Before)) or (Count>Length(After)) then
    raise EArgumentOutOfRangeException.Create('Invalid audio diagnostic sample count');
  Result := Default(TAccumulator); Result.Count := Count; Result.Applied := Applied;
  for var I := 0 to Count-1 do begin
    var A := Double(Before[I]); var B := Double(After[I]);
    if IsNan(A) or IsInfinite(A) or IsNan(B) or IsInfinite(B) then
      raise EInvalidOp.Create('Nonfinite audio diagnostic sample');
    Result.InputPeak := Max(Result.InputPeak,Abs(A));
    Result.OutputPeak := Max(Result.OutputPeak,Abs(B));
    Result.InputSquares := Result.InputSquares+A*A;
    Result.OutputSquares := Result.OutputSquares+B*B;
    Result.ResidualSquares := Result.ResidualSquares+Sqr(B-A);
  end;
end;

procedure TRigmEffectsAnalysis.BeginCapture(SampleRate, TotalSamples: Integer);
begin
  if FStarted or FReady then raise EInvalidOp.Create('Audio diagnostics cannot be reused');
  if (SampleRate<8000) or (SampleRate>192000) or (TotalSamples<0) or
    (Int64(TotalSamples)>Int64(SampleRate)*600) then
    raise EArgumentOutOfRangeException.Create('Invalid audio diagnostic rate or duration');
  FStarted := True; FRate := SampleRate; FSampleCount := TotalSamples;
  FCurrentBlock := -1;
  SetLength(FBlocks,(Int64(TotalSamples)+RIGM_EFFECT_ANALYSIS_BLOCK_SIZE-1) div
    RIGM_EFFECT_ANALYSIS_BLOCK_SIZE);
  var Points := Min(RIGM_EFFECT_ANALYSIS_MAX_WAVE_POINTS,TotalSamples);
  SetLength(FWave,Points);
  for var I := 0 to Points-1 do begin
    FWave[I].FirstSample := Int64(I)*TotalSamples div Points;
    FWave[I].SampleCount := Integer(Int64(I+1)*TotalSamples div Points-FWave[I].FirstSample);
  end;
end;

function TRigmEffectsAnalysis.BeginBlock(FirstSample: Int64; Count: Integer): Integer;
begin
  if FReady or not FStarted or FOpenBlock or (FirstSample<>FCapturedSamples) or
    (Count<>Min(RIGM_EFFECT_ANALYSIS_BLOCK_SIZE,FSampleCount-FCapturedSamples)) or
    (Count<1) or (FBlockCount>=Length(FBlocks)) then
    raise EInvalidOp.Create('Invalid audio diagnostic block sequence');
  Result := FBlockCount; FCurrentBlock := Result; Inc(FBlockCount);
  FBlocks[Result].FirstSample := FirstSample;
  FBlocks[Result].SampleCount := Count; FBlocks[Result].Rate := FRate;
  FEffectMask := 0; FOpenBlock := True;
end;

procedure TRigmEffectsAnalysis.CaptureEffect(BlockIndex, EffectIndex: Integer;
  Applied: Boolean; const Before, After: TArray<Single>; Count: Integer);
begin
  RequireOpenBlock(BlockIndex,Count); ValidateEffectIndex(EffectIndex);
  var Bit := Cardinal(1) shl EffectIndex;
  if (FEffectMask and Bit)<>0 then raise EInvalidOp.Create('Audio diagnostic effect captured twice');
  var Value := MeasurePair(Before,After,Count,Applied);
  FBlocks[BlockIndex].Effects[EffectIndex] := FinishMeasure(Value);
  Accumulate(FEffectTotals[EffectIndex],Value);
  FEffectMask := FEffectMask or Bit;
end;

procedure TRigmEffectsAnalysis.CaptureAudibleBlock(BlockIndex: Integer;
  const Original: TArray<Single>; const Audible: TArray<SmallInt>; Offset, Count: Integer);
begin
  RequireOpenBlock(BlockIndex,Count);
  if (FEffectMask<>((Cardinal(1) shl RIGM_EFFECT_ANALYSIS_COUNT)-1)) or
    (Count>Length(Original)) or (Offset<>FCapturedSamples) or
    (Offset<0) or (Int64(Offset)+Count>Length(Audible)) then
    raise EInvalidOp.Create('Incomplete audible audio diagnostic block');
  var Value := Default(TAccumulator); Value.Count := Count;
  for var EffectIndex := 0 to RIGM_EFFECT_ANALYSIS_COUNT-1 do
    Value.Applied := Value.Applied or FBlocks[BlockIndex].Effects[EffectIndex].Applied;
  for var I := 0 to Count-1 do begin
    var A := Double(Original[I]); var B := Audible[Offset+I]/32768.0;
    if IsNan(A) or IsInfinite(A) then raise EInvalidOp.Create('Nonfinite source audio diagnostic sample');
    Value.InputPeak := Max(Value.InputPeak,Abs(A)); Value.OutputPeak := Max(Value.OutputPeak,Abs(B));
    Value.InputSquares := Value.InputSquares+A*A; Value.OutputSquares := Value.OutputSquares+B*B;
    Value.ResidualSquares := Value.ResidualSquares+Sqr(B-A);
    // Inverse of floor(bin*sampleCount/pointCount); every original sample belongs to one bin.
    var PointIndex := Integer((Int64(Offset+I+1)*Length(FWave)-1) div FSampleCount);
    if Int64(Offset+I)=FWave[PointIndex].FirstSample then begin
      FWave[PointIndex].InputMin := A; FWave[PointIndex].InputMax := A;
      FWave[PointIndex].OutputMin := B; FWave[PointIndex].OutputMax := B;
    end else begin
      FWave[PointIndex].InputMin := Min(FWave[PointIndex].InputMin,A);
      FWave[PointIndex].InputMax := Max(FWave[PointIndex].InputMax,A);
      FWave[PointIndex].OutputMin := Min(FWave[PointIndex].OutputMin,B);
      FWave[PointIndex].OutputMax := Max(FWave[PointIndex].OutputMax,B);
    end;
  end;
  FBlocks[BlockIndex].Chain := FinishMeasure(Value); Accumulate(FChainTotal,Value);
  Inc(FCapturedSamples,Count); FOpenBlock := False;
end;

procedure TRigmEffectsAnalysis.Seal;
begin
  if not FStarted or FReady or FOpenBlock or (FCapturedSamples<>FSampleCount) then
    raise EInvalidOp.Create('Audio diagnostics are incomplete');
  FReady := True;
end;

function TRigmEffectsAnalysis.Clone: TRigmEffectsAnalysis;
begin
  RequireReady; Result := TRigmEffectsAnalysis.Create;
  try
    Result.FStarted := True; Result.FReady := True;
    Result.FRate := FRate; Result.FSampleCount := FSampleCount;
    Result.FBlockCount := FBlockCount; Result.FCurrentBlock := -1;
    Result.FCapturedSamples := FCapturedSamples;
    Result.FBlocks := Copy(FBlocks); Result.FWave := Copy(FWave);
    Result.FEffectTotals := FEffectTotals; Result.FChainTotal := FChainTotal;
  except Result.Free; raise; end;
end;

function TRigmEffectsAnalysis.Block(Index: Integer): TRigmEffectsBlock;
begin
  RequireReady;
  if (Index<0) or (Index>=FBlockCount) then
    raise EArgumentOutOfRangeException.Create('Invalid audio diagnostic block index');
  Result := FBlocks[Index];
end;

function TRigmEffectsAnalysis.BlockIndexAt(Seconds: Double): Integer;
begin
  RequireReady;
  if IsNan(Seconds) or IsInfinite(Seconds) then
    raise EArgumentOutOfRangeException.Create('Nonfinite audio diagnostic cursor');
  if FBlockCount=0 then Exit(-1);
  if Seconds<=0 then Exit(0);
  if Seconds>=FSampleCount/FRate then Exit(FBlockCount-1);
  Result := Integer(Floor(Seconds*FRate) div RIGM_EFFECT_ANALYSIS_BLOCK_SIZE);
end;

function TRigmEffectsAnalysis.EffectAt(EffectIndex: Integer;
  Seconds: Double): TRigmEffectsMeasure;
begin
  ValidateEffectIndex(EffectIndex); var Index := BlockIndexAt(Seconds);
  if Index<0 then Exit(Default(TRigmEffectsMeasure));
  Result := FBlocks[Index].Effects[EffectIndex];
end;

function TRigmEffectsAnalysis.ChainAt(Seconds: Double): TRigmEffectsMeasure;
begin
  var Index := BlockIndexAt(Seconds);
  if Index<0 then Exit(Default(TRigmEffectsMeasure));
  Result := FBlocks[Index].Chain;
end;

function TRigmEffectsAnalysis.EffectTotal(EffectIndex: Integer): TRigmEffectsMeasure;
begin RequireReady; ValidateEffectIndex(EffectIndex); Result := FinishMeasure(FEffectTotals[EffectIndex]); end;

function TRigmEffectsAnalysis.ChainTotal: TRigmEffectsMeasure;
begin RequireReady; Result := FinishMeasure(FChainTotal); end;

function TRigmEffectsAnalysis.GetWavePointCount: Integer;
begin Result := Length(FWave); end;

function TRigmEffectsAnalysis.WavePoint(Index: Integer): TRigmEffectsWavePoint;
begin
  RequireReady;
  if (Index<0) or (Index>=Length(FWave)) then
    raise EArgumentOutOfRangeException.Create('Invalid audio diagnostic waveform index');
  Result := FWave[Index];
end;

end.
