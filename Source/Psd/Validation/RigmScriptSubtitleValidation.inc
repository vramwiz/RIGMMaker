// 所有確認作品の字幕操作・分離・入力ロック・保存再開。意味的AI判断は行わない。
procedure VerifyScriptSubtitles(Main: TRigmWizardMainForm; const ResultPath: string; Reopen: Boolean);
  procedure Check(Value: Boolean; const Text: string; Results: TJSONArray);
  begin if not Value then raise Exception.Create('Subtitle check: '+Text); Results.Add(Text); end;
  procedure Press(Control: TWinControl; Key: Word);
  begin Control.SetFocus; Control.Perform(WM_KEYDOWN,Key,0); Application.ProcessMessages; end;
begin
  var Marker := ParseObject(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'gui-validation-owner.json'),TEncoding.UTF8));
  try if JS(Marker,'owner')<>'RIGMMaker.ScriptSubtitles.Validation.v1' then raise Exception.Create('Owned subtitle root required'); finally Marker.Free; end;
  Main.Position := poDesigned; Main.SetBounds(40,40,1280,840); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
  var Report := TJSONObject.Create; var Results := TJSONArray.Create; Report.AddPair('checks',Results);
  try
    var W := Main.Workspace; W.OpenScriptDraft(Trim(TFile.ReadAllText(TPath.Combine(Main.DataRoot,'fixture-project.txt'),TEncoding.UTF8))); Main.NavigateTo(apScriptCreate);
    var Creator := Main.PageInstance(apScriptCreate); var Toolbar := TComponent(Creator); var Next := TRigmScriptStageProbe.CreateForFrame(Toolbar,W);
    if Reopen then begin
      var Resume := ParseObject(TFile.ReadAllText(ResultPath+'.resume.json',TEncoding.UTF8)); var Json := W.ScriptDraft.Json;
      try Check(W.CurrentScriptStage='subtitles','restart resumes saved subtitle destination',Results);
        Check(W.ScriptDraft.Id=JS(Resume,'projectId'),'same UID after restart',Results);
        Check(Json.ToJSON=JS(Resume,'project'),'subtitle note selection voice scenes and casting all survive restart',Results);
      finally Json.Free; Resume.Free; end;
    end else begin
      Check(W.CurrentScriptStage='casting','copied previous casting draft opened without source modification',Results);
      var Rejected := False; try W.NextScriptDraft; except on E: Exception do Rejected := True; end;
      Check(Rejected and (W.CurrentScriptStage='casting'),'unconfirmed casting cannot advance',Results);
      var Cast: TRigmScriptCastingFrame := nil;
      for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptCastingFrame then Cast := TRigmScriptCastingFrame(Creator.Components[I]);
      var CastingList := TListView(Cast.FindComponent('ScriptCastingRows')); W.SelectCasting(W.ScriptDraft.Cues[0].Id);
      for var I := 0 to W.ScriptDraft.Cues.Count-1 do Press(CastingList,Ord('1'));
      Check(JS(W.ScriptDraft.ScriptWizard,'castingStatus')='complete','GUI numbers complete human casting before subtitle Next',Results);
      WaitThumbnailLibrary(W); W.SaveScriptDraft(False); var Path := W.ScriptDraft.FileName; var Hash := THashSHA2.GetHashStringFromFile(Path); var Guard := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
      try Next.Click; Check((W.CurrentScriptStage='casting') and (THashSHA2.GetHashStringFromFile(Path)=Hash),'failed Next keeps casting screen and saved disk',Results); finally Guard.Free; end;
      Next.Click; Check((W.CurrentScriptStage='subtitles') and not W.ScriptDraft.Modified,'Next saves subtitle destination before navigation',Results);
    end;
    var Frame: TRigmScriptSubtitleFrame := nil;
    for var I := 0 to Creator.ComponentCount-1 do if Creator.Components[I] is TRigmScriptSubtitleFrame then Frame := TRigmScriptSubtitleFrame(Creator.Components[I]);
    Check((Frame<>nil) and Frame.Showing and Next.Visible,'lazy subtitle frame stays within main form and exposes saved Next to voice',Results);
    var List := TListView(Frame.FindComponent('ScriptSubtitleRows')); var Editor := TMemo(Frame.FindComponent('ScriptSubtitleText')); var Note := TMemo(Frame.FindComponent('ScriptSubtitleNote'));
    var Tools := TToolBar(Frame.FindComponent('ScriptSubtitleToolbar')); var Ready := TToolButton(Tools.FindComponent('ScriptSubtitleReady'));
    if not Reopen then begin
      var Raw := ScriptFingerprint(W.ScriptDraft); var Cue := W.ScriptDraft.Cues[0]; var Id := Cue.Id; var Voice := Cue.Text; var Audio := W.ScriptDraft.AudioFingerprint(Cue);
      var Scene := Cue.Scene; var Other := W.ScriptDraft.Cues[2].Json; var OtherJson: string;
      try OtherJson := Other.ToJSON; finally Other.Free; end;
      Press(List,VK_DOWN); Check(JS(JO(W.ScriptDraft.ScriptWizard,'subtitles'),'selectedCue')=W.ScriptDraft.Cues[1].Id,'down selects next speech',Results);
      Press(List,VK_UP); Check(JS(JO(W.ScriptDraft.ScriptWizard,'subtitles'),'selectedCue')=Id,'up selects previous speech',Results);
      Press(List,VK_RETURN); Check(not W.ScriptTextEditing and not Editor.ReadOnly,'Enter opens display details without locking communication',Results);
      Editor.Text := 'AB'+Char($D83D)+Char($DE00)+'CDEF'+#13#10+'後ろの表示文'+#13#10+'最後の行'; Note.Text := '字幕専用の確認メモ';
      Check((Cue.Text=Voice) and (ScriptFingerprint(W.ScriptDraft)=Raw) and (W.ScriptDraft.AudioFingerprint(Cue)=Audio) and (Cue.Scene=Scene),'human display edits leave raw voice audio fingerprint and scene intact',Results);
      Other := W.ScriptDraft.Cues[2].Json; try Check(Other.ToJSON=OtherJson,'display edits never propagate to other section cue',Results); finally Other.Free; end;
      CaptureUiWindow(Main,ResultPath,'.editing'); Ready.Click;
      Check(not W.ScriptTextEditing and Editor.ReadOnly and (JS(W.ScriptDraft.ScriptWizard,'subtitlesStatus')='complete'),'ready completes details and releases shared input lock',Results);
      var Original := Cue.Subtitle; Press(List,VK_LEFT); Check(Cue.Subtitle.IndexOf(#13#10)=7,'left moves first break one character',Results);
      Press(List,VK_RIGHT); Check(Cue.Subtitle=Original,'right restores first break while later manual breaks stay intact',Results);
      W.SetSubtitleBreak(Id,4); Press(List,VK_LEFT); Check(Cue.Subtitle.IndexOf(#13#10)=2,'left skips surrogate middle safely',Results);
      Press(List,VK_RIGHT); Check(Cue.Subtitle.IndexOf(#13#10)=4,'right moves across whole surrogate pair',Results);
      var Rejected := False; var Before := Cue.Subtitle;
      try W.EditSubtitle(Id,'表示',StringOfChar('あ',2049)); except on E: Exception do Rejected := True; end;
      Check(Rejected and (Cue.Subtitle=Before) and (Cue.SubtitleNote='字幕専用の確認メモ'),'invalid note rejects whole display edit atomically',Results);
      CaptureUiWindow(Main,ResultPath,'.pipe');
      Check((W.ScriptDraft.Cues[1].Subtitle='pipe表示'+Char($D83D)+Char($DE42)+#13#10+'2行目') and (W.ScriptDraft.Cues[1].SubtitleNote='パイプ確認メモ'),'actual pipe display edit reaches same cue model',Results);
      Check((Cue.Text=Voice) and (W.ScriptDraft.AudioFingerprint(Cue)=Audio) and (ScriptFingerprint(W.ScriptDraft)=Raw),'actual pipe and wrapping keep audio and raw source unchanged',Results);
      W.EditSubtitle(Id,StringOfChar('あ',250),Cue.SubtitleNote); Frame.RefreshState;
      Check(Frame.Preview.PageCount>1,'long display text previews every existing subtitle page',Results);
      var Composition := W.ScriptDraft.Clone; var Cropped := Vcl.Graphics.TBitmap.Create;
      try
        Composition.EnableComposition; var Rendered := RenderComposition(Composition,Composition.CueStart(Composition.Cue(Id)),nil);
        try
          var Outer := ScaleLayoutRect(MovieLayoutRegions(Composition.Layout,Composition.LDirection).Subtitle,Composition.Width,Composition.Height);
          Cropped.PixelFormat := pf32bit; Cropped.SetSize(Outer.Width,Outer.Height); Cropped.Canvas.CopyRect(Rect(0,0,Outer.Width,Outer.Height),Rendered.Canvas,Outer); GdiFlush;
          var Equal := True;
          for var Y := 0 to Cropped.Height-1 do begin
            var A := PByte(Cropped.ScanLine[Y]); var B := PByte(Frame.Preview.Bitmap.ScanLine[Y]);
            for var X := 0 to Cropped.Width*4-1 do if (X mod 4<>3) and (A[X]<>B[X]) then Equal := False;
          end;
          Check(Equal,'one standard compositor frame matches subtitle preview pixels exactly',Results);
          var Png := TPngImage.Create; try Png.Assign(Rendered); Png.SaveToFile(ResultPath+'.frame.png'); finally Png.Free; end;
        finally Rendered.Free; end;
      finally Cropped.Free; Composition.Free; end;
      TToolButton(Tools.FindComponent('ScriptSubtitleFollowing')).Click; CaptureUiWindow(Main,ResultPath,'.pages');
      ClickScriptStage(Toolbar,'casting'); Next.Click; Cue := W.ScriptDraft.Cue(Id);
      Check((W.CurrentScriptStage='subtitles') and (Cue.Subtitle=StringOfChar('あ',250)) and (Cue.SubtitleNote='字幕専用の確認メモ'),'back to casting and Next preserve display edits and notes',Results);
      var StaleCopy := W.ScriptDraft.Clone;
      try InvalidateScriptCasting(StaleCopy); var StaleRejected := False;
        try RigmScriptSubtitleModel.EditSubtitle(StaleCopy,Id,'古い字幕への更新','変更'); except on E: Exception do StaleRejected := True; end;
        Check(StaleRejected and (StaleCopy.Cue(Id).Subtitle=StringOfChar('あ',250)),'stale source casting prevents old subtitle mutation',Results);
      finally StaleCopy.Free; end;
      Ready.Click; W.SaveScriptDraft(False); CaptureUiWindow(Main,ResultPath,'.saved');
      var Resume := TJSONObject.Create; var Saved := W.ScriptDraft.Json;
      try Resume.AddPair('projectId',W.ScriptDraft.Id); Resume.AddPair('project',Saved.ToJSON); TFile.WriteAllText(ResultPath+'.resume.json',Resume.ToJSON,TEncoding.UTF8); finally Resume.Free; Saved.Free; end;
    end else CaptureUiWindow(Main,ResultPath,'.reopened');
    Check(W.RequestFinish,'owned application closes normally',Results);
    var Target := ResultPath; if Reopen then Target := ResultPath+'.reopened.json'; TFile.WriteAllText(Target,Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; end;
end;
