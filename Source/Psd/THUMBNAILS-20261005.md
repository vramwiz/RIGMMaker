# Thumbnail selection and PSD responsiveness: 2026-10-05

The user reported text-list character selection, slow PSD opening and continuous flicker after the normal-build fix. Existing uncommitted work was retained; no commit/push, user-app termination, image generation, service or installation was performed.

## Result

Character management now uses image cards with the existing VCL TListView/TImageList and ReadCharacterThumbnail path. PSD/RIGM format and stored production state appear before the name, so long names do not hide the unfinished label. Thumbnail scaling preserves aspect ratio. The cache is local to the manager Frame, keyed by path plus file size/UTC modification time; unchanged images are reused on explicit refresh. Script character selection uses the same existing image-list component in icon mode, retaining checkboxes and the original readiness gate. No new UI library was introduced. Empty creation inputs no longer show their internal component names.

The expensive path was repeated PsdReadyForScript calls: opening validated the character before adoption, again during UI refresh and again for the returned status. View-only changes rebuilt the tree/combos and repeated validation. Opening also rendered a full-size bone-reference image before that page was needed. Paused preview continued rendering every timer tick.

TPsdSession now performs the unchanged full validation once per model revision and invalidates the result in Changed. Display-only changes preserve that result and synchronize existing controls without rebuilding the tree. Bone-reference rendering is deferred until the reference page is shown and reused while the document is unchanged. Tree/layout updates are batched. The preview host is double buffered; only its area is invalidated for animation, at a 40ms timer interval. Paused preview renders once when dirty and then stops; hidden/reference pages stop animation drawing. Existing blink, phoneme, small-motion rendering and FullHD output resolution are unchanged. The standalone PSD host explicitly activates its reused Frame.

## Measurements and verification

Same local completed PSD and two original RIGM registrations, copied to owned Temp roots. One local timing sample per phase; these are not controlled cold-cache benchmarks. Baseline used native control events with a hidden window; final checks displayed/captured the actual owned window and used the same selection/edit events. First actual loading still includes decoding and full completion validation.

| Measurement | Before Release | Final Release |
| --- | ---: | ---: |
| Library creation | 500ms | 469ms |
| First PSD edit opening | 7188ms | 3578ms |
| Three expression changes | 6313ms | 16ms |
| Static UI rebuilds for those changes | 3 | 0 |
| Repeated completion checks across the workflow | 6 | 1 |
| Additional paused frames over 0.5s | 11 | 0 |
| Hidden frames over 0.5s | 0 | 0 |
| Return and reopen same editor | 0ms | 31ms |

Final visible animation produced 20 frames over the one-second observation. Same Frame/Session ownership was retained; completion status stayed valid during display changes. Debug also passed the short thumbnail-selection/edit/page-switch checks. Native captures confirm management, PSD editing and script thumbnail selection. Physical mouse/file-dialog automation was not used, and a still image alone is not a complete flicker measurement; draw counters, update scope and buffering support the correction.

Both normal RIGMMaker.dproj standard builds passed: default Debug/Win64 and Release/Win64, without search-path/output overrides. Existing four warnings/four hints remain, zero errors. Standalone PSD host compilation also passed. Completion validation passed 13 checks, including two added checks that unchanged status reuses the validated result and an edit invalidates readiness while completed-session explicit saving remains required. Originals were unchanged.

Evidence in Win64/Validation/PsdStudio: ui-performance-before-release.json; ui-performance-after-debug.json and metadata; ui-performance-after-release.json and metadata; corresponding .library.png/.editor.png/.creation.png; ui-performance-build-debug-after.log; ui-performance-build-release-after.log; ui-build-debug-result.json; ui-build-release-result.json; ui-completion-after.log; thumbnail-ui-final.json. The external native capture reuses Capture-OwnedWindow.ps1 and only targets the validation process's main window.

## Launch and preservation

Normal launch: D:/DelphiProg/MyApp/RIGMMaker/RIGMMaker.exe. Open Home > キャラ管理・PSD制作, select a thumbnail and double-click or choose 選択キャラを編集. Home > 台本・作品管理 > creation uses thumbnail checkboxes. Data root remains D:/Users/take6/RIGMMaker.

The current usual EXE is from the normal Release/Win64 project build and passed the final GUI check. SHA256: D97A33F59A4129866E969317A80BCD4F44EE41C34DE0283675C7827156DC868B. A verified copy is retained at Win64/Validation/PsdStudio/Recovery/thumbnail-ui-d512fd0b039e4b55a416604ba04bbef5/RIGMMaker-ui-Release-verified.exe. This supersedes previous deployment hashes, which remain historical records.

Previous usual EXE: the same Recovery directory's RIGMMaker-before.exe, SHA256 1E5CEFCBE84B97DB36957D5BEAB8DC734C3040CDFEDB41D01067E18880205E71. Completed validation/standalone test EXEs are moved recoverably to that directory; the recovery index retains original paths. Owned Temp fixtures are retained outside the repository. Input PNGs/PSDs and the actual registered .psdchar retain their earlier hashes. No persistent character/script data changed for this GUI fix. The IDE and its unsaved buffers were left untouched.

The manager's stored-state label is informational; script selection still performs full material validation. First opening remains a few seconds on this machine, while reopening reuses the editor. Longer-video output and every physical GUI action were outside this narrow fix. No remaining build/deployment blocker was found.
