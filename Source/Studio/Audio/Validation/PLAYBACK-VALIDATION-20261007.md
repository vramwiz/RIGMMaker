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
