unit ToolBarPanelManager;

interface

uses
  Winapi.Windows,Winapi.CommCtrl,System.SysUtils,System.Classes,System.Types,System.Generics.Collections,Vcl.ComCtrls,Vcl.Graphics,
  Vcl.Controls,Vcl.ExtCtrls;

type
  TToolBarPanelChangeEvent = procedure(Sender: TObject; Index: Integer) of object;
type
  // ToolBar と Panel を連動させる管理クラス（Attach 方式）
  TToolBarPanelManager = class
  private
    FToolBar     : TToolBar;
    FPanels      : TObjectList<TPanel>;
    FActiveIndex : Integer;
    FAttached    : Boolean;
    FOnChange: TToolBarPanelChangeEvent;
    FToolBarBackgroundColor: TColor;
    FToolBarFontColor: TColor;
    FToolBarCheckedColor: TColor;
    FToolBarPressedColor: TColor;
    FToolBarHotColor: TColor;
    FShowCaptions: Boolean;

    procedure ToolButtonClick(Sender: TObject);
    procedure SetActiveIndex(Value: Integer);

    procedure UpdatePanels;
    procedure UpdateButtons;

    procedure ToolBarCustomDraw(Sender: TToolBar; const ARect: TRect; var DefaultDraw: Boolean);
    procedure ToolBarCustomDrawButton(Sender: TToolBar; Button: TToolButton; State: TCustomDrawState; var DefaultDraw: Boolean);
  public
    constructor Create;
    destructor Destroy; override;

    // 描画後に ToolBar を関連付ける
    procedure Attach(AToolBar: TToolBar; ManageButtons: Boolean = True);
    procedure Detach;

    // ToolButton の並び順に対応する Panel を追加（0 起点）
    procedure AddPanel(Panel: TPanel);

    // すべて解除
    procedure Clear;

    // 表示切替
    procedure Activate(Index: Integer);
    procedure RefreshActive;

    property ActiveIndex: Integer read FActiveIndex write SetActiveIndex;
    property Attached: Boolean read FAttached;
    property ToolBarBackgroundColor: TColor read FToolBarBackgroundColor write FToolBarBackgroundColor;
    property ToolBarFontColor: TColor read FToolBarFontColor write FToolBarFontColor;
    property ToolBarCheckedColor: TColor read FToolBarCheckedColor write FToolBarCheckedColor;
    property ToolBarPressedColor: TColor read FToolBarPressedColor write FToolBarPressedColor;
    property ToolBarHotColor: TColor read FToolBarHotColor write FToolBarHotColor;
    // Falseの時はCaptionをヒントとして残し、ImageIndexの画像だけを中央へ描画する。
    property ShowCaptions: Boolean read FShowCaptions write FShowCaptions;

    property OnChange: TToolBarPanelChangeEvent  read FOnChange write FOnChange;
  end;

implementation

{ TToolBarPanelManager }

constructor TToolBarPanelManager.Create;
begin
  inherited Create;
  FToolBar := nil;
  FPanels  := TObjectList<TPanel>.Create(False);
  FActiveIndex := -1;
  FAttached := False;
  FToolBarBackgroundColor := clBtnFace;
  FToolBarFontColor := clWindowText;
  FToolBarCheckedColor := clHighlight;
  FToolBarPressedColor := clBtnShadow;
  FToolBarHotColor := clBtnHighlight;
  FShowCaptions := True;
end;

destructor TToolBarPanelManager.Destroy;
begin
  Detach;
  Clear;
  FPanels.Free;
  inherited Destroy;
end;

procedure TToolBarPanelManager.Attach(AToolBar: TToolBar; ManageButtons: Boolean);
var
  i  : Integer;
  Btn: TToolButton;
begin
  if FAttached then  Exit;

  FToolBar := AToolBar;
  if not Assigned(FToolBar) then  Exit;

  if FToolBar <> nil then
  begin
    FToolBar.OnCustomDraw := ToolBarCustomDraw;
    FToolBar.OnCustomDrawButton := ToolBarCustomDrawButton;
  end;

  // ToolBar 側の前提設定
  FToolBar.ShowCaptions := FShowCaptions;
  FToolBar.Flat         := True;

  // ToolButton 初期化
  if ManageButtons then for i := 0 to FToolBar.ButtonCount - 1 do
  begin
    Btn := FToolBar.Buttons[i];
    if Assigned(Btn) then
    begin
      Btn.Style   := tbsCheck;
      Btn.AllowAllUp   := False;
      Btn.Grouped := False;
      Btn.Down    := False;
      Btn.OnClick := ToolButtonClick;
    end;
  end;

  FAttached := True;

  // 初期表示を反映
  if (FActiveIndex < 0) and (FPanels.Count > 0) then
    Activate(0)
  else if ManageButtons then
    UpdateButtons;
end;

