# Effects audition playback validation (2026-10-07)

`RigmEffectsPlayback.pas` replaces selected-line audition's filename-based MCI commands with `waveOut`. It reads a validated local WAV through `CreateFileW` and an extended Unicode path, then queues PCM16 in memory. It never sends a path to an audio API, obtains an 8.3 name, changes OS short-name settings, changes system volume, or rewrites the source WAV.

Public API: `TRigmEffectsPlayback.Create`, `Open(Path)`, `Play`, `Stop`, `Close`; `Loaded`/`IsOpen`, `Path`, `Playing`, `PositionSeconds`, `DurationSeconds`, `LastError`. Methods/polling belong to the creating UI thread. `Play` restarts the loaded buffer from zero; `Stop` resets position but retains it for replay; natural completion reports duration. The frame decides when to loop or adopt an offline DSP rerender.

The player holds the PCM and `WAVEHDR` until `waveOutReset`, `waveOutUnprepareHeader`, and `waveOutClose` succeed. `CALLBACK_NULL` prevents callback access to destroyed UI state. An abnormal driver refusal retains the buffer for later cleanup rather than freeing driver-owned memory. Final OS process cleanup is used if a defective driver never releases it. This rare driver-failure branch is reviewed statically, not fault-injected into a real driver.

The old failure was reproduced in isolated native Win32 and Win64 probes using the same valid fixtures. `mciSendStringW('open "<path>" type waveaudio alias <owned alias>')` returned:

| Path | MCI open result | New player |
| --- | --- | --- |
| ASCII, 106 characters | 0 | pass |
| Japanese + spaces, 109 characters | 0 | pass |
| Japanese + spaces, 129/180/240 characters | 304 (`MCIERR_FILENAME_REQUIRED`) | pass |
| Japanese + spaces, 344 characters, stereo | 268 (`MCIERR_PARAM_OVERFLOW`) | pass |

Error 304's installed Japanese text asks for an 8-character base name and 3-character extension. The text is the legacy MCI diagnostic; it does not establish that the valid source WAV needs renaming. The observed error occurs during MCI `open`, before playback. Microsoft's [general MCI error documentation](https://learn.microsoft.com/en-us/windows/win32/multimedia/general-mci-errors) identifies that diagnostic, and [waveOutUnprepareHeader documentation](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutunprepareheader) describes the required buffer lifetime.

Final checked run: Delphi 37.0 DCC32 and DCC64 with range/overflow/assertion checking enabled; **88 checks passed on each architecture**. The probes exercised open/load, initial state, playback, real device position progress, stop/reset, repeated stop, natural completion, repeated replay, close, active destruction (20 iterations), reopen/close (10 iterations), and foreign-thread rejection. They rejected missing, malformed, truncated, duplicate/empty-data, non-PCM16, inconsistent-byte-rate, incorrect/zero-alignment WAVs while preserving the prior valid loaded asset. **All 17 fixture SHA256 digests remained unchanged.**

Evidence was written outside source at `effects-fix/playback-probe/final-check/result32.json`, `result64.json`, `before-sha256.json`. The fixtures contain silence; no user audio or script was read or changed. Executables/DCUs remained in the owned probe output directories. No user application or IDE was stopped and no normal application EXE was replaced.

Reproduce with `Test-EffectsPlayback.ps1 -OutDir <isolated-output-directory> -Python <Python-3-executable>`. The script builds only `EffectsPlaybackProbe.dpr`, creates fresh isolated silent fixtures, records both old MCI and new-player behavior, and verifies fixture hashes. The default output directory is a newly named directory in the OS temporary folder. A real output device is required for native position/playback checks; device-specific failure injection and audible quality evaluation are outside this probe.

## 2026-10-19 Voice-editing page session

`OpenSession` optionally opens one fixed PCM16/48kHz/stereo waveOut device before a WAV is loaded. `IsOpen` reports device ownership; `Loaded` reports a loaded PCM buffer. Within this session, `Open(Path)` validates the incoming WAV, converts its sample rate/channels in memory, releases the previous header, and transfers the same device handle to the new buffer. `Stop` and natural completion retain the handle. `Close` ends the session. `DeviceOpenCount` is diagnostic state used to prove that repeat playback/file changes do not call waveOutOpen again. The default API used by the effects page keeps its existing lifetime.

The voice frame activates this session on entering stage 13 and deactivates it on departure/destruction. Workspace stage saving and destruction also release it. MCI aliases and long-path temporary copies were removed from voice audition. Continuous sequencing, cue fingerprints, and marking a naturally completed cue as heard still use the existing workspace logic.

Native Win32 and Win64 playback probes each passed 111 checks, including six WAV paths up to 344 characters, PCM16 mono/stereo at 22.05/24/44.1/48 kHz, buffer switching with exactly one device open, stop/end retention, invalid input, session close/reentry, and thread/lifetime checks. All 17 fixture SHA256 hashes were unchanged. Workspace lifecycle probe passed 23 checks covering activation, repeated activation/stop/cancel, departure, stage navigation, reentry and destruction. Logs and fixtures: `output/maintenance/20261019-voice-device-session/Playback/`, `Win64/VoiceDeviceSession-20261019/Check/`. Hardware-specific missing-onset behavior has not been checked by listening; the probes use silence.