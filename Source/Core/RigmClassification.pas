unit RigmClassification;

interface

uses System.SysUtils, ArtDocument, RigmModel;

function InferLayerRole(Document: TRigmDocument; Layer: TArtLayer): string;
function ClassifyUnclassifiedParts(Document: TRigmDocument; PreserveLocked: Boolean = False): Integer;
function HasImageContent(Layer: TArtLayer): Boolean;

implementation

uses ArtLayerName;

function BaseName(const Name: string): string;
var Text: string; Depth: Integer;
begin
  Text := ParseLayerName(Name).DisplayName.ToLower;
  Result := ''; Depth := 0;
  for var C in Text do begin
    if (C = '(') or (C = '（') or (C = '[') or (C = '【') then Inc(Depth)
    else if (C = ')') or (C = '）') or (C = ']') or (C = '】') then begin
      if Depth > 0 then Dec(Depth) else Result := Result + C;
    end else if Depth = 0 then begin
      if C = '　' then Result := Result + ' ' else Result := Result + C;
    end;
  end;
  // Unbalanced annotations are ambiguous, so do not guess from a truncated name.
  if Depth <> 0 then Exit('');
  Result := Trim(Result);
  for var Suffix in TArray<string>.Create('画面左', '画面右', ' left', ' right', '_left', '_right',
    ' 左', ' 右', '_左', '_右', '_l', '_r') do
    if Result.EndsWith(Suffix) then begin Result := Trim(Result.Substring(0, Result.Length - Suffix.Length)); Break; end;
end;

function NamedRole(const Name: string): string;
var N: string;
begin
  N := BaseName(Name); Result := '';
  if N = '' then Exit;
  if (N = '元画像') or (N = '比較画像') or (N = '比較用') or (N = 'reference') or
    (N = 'original image') or (N = 'source image') or Name.Contains('比較用') then Exit('reference');
  if (N = '髪飾り') or (N = 'hair accessory') or (N = 'hair ornament') then Exit('accessory');
  if (N = '目') or (N = '眼') or (N = '左目') or (N = '右目') or (N = '両目') or
    (N = 'eye') or (N = 'eyes') or (N = 'left eye') or (N = 'right eye') then Exit('eye');
  if (N = '眉') or (N = '眉毛') or (N = '左眉') or (N = '右眉') or (N = '左眉毛') or
    (N = '右眉毛') or (N = 'brow') or (N = 'brows') or (N = 'eyebrow') or (N = 'eyebrows') then Exit('brow');
  if (N = '口') or (N = 'くち') or (N = 'mouth') then Exit('mouth');
  if (N = '髪') or (N = '前髪') or (N = '横髪') or (N = '後ろ髪') or (N = '後髪') or
    (N = 'アホ毛') or (N = 'hair') or (N = 'front hair') or (N = 'side hair') or
    (N = 'back hair') or (N = 'ahoge') then Exit('hair');
  if (N = '顔') or (N = 'face') then Exit('face');
  if (N = '体') or (N = '身体') or (N = '胴体') or (N = 'body') then Exit('body');
end;

function VariantRole(const Name, Context: string): string;
var N: string;
begin
  Result := ''; N := BaseName(Name);
  if (Context = '') or (N = '') then Exit;
  if (N = '通常') or (N = 'normal') or (N = 'default') or (N = 'base') then Exit(Context);
  if Context = 'eye' then begin
    for var V in TArray<string>.Create('閉じ', 'やや閉じ', '笑顔閉じ', '半開き', 'やさしい目', '開き', 'open', 'closed', 'blink') do
      if N = V then Exit(Context);
  end else if Context = 'brow' then begin
    for var V in TArray<string>.Create('喜', '怒', '哀', '楽', '困る', '画面左上げ', '画面右上げ') do
      if N = V then Exit(Context);
  end else if Context = 'mouth' then begin
    for var V in TArray<string>.Create('閉じ', '半開き', '開き', 'あ', 'い', 'う', 'え', 'お', 'ん', 'a', 'i', 'u', 'e', 'o', 'n', 'open', 'closed') do
      if N = V then Exit(Context);
  end else if Context = 'body' then begin
    for var V in TArray<string>.Create('左上を指さす', '右上を指さす', '手のひらで紹介', '腕組み', '胸に手を添える') do
      if N = V then Exit(Context);
  end;
end;

function InferLayerRole(Document: TRigmDocument; Layer: TArtLayer): string;
var Parent: TArtLayer; Context, Role: string; Depth: Integer;
begin
  Result := ''; if (Layer = nil) or (Layer.Kind <> alkImage) then Exit;
  Context := ''; Parent := Document.Art.FindLayer(Document.ParentId(Layer.Id)); Depth := 0;
  while (Parent <> nil) and (Depth < 64) do begin
    Role := NamedRole(Parent.Name);
    if Role = 'reference' then Exit('reference');
    if (Context = '') and (Role <> '') then Context := Role;
    Parent := Document.Art.FindLayer(Document.ParentId(Parent.Id)); Inc(Depth);
  end;
  Result := NamedRole(Layer.Name);
  if Result = '' then Result := VariantRole(Layer.Name, Context);
end;

function ClassifyUnclassifiedParts(Document: TRigmDocument; PreserveLocked: Boolean): Integer;
var Role: string; Part: TRigmPart; Changed: Boolean;
begin
  Result := 0;
  for var Layer in Document.Layers do if Layer.Kind = alkImage then begin
    Part := Document.Part(Layer.Id);
    if PreserveLocked and Part.Locked then Continue;
    Role := InferLayerRole(Document, Layer); Changed := False;
    // Reference identity is independent of a manually assigned role; never bind it to motion.
    if (Role = 'reference') and not Part.ReferenceOnly then begin Part.ReferenceOnly := True; Changed := True; end;
    if (Part.Role = 'other') and not Part.RoleManual and not Part.Locked and (Role <> '') then begin
      Part.Role := Role; Changed := True;
    end;
    if Changed then Inc(Result);
  end;
end;

function HasImageContent(Layer: TArtLayer): Boolean;
var Pixel, X, Y, Coverage, MX, MY, Index: Integer;
begin
  Result := False;
  if (Layer.Kind <> alkImage) or (Layer.Bounds.Width < 1) or (Layer.Bounds.Height < 1) or
    (Int64(Layer.Bounds.Width) * Layer.Bounds.Height * 4 <> Length(Layer.Pixels)) then Exit;
  for Pixel := 0 to Length(Layer.Pixels) div 4 - 1 do if Layer.Pixels[Pixel * 4 + 3] > 0 then begin
    if not Layer.HasMask or Layer.MaskDisabled then Exit(True);
    X := Pixel mod Layer.Bounds.Width; Y := Pixel div Layer.Bounds.Width;
    MX := X + Layer.Bounds.Left - Layer.MaskBounds.Left; MY := Y + Layer.Bounds.Top - Layer.MaskBounds.Top;
    Coverage := Layer.MaskDefault;
    if (MX >= 0) and (MY >= 0) and (MX < Layer.MaskBounds.Width) and (MY < Layer.MaskBounds.Height) then begin
      Index := MY * Layer.MaskBounds.Width + MX;
      if (Index < 0) or (Index >= Length(Layer.MaskPixels)) then Exit(False);
      Coverage := Layer.MaskPixels[Index];
    end;
    if Layer.MaskInvert then Coverage := 255 - Coverage;
    if Coverage > 0 then Exit(True);
  end;
end;

end.
