// 右側プロパティのページ切替、DPI配置、スクロール位置とフォーカスを管理する。
// 編集入力や作品revisionを変更せず、非表示ページのコントロールを保持する。
unit RigmMoviePropertyPages;
interface
uses System.Classes, System.Generics.Collections, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, RigmPropertyScrollBox, RigmIconToolbar;
type
  TRigmMovieProperty = record
    LabelControl: TLabel;   // 折り返し高さを測定する説明ラベル。ラベルなしの行はnil。
    Control     : TControl; // その行に配置する入力欄。説明だけの行はnil。
    Row         : Integer;  // ページ内での論理行の識別値。
    Column      : Integer;  // 0=全幅、1=左列、2=右列。
    Height      : Integer;  // コントロールの最低高（96 DPI基準）。
    Page        : Integer;  // セリフ・場面・演技・音声・診断のページ番号。
  end;
  TRigmMoviePropertyPages = class
  private
    FCanvas: TControlCanvas;
    FOwner         : TWinControl;                     // 借用するコントロール所有者。埋込み時はその親のDPIを使う。
    FRight         : TRigmPropertyScrollBox;
    FPropertyBar   : TRigmIconToolbar;
    FPropertyFields: TList<TRigmMovieProperty>; // 所有する配置情報。登録されたコントロールは非所有。
    FPropertyPage,FBuildPropertyPage,FLayoutPPI,FPropertyLayouts: Integer;
    FPropertyScroll: array[0..4] of Integer;     // ページごとに独立した物理ピクセルの位置。
    FPropertyFocus : array[0..4] of TWinControl; // ページへ戻る時に復帰する借用入力欄。
    FPropertyLayout,FPaused: Boolean; // 配置中の再入と、スプリッタードラッグ中の配置を抑止する。
    function Pixels(Value: Integer): Integer;
  public
    // Ownerと入力欄は借用する。登録行とページ状態だけを自身で所有する。
    constructor Create(Owner: TWinControl; Right: TRigmPropertyScrollBox; Bar: TRigmIconToolbar);
    // 登録した配置情報だけを解放する。VCLコントロールは所有フォームへ残す。
    destructor Destroy; override;
    // 96 DPI基準の配置を登録する。現在のBuildPageへ属する行となる。
    procedure AddProperty(LabelControl: TLabel; Control: TControl; Row,X,W,H: Integer);
    // 現在ページの保存識別子を返す。表示名やタブ番号に依存しない。
    function PropertyPageName: string;
    // Sender.Tagのページ番号を使って切り替える。0..4のページボタンへ配線する。
    procedure PropertyPageClick(Sender: TObject);
    // 登録済み入力欄のフォーカスを記録し、次のページ復帰に使用する。
    procedure PropertyInputEntered(Sender: TObject);
    // 入力内容を保持したままPageへ切り替え、保存したスクロール位置とフォーカスを復帰する。
    procedure SelectPropertyPage(const Page: string);
    // 現在ページの入力欄をDPIとラベルの高さに合わせて配置し、縦スクロール範囲を更新する。
    procedure LayoutProperties(Sender: TObject);
    // DPI変更時は保存済みスクロール位置も同じ比率で変換する。
    procedure ChangeScale(M,D: Integer; isDpiChange: Boolean);
    property Page: Integer read FPropertyPage;
    property BuildPage: Integer read FBuildPropertyPage write FBuildPropertyPage; // 次のAddPropertyが所属する0..4のページ番号。
    property Fields: TList<TRigmMovieProperty> read FPropertyFields; // 入力配線と下書き判定用の非所有参照。内容の変更はAddPropertyで行う。
    property LayoutCount: Integer read FPropertyLayouts;
    property Paused: Boolean read FPaused write FPaused; // True中は配置を保留する。解除後にLayoutPropertiesを呼ぶ。
  end;
