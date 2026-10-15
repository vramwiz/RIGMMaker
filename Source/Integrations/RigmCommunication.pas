unit RigmCommunication;

// 受信用通信方式は1プロセスの起動中固定。既存CodexとDotsを同時に待受けない。
interface
type TRigmCommunicationMode = (rcCodex, rcDots);
function RigmCommunicationMode: TRigmCommunicationMode;
function RigmCommunicationName: string;
function RigmCodexPipesEnabled: Boolean;
implementation
uses System.SysUtils;
var Initialized: Boolean; Selected: TRigmCommunicationMode;
function RigmCommunicationMode: TRigmCommunicationMode;
begin
  if not Initialized then begin
    Selected := rcCodex;
    for var I := 1 to ParamCount do begin
      var Value := '';
      if ParamStr(I).StartsWith('--communication-mode=') then Value := ParamStr(I).Substring(21)
      else if ParamStr(I)='--communication-mode' then begin
        if I=ParamCount then raise Exception.Create('--communication-mode requires codex or dots');
        Value := ParamStr(I+1);
      end else Continue;
      if Value='codex' then Selected := rcCodex
      else if Value='dots' then Selected := rcDots
      else raise Exception.Create('Unknown communication mode: '+Value);
    end;
    Initialized := True;
  end;
  Result := Selected;
end;
function RigmCommunicationName: string;
begin if RigmCommunicationMode=rcDots then Result := 'dots' else Result := 'codex'; end;
function RigmCodexPipesEnabled: Boolean;
begin Result := RigmCommunicationMode=rcCodex; end;
end.
