program CodexPipeProbe;

// 本編とは独立した、1フォームのCodex起動・パイプ往復確認用プロジェクト。
uses
  Vcl.Forms,
  CodexProbeForm in 'CodexProbeForm.pas',
  CodexProbeTransport in 'CodexProbeTransport.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Codex パイプ確認';
  Application.CreateForm(TCodexProbeForm, CodexProbeMain);
  Application.Run;
end.
