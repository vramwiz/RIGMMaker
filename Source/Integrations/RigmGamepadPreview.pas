unit RigmGamepadPreview;

interface
uses System.Generics.Collections, GamepadState, GamepadNavigation, RigmModel;

type
  TRigmGamepadTarget = (gtEyes, gtMouth, gtHead, gtBody);
  TRigmGamepadPreview = class
  private
    FNavigation: TGamepadNavigation;
    FBefore: TDictionary<string, Double>;
    FTarget: TRigmGamepadTarget;
    FPending: Boolean;
    FWasBlink, FWasMouth: Boolean;
    FEyeBefore, FMouthBefore: Double;
    procedure SetTarget(Value: TRigmGamepadTarget);
    procedure BeginSession(Pose: TRigmPose);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ResetInput;
    function Release(Pose: TRigmPose): Boolean;
    function Apply(const State: TGamepadState; NowTick: UInt64;
      Document: TRigmDocument; Pose: TRigmPose): Boolean;
    property Target: TRigmGamepadTarget read FTarget write SetTarget;
    property Pending: Boolean read FPending;
  end;

function GamepadTargetName(Target: TRigmGamepadTarget): string;

implementation
uses System.Math, System.SysUtils;

function GamepadTargetName(Target: TRigmGamepadTarget): string;
begin
  case Target of gtEyes: Result := '目'; gtMouth: Result := '口'; gtHead: Result := '頭'; gtBody: Result := '上半身'; end;
end;

constructor TRigmGamepadPreview.Create;
begin
  inherited; FNavigation := TGamepadNavigation.Create;
  FBefore := TDictionary<string, Double>.Create; FTarget := gtEyes;
end;

destructor TRigmGamepadPreview.Destroy;
begin FBefore.Free; FNavigation.Free; inherited; end;

procedure TRigmGamepadPreview.ResetInput;
begin FNavigation.Reset; FPending := False; FBefore.Clear; end;

function TRigmGamepadPreview.Release(Pose: TRigmPose): Boolean;
begin
  Result := FWasBlink or FWasMouth;
  if FWasBlink then Pose.Values.AddOrSetValue('eyeOpen', FEyeBefore);
  if FWasMouth then Pose.Values.AddOrSetValue('mouthOpen', FMouthBefore);
  FWasBlink := False; FWasMouth := False; ResetInput;
end;

procedure TRigmGamepadPreview.SetTarget(Value: TRigmGamepadTarget);
begin
  if FTarget = Value then Exit;
  FTarget := Value; FPending := False; FBefore.Clear; FNavigation.AwaitNeutral;
end;

procedure TRigmGamepadPreview.BeginSession(Pose: TRigmPose);
begin
  if FPending then Exit;
  FBefore.Clear; for var Pair in Pose.Values do FBefore.Add(Pair.Key, Pair.Value);
  FPending := True;
end;

function TRigmGamepadPreview.Apply(const State: TGamepadState; NowTick: UInt64;
  Document: TRigmDocument; Pose: TRigmPose): Boolean;
var Frame: TGamepadFrame; Rate: Double;
  function Initial(const Id: string): Double;
  begin
    Result := 0; for var Parameter in Document.Parameters do if Parameter.Id = Id then Exit(Parameter.Initial);
  end;
  procedure SetValue(const Id: string; Value: Double);
  begin
    for var Parameter in Document.Parameters do if Parameter.Id = Id then begin
      Value := EnsureRange(Value, Parameter.Minimum, Parameter.Maximum);
      if SameValue(Pose.Value(Id, Parameter.Initial), Value) then Exit;
      BeginSession(Pose); Pose.Values.AddOrSetValue(Id, Value); Result := True; Exit;
    end;
  end;
begin
  Result := False; Frame := FNavigation.Update(State, NowTick);
  if Frame.DirectionChanged and ((State.POV = 0) or (State.POV = 18000)) then begin
    if State.POV = 0 then Target := TRigmGamepadTarget((Ord(Target) + 3) mod 4)
    else Target := TRigmGamepadTarget((Ord(Target) + 1) mod 4);
    Exit;
  end;
  if Frame.Pressed(PadButtonB) then begin
    if FPending then begin
      Pose.Values.Clear; for var Pair in FBefore do Pose.Values.Add(Pair.Key, Pair.Value); Result := True;
    end;
    FWasBlink := False; FWasMouth := False;
    FPending := False; FBefore.Clear; FNavigation.AwaitNeutral; Exit;
  end;
  if Frame.Pressed(PadButtonA) then begin
    FPending := False; FBefore.Clear; FNavigation.AwaitNeutral; Exit;
  end;
  if Frame.Pressed(PadButtonY) then begin
    case Target of
      gtEyes: begin SetValue('gazeX', Initial('gazeX')); SetValue('gazeY', Initial('gazeY')); SetValue('eyeOpen', Initial('eyeOpen')); end;
      gtMouth: SetValue('mouthOpen', Initial('mouthOpen'));
      gtHead: SetValue('headAngle', Initial('headAngle'));
      gtBody: SetValue('bodyAngle', Initial('bodyAngle'));
    end;
    FPending := False; FBefore.Clear; FNavigation.AwaitNeutral; Exit;
  end;
  // Right stick and expression buttons can be used together with the selected target.
  if State.Down(PadButtonZR) then begin
    if not FWasBlink then FEyeBefore := Pose.Value('eyeOpen', Initial('eyeOpen'));
    SetValue('eyeOpen', 0); FWasBlink := True;
  end else if FWasBlink then begin SetValue('eyeOpen', FEyeBefore); FWasBlink := False; end;
  if State.Down(PadButtonZL) then begin
    if not FWasMouth then FMouthBefore := Pose.Value('mouthOpen', Initial('mouthOpen'));
    SetValue('mouthOpen', 1); FWasMouth := True;
  end else if FWasMouth then begin SetValue('mouthOpen', FMouthBefore); FWasMouth := False; end;
  if not Frame.CanMove then Exit;
  Rate := 0.10 * Frame.Factor; if State.Down(PadButtonL) then Rate := Rate * 0.2;
  case Target of
    gtEyes: begin
      SetValue('gazeX', Pose.Value('gazeX', Initial('gazeX')) + State.LeftX * Rate);
      SetValue('gazeY', Pose.Value('gazeY', Initial('gazeY')) - State.LeftY * Rate);
    end;
    gtMouth: if Abs(State.LeftY) > 0.005 then SetValue('mouthOpen', Pose.Value('mouthOpen', Initial('mouthOpen')) + State.LeftY * Rate);
    gtHead: SetValue('headAngle', Pose.Value('headAngle', Initial('headAngle')) + State.LeftX * Rate * 20);
    gtBody: SetValue('bodyAngle', Pose.Value('bodyAngle', Initial('bodyAngle')) + State.LeftX * Rate * 15);
  end;
  if State.Down(PadButtonR) then SetValue('bodyAngle', Pose.Value('bodyAngle', Initial('bodyAngle')) + State.RightX * Rate * 15)
  else SetValue('headAngle', Pose.Value('headAngle', Initial('headAngle')) + State.RightX * Rate * 20);
end;

end.
