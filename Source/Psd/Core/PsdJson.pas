unit PsdJson;

// PSD系統だけで使うJSON検証。旧RIGMのモデルや編集状態には依存しない。
interface
uses System.SysUtils, System.JSON;

function S(O: TJSONObject; const Key: string; const Default: string = ''): string;
function N(O: TJSONObject; const Key: string; Default: Double = 0): Double;
function I(O: TJSONObject; const Key: string; Default: Integer = 0): Integer;
function B(O: TJSONObject; const Key: string; Default: Boolean = False): Boolean;
function Obj(O: TJSONObject; const Key: string): TJSONObject;
function Arr(O: TJSONObject; const Key: string): TJSONArray;
function Parse(const Text: string): TJSONValue;
function ObjectText(const Text: string): TJSONObject;
procedure Put(O: TJSONObject; const Key: string; Value: TJSONValue); overload;
procedure Put(O: TJSONObject; const Key, Value: string); overload;
function NewId: string;

implementation
uses System.Math, System.Generics.Collections;

function S(O: TJSONObject; const Key, Default: string): string;
begin
  var V := O.GetValue(Key); if V = nil then Exit(Default);
  if not (V is TJSONString) then raise Exception.Create('String required: ' + Key);
  Result := V.Value;
end;
function N(O: TJSONObject; const Key: string; Default: Double): Double;
begin
  var V := O.GetValue(Key); if V = nil then Exit(Default);
  if not (V is TJSONNumber) or not TryStrToFloat(V.Value, Result, TFormatSettings.Invariant) or
    IsNan(Result) or IsInfinite(Result) then raise Exception.Create('Finite number required: ' + Key);
end;
function I(O: TJSONObject; const Key: string; Default: Integer): Integer;
begin
  var V := N(O, Key, Default);
  if (V < Low(Integer)) or (V > High(Integer)) or (Frac(V) <> 0) then raise Exception.Create('Integer required: ' + Key);
  Result := Trunc(V);
end;
function B(O: TJSONObject; const Key: string; Default: Boolean): Boolean;
begin
  var V := O.GetValue(Key); if V = nil then Exit(Default);
  if not (V is TJSONBool) then raise Exception.Create('Boolean required: ' + Key);
  Result := TJSONBool(V).AsBoolean;
end;
function Obj(O: TJSONObject; const Key: string): TJSONObject;
begin
  if not (O.GetValue(Key) is TJSONObject) then raise Exception.Create('Object required: ' + Key);
  Result := TJSONObject(O.GetValue(Key));
end;
function Arr(O: TJSONObject; const Key: string): TJSONArray;
begin
  if not (O.GetValue(Key) is TJSONArray) then raise Exception.Create('Array required: ' + Key);
  Result := TJSONArray(O.GetValue(Key));
end;
procedure Validate(V: TJSONValue; Depth: Integer);
begin
  if Depth > 40 then raise Exception.Create('JSON nesting limit');
  if V is TJSONObject then begin
    var Seen := TDictionary<string, Boolean>.Create;
    try
      for var P in TJSONObject(V) do begin
        if Seen.ContainsKey(P.JsonString.Value) then raise Exception.Create('Duplicate JSON key');
        Seen.Add(P.JsonString.Value, True); Validate(P.JsonValue, Depth + 1);
      end;
    finally Seen.Free; end;
  end else if V is TJSONArray then for var Item in TJSONArray(V) do Validate(Item, Depth + 1);
end;
function Parse(const Text: string): TJSONValue;
begin
  if Length(Text) > 8 * 1024 * 1024 then raise Exception.Create('JSON size limit');
  Result := TJSONObject.ParseJSONValue(Text);
  try
    if Result = nil then raise Exception.Create('Invalid JSON');
    Validate(Result, 0);
  except Result.Free; raise; end;
end;
function ObjectText(const Text: string): TJSONObject;
begin
  var V := Parse(Text);
  if not (V is TJSONObject) then begin V.Free; raise Exception.Create('Object required'); end;
  Result := TJSONObject(V);
end;
procedure Put(O: TJSONObject; const Key: string; Value: TJSONValue);
begin O.RemovePair(Key).Free; O.AddPair(Key, Value); end;
procedure Put(O: TJSONObject; const Key, Value: string);
begin Put(O, Key, TJSONString.Create(Value)); end;
function NewId: string;
begin var G: TGUID; CreateGUID(G); Result := GUIDToString(G); end;
end.
