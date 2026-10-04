unit GamepadNavigation;

// Generic input navigation extracted from MmdTimelinePoseControllerDriver:
// edge detection, time scaling and neutral gating after target/connection changes.
interface
uses GamepadState;

type
  TGamepadFrame = record
    State: TGamepadState;
    PressedButtons: Cardinal;
    DirectionChanged: Boolean;
    Factor: Single;
    CanMove: Boolean;
    function Pressed(ButtonNumber: Integer): Boolean;
  end;
  TGamepadNavigation = class
  private
    FPreviousButtons, FPreviousPOV: Cardinal;
    FLastTick: UInt64;
    FAwaitNeutral: Boolean;
  public
    constructor Create;
    procedure Reset;
    procedure AwaitNeutral;
    function Update(const State: TGamepadState; NowTick: UInt64): TGamepadFrame;
  end;

implementation
uses System.Math;

function TGamepadFrame.Pressed(ButtonNumber: Integer): Boolean;
begin
  Result := (ButtonNumber >= 1) and (ButtonNumber <= 32) and
    ((PressedButtons and (Cardinal(1) shl (ButtonNumber - 1))) <> 0);
end;

constructor TGamepadNavigation.Create;
begin inherited; Reset; end;

procedure TGamepadNavigation.Reset;
begin FLastTick := 0; FPreviousButtons := 0; FPreviousPOV := PadPOVNeutral; FAwaitNeutral := True; end;

procedure TGamepadNavigation.AwaitNeutral;
begin FAwaitNeutral := True; end;

function TGamepadNavigation.Update(const State: TGamepadState; NowTick: UInt64): TGamepadFrame;
begin
  Result := Default(TGamepadFrame); Result.State := State;
  Result.PressedButtons := State.Buttons and not FPreviousButtons;
  Result.DirectionChanged := State.POV <> FPreviousPOV;
  if (FLastTick = 0) or (NowTick < FLastTick) then Result.Factor := 1
  else Result.Factor := EnsureRange((NowTick - FLastTick) / 33.0, 0.5, 3.0);
  FLastTick := NowTick;
  if (Abs(State.LeftX) <= 0.005) and (Abs(State.LeftY) <= 0.005) and
    (Abs(State.RightX) <= 0.005) and (Abs(State.RightY) <= 0.005) then FAwaitNeutral := False;
  Result.CanMove := not FAwaitNeutral;
  FPreviousButtons := State.Buttons; FPreviousPOV := State.POV;
end;

end.
