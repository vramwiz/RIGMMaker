program DotsCodexProbe;

uses
  System.SysUtils,
  Vcl.Forms,
  DotsProbeForm in 'DotsProbeForm.pas',
  DotsProbePipe in 'DotsProbePipe.pas',
  DotsCodexTransport in 'DotsCodexTransport.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Dots Codex 通信試験';
  Application.CreateForm(TDotsProbeForm, DotsProbeMain);
  // Native window-style regression check; no pipe requests or Codex calls.
  for var I := 1 to ParamCount - 1 do
    if ParamStr(I) = '--window-check' then begin
      try
        DotsProbeMain.CheckTaskbarWindow(ParamStr(I + 1));
      except
        // The check records its failure; do not show an error dialog.
        ExitCode := 1;
      end;
      Exit;
    end;
  Application.Run;
end.
