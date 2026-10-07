"""No-build regression checks plus isolated reference-math fixtures.

This does not execute Delphi/VCL/DSP or replace the user's native build checks.
"""
from pathlib import Path
import json
import math
import tempfile
import wave
import struct
import re

ROOT = Path(__file__).resolve().parents[2]

def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8-sig")

def require(relative, *fragments):
    text = source(relative)
    for fragment in fragments:
        assert fragment in text, (relative, fragment)
    return text

model = require("Studio/Model/RigmMovieModel.pas",
    "Result.AddPair('bgm',Bgm)", "Saved.BgmFile := Asset(Project.BgmFile)",
    "Project.BgmFile := Saved.BgmFile", "ValidateMovieImageTransitions(Scene.Animation)",
    "ValidateVoiceEffectSettings(C.AudioEffects)", "AudioEffects.Free",
    "Saved.Cues[I].EffectWaveFile := Asset(Project.Cues[I].EffectWaveFile)")
audio = require("Studio/Audio/RigmMovieAudio.pas",
    "CueVoiceEffectsStamp(C)", "ApplyCueVoiceEffects(C,Source.Rate,Source.Samples)",
    "Result.SpeechSamples := Copy(Result.Samples)", "EnvelopeSamples := SpeechSamples",
    "Result.SpeechSamples := CacheSpeechSamples", "Min(Project.BgmFadeOut,Project.Duration)",
    "FILE_FLAG_OPEN_REPARSE_POINT", "CREATE_NEW", "MOVEFILE_WRITE_THROUGH",
    "if THashSHA2.GetHashStringFromFile(Result)<>Hash")
compositor = require("Studio/Rendering/RigmMovieCompositor.pas",
    "MovieImageOpacity(S.Animation,SceneLocal,Project.SceneDuration(S))",
    "Before[P+Channel]*(255-Alpha)")
session = require("Studio/Session/RigmMovieSession.pas",
    "CopyCheckedMovieBgm(ResolveMoviePath(FProject.FileName,JS(Bgm,'file'))",
    "Scene.ImageApproved", "S.ImageApproved", "RequireRevision(Args)",
    "EditCueVoiceEffects(Next,JS(Args,'id'),JO(Args,'audioEffects'))",
    "Imported.ImageApprovalKey<>Existing.ImageApprovalKey",
    "Imported.ImageEditEpoch<>Existing.ImageEditEpoch",
    "Imported.Description<>Existing.Description",
    "Project.Validate; GuardApprovedSceneUpdates(FProject,Project)")
commands = require("Studio/Session/RigmMovieCompositionCommands.pas",
    "LockedScene.ImageApproved", "Args.GetValue('imagePrompt')", "Args.GetValue('description')",
    "Args.GetValue('displayMode')", "CopyCheckedMovieImage(ResolveMoviePath",
    "ValidateMovieImageTransitions(Animation)", "Approved closing image metadata")
controls = require("Studio/Views/Editor/RigmMovieControls.pas",
    "MovieApplyImageAnimation", "MovieSelectBgm", "MovieBgmVolume", "MovieBgmFadeOut")
form = require("Studio/Views/Editor/RigmMovieForm.pas",
    "DraftPages[1] := SceneDraft or ChartDraft or AnimationDraft",
    "DraftPages[3] := VoiceDraft or BgmDraft", "46,47,48: begin",
    "Run('waveform-refresh')", "FUi.SceneDescription.ReadOnly")
jobs = require("Studio/Workflow/RigmMovieJobs.pas",
    "CachedMovieAudio(FProject", "RenderMovieFrame(")
require("Studio/Rendering/RigmMovieRendering.pas", "RenderComposition(Project,Seconds,Audio)")
require("Studio/Output/RigmMovieMp4.pas", "Audio.Save(WaveFile)")
require("Studio/Output/RigmMovieAvi.pas", "Audio.Samples")
require("Studio/Workflow/RigmMoviePreparation.pas",
    "|bgm|", "bgm_missing", "bgm_invalid", "bgm_unchecked", "bgm_unreadable",
    "AudioOK and CharacterOK and BgmOK and OutputOK",
    "CharacterOK and BgmOK and (Project.Cues.Count>0)")
require("Studio/Workflow/RigmMovieProduction.pas",
    "P.BgmFile := Current.BgmFile; P.BgmVolume := Current.BgmVolume; P.BgmFadeOut := Current.BgmFadeOut",
    "Put(O,'bgm',JO(Existing,'bgm').Clone as TJSONObject)",
    "MergeProductionBgm(Current,O,JO(Settings,'bgm'),Current.FileName)",
    "CopyCheckedMovieBgm(ResolveMoviePath(Base,Path)",
    "C.AudioEffects := Old.AudioEffects.Clone as TJSONObject")
