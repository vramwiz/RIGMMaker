program RIGMMaker;

uses
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  RIGMMakerMainForm in 'Source\Shell\RIGMMakerMainForm.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  TStyleManager.TrySetStyle('Windows Modern Dark');
  Application.MainFormOnTaskbar := True;
  Application.Title := 'RIGMMaker';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
