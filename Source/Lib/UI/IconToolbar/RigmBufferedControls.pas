unit RigmBufferedControls;
// 背景消去と文字描画を同じバッファ内で行う。各画面の入力・保存処理は持たない。
interface
uses System.Classes, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.ComCtrls;
type
  TRigmBufferedFrame = class(TFrame)
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;
  TRigmBufferedPanel = class(TPanel)
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;
  TRigmBufferedListView = class(TListView)
  protected
    procedure CreateWnd; override;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;
implementation
uses Winapi.Windows, Winapi.CommCtrl;
constructor TRigmBufferedFrame.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True;
end;
procedure TRigmBufferedFrame.WndProc(var Message: TMessage);
begin
  // VCLのスタイル付きFrameはDoubleBufferedでも画面DCを先に消す。
  // メモリDC・PaintTo・親背景の合成は許可し、画面だけを空白へ戻す処理を省く。
  if (Message.Msg=WM_ERASEBKGND) and DoubleBuffered and
    (Message.WParam<>WPARAM(Message.LParam)) and not (csPaintCopy in ControlState) and
    (GetObjectType(HDC(Message.WParam))=OBJ_DC) then begin Message.Result := 1; Exit; end;
  inherited;
end;
constructor TRigmBufferedPanel.Create(AOwner: TComponent);
begin
  // ParentBackgroundは元の継承設定を保持する。変更すると親を描くFrameの配色も変わる。
  inherited; DoubleBuffered := True;
end;
procedure TRigmBufferedPanel.WndProc(var Message: TMessage);
begin
  // 背景の継承を切らず、画面DCの先行消去だけを省いてメモリDC内で親背景を合成する。
  if (Message.Msg=WM_ERASEBKGND) and DoubleBuffered and
    (Message.WParam<>WPARAM(Message.LParam)) and not (csPaintCopy in ControlState) and
    (GetObjectType(HDC(Message.WParam))=OBJ_DC) then begin Message.Result := 1; Exit; end;
  inherited;
end;
constructor TRigmBufferedListView.Create(AOwner: TComponent);
begin
  inherited; ParentDoubleBuffered := False; DoubleBuffered := False;
end;
procedure TRigmBufferedListView.CreateWnd;
begin
  inherited; ListView_SetExtendedListViewStyleEx(Handle,LVS_EX_DOUBLEBUFFER,LVS_EX_DOUBLEBUFFER);
end;
procedure TRigmBufferedListView.WndProc(var Message: TMessage);
const ManagedStyles = LVS_EX_DOUBLEBUFFER or LVS_EX_INFOTIP or LVS_EX_LABELTIP;
begin
  if Message.Msg=LVM_SETEXTENDEDLISTVIEWSTYLE then begin
    if Message.WParam<>0 then Message.WParam := Message.WParam or ManagedStyles;
    Message.LParam := (Message.LParam and not (LVS_EX_INFOTIP or LVS_EX_LABELTIP)) or LVS_EX_DOUBLEBUFFER;
  end else if Message.Msg=WM_ERASEBKGND then begin Message.Result := 1; Exit; end;
  inherited;
end;
end.
