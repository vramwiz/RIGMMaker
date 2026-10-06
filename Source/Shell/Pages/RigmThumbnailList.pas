unit RigmThumbnailList;
interface
uses System.Classes, System.JSON, System.Generics.Collections, Vcl.Controls, Vcl.ComCtrls,
  Vcl.ExtCtrls, RigmThumbnailCache;
type
  TRigmThumbnailPathEvent = function(Item: TListItem): string of object;
  TRigmThumbnailAppliedEvent = procedure(Sender: TObject; Item: TListItem; Metadata: TJSONObject) of object;
  TRigmThumbnailList = class(TComponent)
  private
    FCache: TRigmThumbnailCache; FList: TListView; FImages: TImageList;
    FTimer: TTimer; FApplied: TDictionary<string,string>;
    FOnPath: TRigmThumbnailPathEvent; FOnApplied: TRigmThumbnailAppliedEvent;
    procedure Tick(Sender: TObject);
  public
    constructor CreateForList(AOwner: TComponent; Cache: TRigmThumbnailCache; List: TListView; Images: TImageList);
    destructor Destroy; override;
    procedure Reset;
    procedure Refresh;
    procedure Pause;
    property OnPath: TRigmThumbnailPathEvent read FOnPath write FOnPath;
    property OnApplied: TRigmThumbnailAppliedEvent read FOnApplied write FOnApplied;
    function Idle: Boolean;
  end;
implementation
uses System.SysUtils, Vcl.Graphics, RigmCharacterCatalog;
constructor TRigmThumbnailList.CreateForList(AOwner: TComponent; Cache: TRigmThumbnailCache; List: TListView; Images: TImageList);
begin
  inherited Create(AOwner); FCache := Cache; FList := List; FImages := Images;
  FApplied := TDictionary<string,string>.Create;
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 80; FTimer.OnTimer := Tick;
end;
destructor TRigmThumbnailList.Destroy;
begin FTimer.Enabled := False; FApplied.Free; inherited; end;
procedure TRigmThumbnailList.Reset;
begin FTimer.Enabled := False; FApplied.Clear; FImages.Clear; end;
procedure TRigmThumbnailList.Pause;
begin FTimer.Enabled := False; end;
procedure TRigmThumbnailList.Refresh;
begin FTimer.Enabled := True; Tick(Self); end;
function TRigmThumbnailList.Idle: Boolean;
begin Result := not FTimer.Enabled; end;
procedure TRigmThumbnailList.Tick(Sender: TObject);
begin
  if not Assigned(FOnPath) then begin FTimer.Enabled := False; Exit; end;
  var Loading := False;
  for var Item in FList.Items do begin
    var Path := FOnPath(Item); var Previous: string;
    try
      var Entry := FCache.Request(Path);
      if Entry=nil then begin
        Loading := True;
        if not FApplied.TryGetValue(Path,Previous) or (Previous<>'loading') then begin
          var Metadata := TJSONObject.Create;
          try
            Metadata.AddPair('readyForScript',TJSONBool.Create(False)); Metadata.AddPair('loading',TJSONBool.Create(True));
            Metadata.AddPair('productionState','準備中'); Metadata.AddPair('productionReason','サムネイルと完成状態を準備中です。');
            if Assigned(FOnApplied) then FOnApplied(Self,Item,Metadata);
          finally Metadata.Free; end;
          FApplied.AddOrSetValue(Path,'loading');
        end;
        Continue;
      end;
      var Stamp := Entry.Signature+':'+FImages.Width.ToString+':'+FImages.Height.ToString;
      if FApplied.TryGetValue(Path,Previous) and (Previous=Stamp) then Continue;
      if Length(Entry.Pixels)>0 then begin
        var Bitmap := TBitmap.Create;
        try
          PaintCharacterPixels(Entry.Pixels,Entry.Width,Entry.Height,Bitmap,FImages.Width,FImages.Height);
          if Item.ImageIndex<0 then Item.ImageIndex := FImages.Add(Bitmap,nil)
          else FImages.Replace(Item.ImageIndex,Bitmap,nil);
        finally Bitmap.Free; end;
      end else Item.ImageIndex := -1;
      if Assigned(FOnApplied) then FOnApplied(Self,Item,Entry.Metadata);
      FApplied.AddOrSetValue(Path,Stamp);
    except on E: Exception do begin
      if FApplied.TryGetValue(Path,Previous) and (Previous='error:'+E.Message) then Continue;
      var Metadata := TJSONObject.Create;
      try
        Metadata.AddPair('readyForScript',TJSONBool.Create(False)); Metadata.AddPair('productionState','読込不可');
        Metadata.AddPair('productionReason',E.Message);
        if Assigned(FOnApplied) then FOnApplied(Self,Item,Metadata);
      finally Metadata.Free; end;
      Item.ImageIndex := -1; FApplied.AddOrSetValue(Path,'error:'+E.Message);
    end; end;
  end;
  FTimer.Enabled := Loading;
end;
end.
