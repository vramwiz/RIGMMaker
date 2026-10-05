# PSD production requirements: 2026-10-05

The user confirmed normal plus joy, anger, sadness and fun. PSD_EMOTION_REQUIREMENTS_CONFIRMED=True; validation version 2. Existing aliases remain compatible. Real rendered expressions must be visible and distinct. Blink checks compare open/half/closed rendered images; phoneme checks compare closed/a/i/u/e/o. Identical image aliases and invisible layers do not satisfy completion. These checks do not determine semantic meaning or visual suitability.

Motion references are mandatory: face bounds, neck, screen-left/right shoulder, upper-body bottom, in canvas pixels. Both GUI and AI inputs use the same validation. Artificial fixture coordinates must never become production reference points. Front face parts are composed before small motion; non-front/full-body sequence rendering excludes face controls.

Old packages without production metadata remain editable and render-compatible. Incomplete characters cannot be newly selected as script actors. Existing projects can still load. Production edits use existing draft recovery/autosave; sessions opened from completed characters require explicit saving even when edits invalidate readiness. Explicit save and reopen were tested.

Package version 1 retains embedded PSD, poses/sequences/settings in one .psdchar. Production metadata stores validation results, version and content digest. New registrations use Characters/<UID>/character.psdchar; old paths stay unchanged. The actual registered character still lacks fun and real measured reference points. Only copied material was used in the new checks.

Syncroh2 is a reference for production rules only. RIGMMaker-owned PSD does not require Syncroh2 keys or authentication. Do not create origin.key. Its local HMAC key is DPAPI-protected; it is not cloud authorization, PSD encryption or legal ownership proof. No key was generated, read or copied. Third-party PSD must not be relabelled as authenticated self-created material.

No new images, services, installations or long MP4 exports were used in this phase. See PAUSED-20261005.md for verification and unfinished work.