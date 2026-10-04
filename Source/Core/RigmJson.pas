unit RigmJson;

interface
uses System.SysUtils, System.JSON, RigmModel;

function JS(O: TJSONObject; const Key: string; const Default: string = ''): string;
function JN(O: TJSONObject; const Key: string; Default: Double = 0): Double;
function JI(O: TJSONObject; const Key: string; Default: Integer = 0): Integer;
function JB(O: TJSONObject; const Key: string; Default: Boolean = False): Boolean;
function JO(O: TJSONObject; const Key: string): TJSONObject;
function JA(O: TJSONObject; const Key: string): TJSONArray;
function ParseObject(const Text: string): TJSONObject;
procedure AddN(O: TJSONObject; const Key: string; Value: Double);
procedure AddB(O: TJSONObject; const Key: string; Value: Boolean);
procedure ValidateJson(Value: TJSONValue; Depth: Integer = 0);

implementation
uses System.Math, System.Generics.Collections;

function JS(O: TJSONObject; const Key, Default: string): string;
var V: TJSONValue;
begin
  V := O.GetValue(Key); if V = nil then Exit(Default);
  if not (V is TJSONString) then raise ERigm.Create('文字列が必要です: ' + Key);
  Result := V.Value;
end;

function JN(O: TJSONObject; const Key: string; Default: Double): Double;
var V: TJSONValue;
begin
  V := O.GetValue(Key); if V = nil then Exit(Default);
  if not (V is TJSONNumber) or not TryStrToFloat(V.Value, Result, TFormatSettings.Invariant) or not Finite(Result) then
    raise ERigm.Create('有限の数値が必要です: ' + Key);
end;

function JI(O: TJSONObject; const Key: string; Default: Integer): Integer;
var Value: Double;
begin
  Value := JN(O, Key, Default);
  if (Value < Low(Integer)) or (Value > High(Integer)) or (Frac(Value) <> 0) then
    raise ERigm.Create('整数が必要です: ' + Key);
  Result := Trunc(Value);
end;

function JB(O: TJSONObject; const Key: string; Default: Boolean): Boolean;
var V: TJSONValue;
begin
  V := O.GetValue(Key); if V = nil then Exit(Default);
  if not (V is TJSONBool) then raise ERigm.Create('真偽値が必要です: ' + Key);
  Result := TJSONBool(V).AsBoolean;
end;

function JO(O: TJSONObject; const Key: string): TJSONObject;
begin
  if not (O.GetValue(Key) is TJSONObject) then raise ERigm.Create('オブジェクトが必要です: ' + Key);
  Result := TJSONObject(O.GetValue(Key));
end;

function JA(O: TJSONObject; const Key: string): TJSONArray;
begin
  if not (O.GetValue(Key) is TJSONArray) then raise ERigm.Create('配列が必要です: ' + Key);
  Result := TJSONArray(O.GetValue(Key));
end;

procedure ValidateJson(Value: TJSONValue; Depth: Integer);
var Seen: TDictionary<string, Boolean>; Pair: TJSONPair; Item: TJSONValue;
begin
  if Depth > 70 then raise ERigm.Create('JSON階層上限です。');
  if Value is TJSONObject then begin
    Seen := TDictionary<string, Boolean>.Create;
    try
      for Pair in TJSONObject(Value) do begin
        if Seen.ContainsKey(Pair.JsonString.Value) then raise ERigm.Create('重複したJSON項目です。');
        Seen.Add(Pair.JsonString.Value, True); ValidateJson(Pair.JsonValue, Depth + 1);
      end;
    finally Seen.Free; end;
  end else if Value is TJSONArray then for Item in TJSONArray(Value) do ValidateJson(Item, Depth + 1);
end;

function ParseObject(const Text: string): TJSONObject;
var V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(Text);
  try
    if not (V is TJSONObject) then raise ERigm.Create('JSONオブジェクトが必要です。');
    ValidateJson(V); Result := TJSONObject(V); V := nil;
  finally V.Free; end;
end;

procedure AddN(O: TJSONObject; const Key: string; Value: Double);
begin
  if (Abs(Value) < 9.0E18) and (Frac(Value) = 0) then O.AddPair(Key, TJSONNumber.Create(Trunc(Value)))
  else O.AddPair(Key, TJSONNumber.Create(Value));
end;

procedure AddB(O: TJSONObject; const Key: string; Value: Boolean);
begin O.AddPair(Key, TJSONBool.Create(Value)); end;

end.
