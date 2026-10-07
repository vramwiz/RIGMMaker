unit RigmVoiceEffectsPreview;
// Worker owns its snapshot. UI polls a completion event; no queued callbacks outlive a frame.
interface
uses System.Classes, System.SyncObjs, RigmMovieModel;
type
  TRigmVoiceEffectsPreviewJob = class(TThread)
  private
    FProject: TRigmMovieProject; FDone: TEvent; FCueId,FKey,FFileName,FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(Project: TRigmMovieProject; const CueId: string);
    destructor Destroy; override;
    function Done: Boolean;
    property Key: string read FKey;
    property FileName: string read FFileName;
    property Error: string read FError;
  end;
implementation
uses System.SysUtils, System.IOUtils, System.Math, RigmMovieAudio, RigmVoiceEffects,
  RigmVoiceEffectsDsp, RigmModel, Winapi.Windows;
procedure SaveExclusiveWave(Audio: TRigmPcm; const Path: string);
var H: THandle; S: THandleStream;
  procedure Four(const Value: AnsiString); begin S.WriteBuffer(Value[1],4); end;
  procedure U32(Value: Cardinal); begin S.WriteBuffer(Value,4); end;
  procedure U16(Value: Word); begin S.WriteBuffer(Value,2); end;
begin
  H := CreateFile(PChar(Path),GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
  if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
  S := THandleStream.Create(H);
  try
    Four('RIFF'); U32(36+Length(Audio.Samples)*2); Four('WAVE'); Four('fmt '); U32(16);
    U16(1); U16(1); U32(Audio.Rate); U32(Audio.Rate*2); U16(2); U16(16);
    Four('data'); U32(Length(Audio.Samples)*2);
    if Length(Audio.Samples)>0 then S.WriteBuffer(Audio.Samples[0],Length(Audio.Samples)*2);
    if not FlushFileBuffers(H) then RaiseLastOSError;
  finally S.Free; CloseHandle(H); end;
end;
constructor TRigmVoiceEffectsPreviewJob.Create(Project: TRigmMovieProject; const CueId: string);
begin
  inherited Create(True); FreeOnTerminate := False; FCueId := CueId;
  FDone := TEvent.Create(nil,True,False,''); FProject := Project.Clone;
  FKey := CueEffectPreviewKey(FProject,FProject.Cue(CueId));
end;
destructor TRigmVoiceEffectsPreviewJob.Destroy;
begin
  Terminate;
  // TThread.Destroy also resumes a never-started thread to terminate it. Keep fields alive until joined.
  inherited; FProject.Free; FDone.Free;
end;
function TRigmVoiceEffectsPreviewJob.Done: Boolean;
begin Result := FDone.WaitFor(0)=wrSignaled; end;
procedure TRigmVoiceEffectsPreviewJob.Execute;
begin
  try
    try
      if Terminated or (FProject=nil) then Exit;
      var Cue := FProject.Cue(FCueId);
      if (Cue=nil) or not FProject.AudioReady(Cue) then raise Exception.Create('先にこの行の音声を生成・確認してください。');
      if (Cue.AudioSeconds<=0) or (Cue.WaveFile='') then raise Exception.Create('音声を持たない字幕行です。');
      if FProject.FileName='' then raise Exception.Create('試聴前に下書きを保存してください。');
      if Terminated then Exit;
      var Root := TPath.GetFullPath(TPath.Combine(ExtractFileDir(FProject.FileName),'Audio\Effects'));
      if not ForceDirectories(Root) then raise Exception.Create('音声エフェクト素材フォルダを作成できません。');
      var G: TGUID; CreateGUID(G); var Path := TPath.Combine(Root,'cue-effects-'+GUIDToString(G).Replace('{','').Replace('}','')+'.wav');
      if FileExists(Path) then raise Exception.Create('音声エフェクト素材名が衝突しました。');
      var SourcePath := ResolveMoviePath(FProject.FileName,Cue.WaveFile);
      if Terminated then Exit;
      // Hold a read lock through processing: source cannot be replaced halfway through a render.
      var SourceLock := TFileStream.Create(SourcePath,fmOpenRead or fmShareDenyWrite);
      try
      if Terminated then Exit;
      var Audio := TRigmPcm.Load(SourcePath);
      try
        if Abs(Audio.Duration-Cue.AudioSeconds)>0.002 then raise Exception.Create('原音声の長さが台本と一致しません。');
        ApplyCueVoiceEffects(Cue,Audio.Rate,Audio.Samples,function: Boolean begin Result := Terminated; end);
        if Terminated then Exit;
        if FKey<>CueEffectPreviewKey(FProject,Cue) then raise Exception.Create('処理中に原音声が変わりました。試聴をやり直してください。');
        SaveExclusiveWave(Audio,Path);
        var Check := TRigmPcm.Load(Path);
        try if (Check.Rate<>Audio.Rate) or (Length(Check.Samples)<>Length(Audio.Samples)) then raise Exception.Create('派生音声の検証に失敗しました。'); finally Check.Free; end;
        if not Terminated then FFileName := Path;
      finally Audio.Free; end;
      finally SourceLock.Free; end;
    except on E: Exception do FError := E.Message; end;
  finally if FDone<>nil then FDone.SetEvent; end;
end;
end.