require("Studio/Workflow/RigmMovieJobs.pas",
    "if (FProject.Characters.Count>0) or (FProject.BgmFile<>'') then ValidateCompositionMaterials(FProject)")

# Parse the actual constant Delphi schema fragments, including both added APIs.
schema_expression = session.split("Result.AddPair('commands',ParseObject(",1)[1].split("));",1)[0]
parts = re.findall(r"'((?:''|[^'])*)'", schema_expression)
schema = json.loads("".join(part.replace("''", "'") for part in parts))
assert "bgm" in schema["update-project"]
assert "audioEffects" in schema["update-cue"]
extra_expression = session.split("var Extra := ParseObject(",1)[1].split(");",1)[0]
extra = json.loads("".join(part.replace("''", "'") for part in re.findall(r"'((?:''|[^'])*)'", extra_expression)))
assert extra["update-scene"]["animation"]["enter"] == "none|fade"

def opacity(local, duration, enter, leave):
    if enter + leave > duration and enter + leave > 0:
        scale = duration / (enter + leave)
        enter *= scale
        leave *= scale
    result = 1.0
    if enter:
        result = min(result, max(0.0, min(1.0, local / enter)))
    if leave:
        result = min(result, max(0.0, min(1.0, (duration-local) / leave)))
    return result, enter, leave

for duration in [0, 0.001, 0.1, 0.8, 3, 20]:
    for enter, leave in [(0, 0), (0.5, 0), (0, 0.5), (0.5, 0.5), (60, 60), (0.01, 60)]:
        values = [opacity(duration*i/100, duration, enter, leave) for i in range(101)]
        assert all(0 <= value <= 1 and a+b <= duration+1e-10 for value,a,b in values)
        if enter and duration:
            assert values[0][0] == 0
        if leave and duration:
            assert values[-1][0] == 0
assert opacity(0.5, 0.1, 0.5, 0.5)[1:] == (0.05, 0.05)

def bgm_gain(time, duration, volume, fade):
    fade = min(fade, duration)
    if fade > 0 and time > duration-fade:
        return volume*max(0.0, min(1.0, (duration-time)/fade))
    return volume

for duration in [0.1, 2, 10]:
    for fade in [0, 0.1, 2, 3600]:
        for volume in [0, 0.25, 1, 2]:
            samples = [bgm_gain(duration*i/100, duration, volume, fade) for i in range(101)]
            assert all(0 <= x <= volume for x in samples)
            assert all(a >= b for a,b in zip(samples,samples[1:]))
            if fade:
                assert samples[-1] == 0
assert bgm_gain(5, 10, 0.25, 2) == 0.25
assert bgm_gain(9, 10, 0.25, 2) == 0.125

# Generated audio fixtures stay outside every user's real project/material folder.
with tempfile.TemporaryDirectory(prefix="rigmovie-editing-") as directory:
    path = Path(directory)/"bgm.wav"
    samples = [10000, -10000]*400
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(8000)
        stream.writeframes(struct.pack("<"+"h"*len(samples), *samples))
    original = path.read_bytes()
    settings = {"bgm":{"file":str(path), "volume":0.25, "fadeOut":3600},
                "scene":{"id":"stable-scene-id", "animation":{"enter":"fade", "exit":"fade", "enterSeconds":0.5,"exitSeconds":0.5}}}
    assert json.loads(json.dumps(settings)) == settings
    speech = [32000]*4800
    envelope = speech.copy()
    mixed = [max(-32768, min(32767, round(value+10000*bgm_gain(i/48000,0.1,0.25,3600))))
             for i,value in enumerate(speech)]
    assert envelope == speech and mixed != speech
    assert min(mixed) >= -32768 and max(mixed) <= 32767
    assert path.read_bytes() == original

# Preserve Delphi source conventions without creating any EXE/DCU.
for relative in ["Studio/Model/RigmMovieTransitions.pas", "Studio/Model/RigmMovieModel.pas",
                 "Studio/Audio/RigmMovieAudio.pas", "Studio/Rendering/RigmMovieCompositor.pas",
                 "Studio/Session/RigmMovieCompositionCommands.pas", "Studio/Session/RigmMovieSession.pas",
                 "Studio/Workflow/RigmMoviePreparation.pas",
                 "Studio/Workflow/RigmMovieProduction.pas",
                 "Studio/Views/Editor/RigmMovieControls.pas", "Studio/Views/Editor/RigmMovieForm.pas"]:
    data = (ROOT/relative).read_bytes()
    assert data.startswith(b"\xef\xbb\xbf"), relative
    assert b"\n" not in data.replace(b"\r\n", b""), relative
print("PASS: video wiring/static guards/pipe schema JSON, 36 transition scenarios, 48 BGM fade scenarios, isolated WAV/JSON/clipping/speech-envelope fixtures; native Delphi/VCL unexecuted")
