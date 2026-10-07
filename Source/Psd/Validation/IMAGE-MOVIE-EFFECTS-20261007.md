# Source-only validation result — 2026-10-07

Target: VRAM_WIZ `D:\DelphiProg\RIGMMaker`, baseline `main/e6045e1`.

All tests use source inspection or isolated temporary fixtures. No Delphi compilation, product launch/restart, EXE deployment, live project pipe mutation, external image generation or real user material changes were performed.

| Check | Result | Scope |
| --- | --- | --- |
| check_scene_image_contracts.py | PASS, 61 checks | Approval/revision/request wiring, editor gates, safe copy and adversarial PNG/JPEG/BMP fixtures using independent Python/Pillow oracle |
| validate_movie_editing_static.py | PASS | Actual Pascal pipe schema JSON extraction, video/BGM/approval/production wiring, 36 transition + 48 BGM reference scenarios, isolated WAV/JSON/clipping/speech-envelope fixtures |
| Verify-VoiceEffects.py | PASS, 7 tests | 100 catalog/default settings, strict validation, 20 DSP order/reset/source wiring, isolated PCM delay/gain preservation reference contracts |
| Copy provenance independent review | PASS | 24 source SHA256 values and 103 retained DSP core routines match read-only Aul2AudioFilter reference |
| Pascal/source checks | PASS | UTF8 BOM + CRLF, lexical string/comment/delimiter balance, includes and configured unit search paths, Python AST, 50 script schema JSON blocks and documentation JSON |

The numerical/reference checks do not execute the production Delphi implementations. `SceneImageContractCheck.dpr` is supplied for a future user build, and was not compiled or run here.

Remaining verification: user builds the source, checks actual VCL/DPI row layout and editor controls, MCI playback and loop/device behavior, native model/pipe rejection and OS copy races, actual image decoder behavior, native DSP processing and AVI/MP4 render output. There is no claim of runtime verification. See note.md and VOICE-EFFECTS-20261007.md for functional limits.
