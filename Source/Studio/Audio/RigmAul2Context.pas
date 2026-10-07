unit RigmAul2Context;

// 音声処理中の Object_.ID + EffectID ごとに、状態持ちエフェクトの Context を分離する。

interface

uses
  System.Generics.Collections,
  RigmAul2Adapter;

type
  TAul2AudioFilterContextItem = class
  private
    FObjectID: Int64;
    FEffectID: Int64;
  public
    property ObjectID: Int64 read FObjectID;
    property EffectID: Int64 read FEffectID;
  end;

  TAul2AudioFilterContextList<T: TAul2AudioFilterContextItem, constructor> = class(TObjectList<T>)
  private
    function FindByKey(ObjectID, EffectID: Int64): T;
  public
    constructor Create;
    function GetContext(Audio: PFILTER_PROC_AUDIO): T;
  end;

implementation

{ TAul2AudioFilterContextList<T> }

constructor TAul2AudioFilterContextList<T>.Create;
begin
  inherited Create(True);
end;

function TAul2AudioFilterContextList<T>.FindByKey(ObjectID, EffectID: Int64): T;
var
  Item: T;
begin
  Result := nil;
  for Item in Self do
    if (Item.ObjectID = ObjectID) and (Item.EffectID = EffectID) then
      Exit(Item);
end;

function TAul2AudioFilterContextList<T>.GetContext(Audio: PFILTER_PROC_AUDIO): T;
var
  ObjectID: Int64;
  EffectID: Int64;
begin
  ObjectID := 0;
  EffectID := 0;
  if (Audio <> nil) and (Audio^.Object_ <> nil) then
  begin
    ObjectID := Audio^.Object_^.ID;
    EffectID := Audio^.Object_^.EffectID;
  end;

  Result := FindByKey(ObjectID, EffectID);
  if Result <> nil then
    Exit;

  Result := T.Create;
  Result.FObjectID := ObjectID;
  Result.FEffectID := EffectID;
  Add(Result);
end;

end.
