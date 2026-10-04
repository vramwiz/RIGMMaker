unit GamepadState;

// Device-independent state extracted from MmdProControllerInput.
interface

const
  PadButtonB = 1; PadButtonA = 2; PadButtonY = 3; PadButtonX = 4;
  PadButtonL = 5; PadButtonR = 6; PadButtonZL = 7; PadButtonZR = 8;
  PadButtonMinus = 9; PadButtonPlus = 10;
  PadButtonLeftStick = 11; PadButtonRightStick = 12;
  PadPOVNeutral = $FFFF;

type
  TGamepadState = record
    LeftX, LeftY, RightX, RightY: Single;
    Buttons: Cardinal;
    POV: Cardinal;
    function Down(ButtonNumber: Integer): Boolean;
    class function Neutral: TGamepadState; static;
  end;

implementation

function TGamepadState.Down(ButtonNumber: Integer): Boolean;
begin
  Result := (ButtonNumber >= 1) and (ButtonNumber <= 32) and
    ((Buttons and (Cardinal(1) shl (ButtonNumber - 1))) <> 0);
end;

class function TGamepadState.Neutral: TGamepadState;
begin
  Result := Default(TGamepadState); Result.POV := PadPOVNeutral;
end;

end.