implementation
uses Winapi.Windows, System.SysUtils, System.Math, RigmModel;
constructor TRigmMoviePropertyPages.Create(Owner: TWinControl; Right: TRigmPropertyScrollBox; Bar: TRigmIconToolbar);
begin inherited Create; FOwner := Owner; FCanvas := TControlCanvas.Create; FCanvas.Control := Owner; FRight := Right; FPropertyBar := Bar;
  FLayoutPPI := 96; FPropertyFields := TList<TRigmMovieProperty>.Create; end;
destructor TRigmMoviePropertyPages.Destroy;
begin FCanvas.Free; FPropertyFields.Free; inherited; end;
function TRigmMoviePropertyPages.Pixels(Value: Integer): Integer;
begin Result := MulDiv(Value,FLayoutPPI,96); end;
procedure TRigmMoviePropertyPages.ChangeScale(M,D: Integer; isDpiChange: Boolean);
begin
  for var I := 0 to High(FPropertyScroll) do FPropertyScroll[I] := MulDiv(FPropertyScroll[I],M,D);
  if isDpiChange then FLayoutPPI := M else FLayoutPPI := MulDiv(FLayoutPPI,M,D);
end;
procedure TRigmMoviePropertyPages.AddProperty(LabelControl: TLabel; Control: TControl; Row,X,W,H: Integer);
begin
  var Field: TRigmMovieProperty; Field.LabelControl := LabelControl; Field.Control := Control;
  Field.Row := Row; Field.Height := H; Field.Column := 0;
  Field.Page := FBuildPropertyPage;
  if (Control<>nil) and (Control.Name='MovieBackground') then begin Field.Page := 1; Field.Row := 110; end;
  if Field.Page=0 then case Row of 156: Field.Row := 0; 269: Field.Row := 110; 53: Field.Row := 210;
    374: Field.Row := 265; 408: Field.Row := 299; end;
  if (Field.Page=1) and (Control<>nil) and (Control.Name='MovieCueScene') then Field.Row := 55;
  if Field.Page=2 then begin if Row=102 then Field.Row := 0 else if Row=152 then Field.Row := 50; end;
  if Field.Page=3 then Field.Row := Row-448;
  if Field.Page=4 then Field.Row := Row-1150;
  if W<260 then if X<170 then Field.Column := 1 else Field.Column := 2;
  if LabelControl<>nil then begin LabelControl.AutoSize := False; LabelControl.WordWrap := True; end;
  FPropertyFields.Add(Field);
end;

function TRigmMoviePropertyPages.PropertyPageName: string;
const Names: array[0..4] of string = ('dialogue','scene','acting','audio','diagnostics');
begin Result := Names[FPropertyPage]; end;

procedure TRigmMoviePropertyPages.PropertyPageClick(Sender: TObject);
const Names: array[0..4] of string = ('dialogue','scene','acting','audio','diagnostics');
begin SelectPropertyPage(Names[TComponent(Sender).Tag]); end;

procedure TRigmMoviePropertyPages.PropertyInputEntered(Sender: TObject);
begin
  for var Field in FPropertyFields do if Field.Control=Sender then begin
    FPropertyFocus[Field.Page] := TWinControl(Sender); Break;
  end;
end;

procedure TRigmMoviePropertyPages.SelectPropertyPage(const Page: string);
const Names: array[0..4] of string = ('dialogue','scene','acting','audio','diagnostics');
begin
  var Index := -1; for var I := 0 to High(Names) do if Page=Names[I] then Index := I;
  if Index<0 then raise ERigm.Create('Unknown movie property page');
  var Host := GetParentForm(FOwner,True);
  if (Host<>nil) and (Host.ActiveControl<>nil) and
    FRight.ContainsControl(Host.ActiveControl) then FPropertyFocus[FPropertyPage] := Host.ActiveControl;
  FPropertyScroll[FPropertyPage] := FRight.VertScrollBar.Position;
  FPropertyPage := Index;
  FRight.DisableAlign;
  try
    for var Field in FPropertyFields do begin
      if Field.Control<>nil then Field.Control.Visible := Field.Page=Index;
      if Field.LabelControl<>nil then Field.LabelControl.Visible := Field.Page=Index;
    end;
    for var I := 0 to FPropertyBar.ButtonCount-1 do FPropertyBar.Buttons[I].Down := I=Index;
  finally FRight.EnableAlign; end;
  FRight.VertScrollBar.Position := 0; LayoutProperties(FOwner);
  FRight.VertScrollBar.Position := FPropertyScroll[Index]; LayoutProperties(FOwner);
  var Focus := FPropertyFocus[Index];
  if (Focus<>nil) and Focus.CanFocus then Focus.SetFocus;
