# Single-form migration: paused 2026-10-05

See [PAUSED-20261005.md](PAUSED-20261005.md) for the authoritative handoff.

RIGMWizard.dpr starts at Home and lazily creates reusable feature Frames. Character management, PSD/legacy editing, script management/creation, and movie editing run inside one main form. Creation and movie editing share the same Session and preserve unapplied input across navigation. Existing .rigmovie processing is reused. Old Forms remain compatible; duplicated Frame code is an intermediate state.

Debug: 25 navigation checks and 11 PSD page checks passed with normal exit. Both old main and new shell isolated Release builds passed. Final Release GUI was not rerun. The old Workspace pipe entry is not connected in the new shell. Normal RIGMMaker.exe remains unchanged.

Build: Source/Psd/build-integrated.ps1 -Configuration Release -Project RIGMWizard.dpr
Isolated executable: Win64/Validation/IntegratedPsd/Release/RIGMWizard.exe
Override data: --data-root <external-folder>
Reproduction: Source/Psd/Validation/Invoke-WizardFlow.ps1 -Configuration Debug

All character fixtures and scratch .rigm files stay outside the repository. Do not resume local work until the user explicitly requests it.