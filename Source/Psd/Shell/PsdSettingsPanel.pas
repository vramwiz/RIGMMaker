unit PsdSettingsPanel;

// PSD編集の右欄。行を順に積み、画面の高さを超えた設定を縦スクロールで表示する。
interface
uses System.Classes, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls;
type
  TPsdSettingsPanel = class(TScrollBox)
  private
    FContent: TPanel; // 所有する行の表示先。各行の高さを合計してスクロール範囲を作る。
  public
    constructor Create(AOwner: TComponent); override;
    function AddRow(HeightAt96: Integer): TPanel;
    function AddLabel(const Text: string; HeightAt96: Integer = 32): TLabel;
    function AddButton(const Text: string; Handler: TNotifyEvent): TButton;
    function AddEdit(const Text: string): TEdit;
    function AddCombo(const Text: string; Handler: TNotifyEvent): TComboBox;
    function AddCheck(const Text: string; Handler: TNotifyEvent = nil): TCheckBox;
    property Content: TPanel read FContent; // 借用。行内の部品は呼出元のOwnerで所有してよい。
  end;
implementation
constructor TPsdSettingsPanel.Create(AOwner: TComponent);
begin
  inherited; Align := alClient; BorderStyle := bsNone; DoubleBuffered := True;
  HorzScrollBar.Visible := False; VertScrollBar.Tracking := True;
  FContent := TPanel.Create(Self); FContent.Parent := Self; FContent.Align := alTop;
  FContent.BevelOuter := bvNone; FContent.Height := 0; FContent.DoubleBuffered := True;
end;
function TPsdSettingsPanel.AddRow(HeightAt96: Integer): TPanel;
begin
  Result := TPanel.Create(Self); Result.BevelOuter := bvNone; Result.Parent := FContent;
  Result.SetBounds(0,FContent.Height,FContent.ClientWidth,ScaleValue(HeightAt96));
  Result.Align := alTop; Result.DoubleBuffered := True;
  Result.Padding.Left := ScaleValue(8); Result.Padding.Right := ScaleValue(8);
  Result.Padding.Top := ScaleValue(4); Result.Padding.Bottom := ScaleValue(4);
  FContent.Height := FContent.Height+Result.Height;
end;
function TPsdSettingsPanel.AddLabel(const Text: string; HeightAt96: Integer): TLabel;
begin
  var Row := AddRow(HeightAt96); Result := TLabel.Create(Owner); Result.Parent := Row;
  Result.Align := alClient; Result.AutoSize := False; Result.WordWrap := True; Result.Caption := Text;
end;
function TPsdSettingsPanel.AddButton(const Text: string; Handler: TNotifyEvent): TButton;
begin
  var Row := AddRow(44); Result := TButton.Create(Owner); Result.Parent := Row;
  Result.Align := alClient; Result.WordWrap := True; Result.Caption := Text; Result.OnClick := Handler;
end;
function TPsdSettingsPanel.AddEdit(const Text: string): TEdit;
begin
  var Row := AddRow(60); var LabelControl := TLabel.Create(Owner); LabelControl.Parent := Row;
  LabelControl.Align := alTop; LabelControl.Height := ScaleValue(22); LabelControl.Caption := Text;
  Result := TEdit.Create(Owner); Result.Parent := Row; Result.Align := alClient;
end;
function TPsdSettingsPanel.AddCombo(const Text: string; Handler: TNotifyEvent): TComboBox;
begin
  var Row := AddRow(60); var LabelControl := TLabel.Create(Owner); LabelControl.Parent := Row;
  LabelControl.Align := alTop; LabelControl.Height := ScaleValue(22); LabelControl.Caption := Text;
  Result := TComboBox.Create(Owner); Result.Parent := Row; Result.Align := alClient;
  Result.Style := csDropDownList; Result.OnChange := Handler;
end;
function TPsdSettingsPanel.AddCheck(const Text: string; Handler: TNotifyEvent): TCheckBox;
begin
  var Row := AddRow(34); Result := TCheckBox.Create(Owner); Result.Parent := Row;
  Result.Align := alClient; Result.Caption := Text; Result.OnClick := Handler;
end;
end.