end;

procedure TRigmMoviePropertyPages.LayoutProperties(Sender: TObject);
begin
  if FPropertyLayout or (FRight=nil) or (FPropertyFields=nil) or (csDestroying in FOwner.ComponentState) then Exit;
  if FPaused then Exit;
  FPropertyLayout := True;
  try
    Inc(FPropertyLayouts);
    var HostForm := GetParentForm(FOwner,True);
    if (HostForm<>nil) and (HostForm<>FOwner) then FLayoutPPI := HostForm.ScaleValue(96);
    var Scroll := FRight.VertScrollBar.Position; var Margin := Pixels(12); var Gap := Pixels(12);
    var Available := Max(Pixels(220),FRight.ClientWidth-Margin*2); var Half := (Available-Gap) div 2;
    var Rows := TList<Integer>.Create;
    try
      for var Field in FPropertyFields do if (Field.Page=FPropertyPage) and not Rows.Contains(Field.Row) then Rows.Add(Field.Row);
      Rows.Sort; var Y := Pixels(8);
      FRight.DisableAlign;
      try for var Row in Rows do begin
        var LabelHeight := 0; var ControlHeight := 0; var HasVisible := False;
        for var Field in FPropertyFields do if (Field.Page=FPropertyPage) and (Field.Row=Row) then begin
          if (Field.Control<>nil) and not Field.Control.Visible then Continue;
          HasVisible := True;
          if Field.LabelControl<>nil then begin
            Field.LabelControl.Visible := True; var W := Available; if Field.Column<>0 then W := Half;
            FCanvas.Font.Assign(Field.LabelControl.Font); FCanvas.TextHeight('M');
            var R := Rect(0,0,W,0); DrawText(FCanvas.Handle,PChar(Field.LabelControl.Caption),-1,R,DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
            LabelHeight := Max(LabelHeight,Max(Pixels(20),R.Height+Pixels(3)));
          end;
          ControlHeight := Max(ControlHeight,Pixels(Field.Height));
        end;
        if not HasVisible then Continue;
        for var Field in FPropertyFields do if (Field.Page=FPropertyPage) and (Field.Row=Row) then begin
          if (Field.Control<>nil) and not Field.Control.Visible then Continue;
          var X := Margin; var W := Available; if Field.Column<>0 then W := Half;
          if Field.Column=2 then Inc(X,Half+Gap);
          if Field.LabelControl<>nil then Field.LabelControl.SetBounds(X,Y-Scroll,W,LabelHeight);
          if Field.Control<>nil then begin
            var Height := Pixels(Field.Height);
            if Field.Control is TEdit then FCanvas.Font.Assign(TEdit(Field.Control).Font)
            else if Field.Control is TComboBox then FCanvas.Font.Assign(TComboBox(Field.Control).Font)
            else if Field.Control is TButton then FCanvas.Font.Assign(TButton(Field.Control).Font);
            if (Field.Control is TEdit) or (Field.Control is TComboBox) or (Field.Control is TButton) then
              Height := Max(Height,FCanvas.TextHeight('Mg')+Pixels(8));
            Field.Control.SetBounds(X,Y+LabelHeight-Scroll,W,Height);
            // Native combo boxes enforce a font-dependent height, particularly after DPI changes.
            ControlHeight := Max(ControlHeight,Field.Control.Height);
          end;
        end;
        Inc(Y,LabelHeight+ControlHeight+Pixels(10));
      end;
      finally FRight.EnableAlign; end;
      FRight.VertScrollBar.Range := Y+Margin;
    finally Rows.Free; end;
  finally FPropertyLayout := False; end;
end;
end.