procedure TToolBarPanelManager.Detach;
begin
  if FToolBar <> nil then begin
    FToolBar.OnCustomDraw := nil;
    FToolBar.OnCustomDrawButton := nil;
  end;
  FToolBar := nil;
  FAttached := False;
end;

procedure TToolBarPanelManager.Clear;
begin
  FPanels.Clear;
  FActiveIndex := -1;
end;

procedure TToolBarPanelManager.AddPanel(Panel: TPanel);
begin
  if Panel = nil then
    Exit;

  Panel.Visible := False;
  FPanels.Add(Panel);

  // Attach 済みで最初の Panel なら即反映
  if FAttached and (FActiveIndex < 0) then
    Activate(0);
end;

procedure TToolBarPanelManager.Activate(Index: Integer);
begin
  if (Index < 0) or (Index >= FPanels.Count) then
    Exit;

  FActiveIndex := Index;

  UpdatePanels;
  UpdateButtons;

  if Assigned(FOnChange) then
    FOnChange(Self, FActiveIndex);
end;

procedure TToolBarPanelManager.RefreshActive;
var
  ActiveIndex: Integer;
begin
  if FPanels.Count = 0 then
    Exit;

  ActiveIndex := FActiveIndex;
  if ActiveIndex < 0 then
    ActiveIndex := 0;

  Activate(ActiveIndex);
end;

procedure TToolBarPanelManager.SetActiveIndex(Value: Integer);
begin
  Activate(Value);
end;

procedure TToolBarPanelManager.UpdatePanels;
var
  i: Integer;
begin
  if Assigned(FToolBar) then
    FToolBar.Parent.DisableAlign;

  try
    for i := 0 to FPanels.Count - 1 do
      FPanels[i].Visible := (i = FActiveIndex);
  finally
    if Assigned(FToolBar) then
      FToolBar.Parent.EnableAlign;
  end;
end;

procedure TToolBarPanelManager.UpdateButtons;
var
  i: Integer;
begin
  if not Assigned(FToolBar) then
    Exit;

  for i := 0 to FToolBar.ButtonCount - 1 do
    FToolBar.Buttons[i].Down := (i = FActiveIndex);
end;

procedure TToolBarPanelManager.ToolBarCustomDraw(Sender: TToolBar;
  const ARect: TRect; var DefaultDraw: Boolean);
begin
  Sender.Canvas.Brush.Style := bsSolid;
  Sender.Canvas.Brush.Color := FToolBarBackgroundColor;
  Sender.Canvas.FillRect(ARect);
  Sender.Canvas.Font.Color := FToolBarFontColor;
  DefaultDraw := True;
end;

procedure TToolBarPanelManager.ToolBarCustomDrawButton(Sender: TToolBar;
  Button: TToolButton; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  R : TRect;
  C : TColor;
begin
  if Button.Style in [tbsSeparator, tbsDivider] then Exit;
  // 非表示から追加されたボタンではVCLのBoundsRectにDFM上の旧位置・旧幅が残る。
  // 実際に描画されているネイティブツールバーの矩形を使い、非表示ボタン分の空白を描かない。
  if (not Sender.HandleAllocated) or
     (Sender.Perform(TB_GETITEMRECT, Button.Index, LPARAM(@R)) = 0) then
    R := Button.BoundsRect;

  if Button.Down or (cdsChecked in State) then
    C := FToolBarCheckedColor
  else if cdsSelected in State then
    C := FToolBarPressedColor
  else if cdsHot in State then
    C := FToolBarHotColor
  else
    C := FToolBarBackgroundColor;

  Sender.Canvas.Brush.Style := bsSolid;
  Sender.Canvas.Brush.Color := C;
  Sender.Canvas.FillRect(R);

  Sender.Canvas.Font.Color := FToolBarFontColor;

  if FShowCaptions or not Assigned(Sender.Images) or
     (Button.ImageIndex < 0) or (Button.ImageIndex >= Sender.Images.Count) then
    DrawText(Sender.Canvas.Handle, PChar(Button.Caption), -1, R,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE)
  else if not Button.Enabled and Assigned(Sender.DisabledImages) then
    Sender.DisabledImages.Draw(Sender.Canvas,
      R.Left + (R.Width - Sender.DisabledImages.Width) div 2,
      R.Top + (R.Height - Sender.DisabledImages.Height) div 2,
      Button.ImageIndex)
  else
    Sender.Images.Draw(Sender.Canvas,
      R.Left + (R.Width - Sender.Images.Width) div 2,
      R.Top + (R.Height - Sender.Images.Height) div 2,
      Button.ImageIndex, Button.Enabled);

  DefaultDraw := False;
end;

procedure TToolBarPanelManager.ToolButtonClick(Sender: TObject);
var
  Btn: TToolButton;
begin
  if not (Sender is TToolButton) then
    Exit;

  Btn := TToolButton(Sender);
  Activate(Btn.Index);
end;

end.

