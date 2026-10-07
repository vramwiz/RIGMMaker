unit RigmAul2Adapter;
// Standalone adapter for copied Aul2 DSP. No plugin ABI, shared memory, or host calls.
interface
uses System.JSON, System.Generics.Collections;
type
  TSampleTransfer = procedure(Data: Pointer; Channel: Integer) of object;
  TSCENE_INFO = record SampleRate: Integer; end;
  PSCENE_INFO = ^TSCENE_INFO;
  TOBJECT_INFO = record
    ID,EffectID,SampleIndex: Int64;
    SampleNum,ChannelNum,Frame,FrameS,FrameE,Layer: Integer;
  end;
  POBJECT_INFO = ^TOBJECT_INFO;
  TFILTER_PROC_AUDIO = record
    Scene: PSCENE_INFO; Object_: POBJECT_INFO;
    GetSampleData,SetSampleData: TSampleTransfer;
  end;
  PFILTER_PROC_AUDIO = ^TFILTER_PROC_AUDIO;
  TFILTER_ITEM_GROUP = record Name: PWideChar; end;
  TFILTER_ITEM_CHECK = record Name: PWideChar; Value: Byte; end;
  PFILTER_ITEM_CHECK = ^TFILTER_ITEM_CHECK;
  TFILTER_ITEM_TRACK = record Name: PWideChar; Value: Double; end;
  PFILTER_ITEM_TRACK = ^TFILTER_ITEM_TRACK;
  TFILTER_ITEM_SELECT = record Name: PWideChar; Value: Integer; end;
  PFILTER_ITEM_SELECT = ^TFILTER_ITEM_SELECT;
  TFILTER_ITEM_SELECT_ITEM = record Name: PWideChar; Value: Integer; end;
procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar; DefaultVisible: Integer);
procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar; Value: Integer);
procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar; Value,S,E,Step: Double;
  ZeroDisplay: PWideChar=nil; SliderRatio: Double=1.0);
procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: PWideChar; Value: Integer; List: Pointer);
procedure ClearSelectList;
procedure AddSelectList(var List: array of TFILTER_ITEM_SELECT_ITEM; Name: PWideChar; Value: Integer);
procedure BeginCopiedSettings;
procedure ApplyCopiedSettings(Settings: TJSONObject);
implementation
uses System.SysUtils;
var Checks: TDictionary<string,Pointer>; Tracks: TDictionary<string,Pointer>;
  Selects: TDictionary<string,Pointer>; SelectIndex: Integer;
procedure BeginCopiedSettings;
begin Checks.Clear; Tracks.Clear; Selects.Clear; SelectIndex := 0; end;
procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar; DefaultVisible: Integer);
begin Item.Name := Name; end;
procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar; Value: Integer);
begin Item.Name := Name; Item.Value := Byte(Value<>0); Checks.AddOrSetValue(string(Name),@Item); end;
procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar; Value,S,E,Step: Double;
  ZeroDisplay: PWideChar; SliderRatio: Double);
begin Item.Name := Name; Item.Value := Value; Tracks.AddOrSetValue(string(Name),@Item); end;
procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: PWideChar; Value: Integer; List: Pointer);
begin Item.Name := Name; Item.Value := Value; Selects.AddOrSetValue(string(Name),@Item); end;
procedure ClearSelectList;
begin SelectIndex := 0; end;
procedure AddSelectList(var List: array of TFILTER_ITEM_SELECT_ITEM; Name: PWideChar; Value: Integer);
begin
  if SelectIndex>=High(List) then raise ERangeError.Create('Copied select list capacity');
  List[SelectIndex].Name := Name; List[SelectIndex].Value := Value; Inc(SelectIndex);
  List[SelectIndex].Name := nil; List[SelectIndex].Value := 0;
end;
procedure ApplyCopiedSettings(Settings: TJSONObject);
begin
  for var Pair in Settings do begin
    var K := Pair.JsonString.Value; var N := TJSONNumber(Pair.JsonValue).AsDouble; var P: Pointer;
    if Checks.TryGetValue(K,P) then PFILTER_ITEM_CHECK(P)^.Value := Byte(Round(N))
    else if Tracks.TryGetValue(K,P) then PFILTER_ITEM_TRACK(P)^.Value := N
    else if Selects.TryGetValue(K,P) then PFILTER_ITEM_SELECT(P)^.Value := Round(N)
    else raise Exception.Create('Unsupported copied effect setting: '+K);
  end;
end;
initialization
  Checks := TDictionary<string,Pointer>.Create; Tracks := TDictionary<string,Pointer>.Create;
  Selects := TDictionary<string,Pointer>.Create;
finalization
  Selects.Free; Tracks.Free; Checks.Free;
end.
