# Single-main-form entry: 2026-10-05 resumed

RIGMMaker.dpr and the auxiliary RIGMWizard.dpr now use TRigmWizardMainForm. The usual RIGMMaker.exe has been updated, with the prior executable preserved. Deployment and verification evidence are in [RESUMED-20261005.md](RESUMED-20261005.md).

Startup creates Home and the common Workspace pipe, without creating a movie Session or feature pages. Character management, PSD/legacy editing, script management/creation and movie editing use lazily created reusable Frames inside one main form. Page changes preserve editor instances and unapplied input. Creation and movie editing share the existing movie Session, project serialization, jobs, cancellation and rendering. Unapplied script input must still be imported/applied before it becomes saved project content. Close and keyboard handling are shared.

The movie Frame exposes existing File/Edit/Production menu actions, including Save As and AVI output. PSD editing has layer choices, expression registration from those choices, measured motion references and operation checks. Draft recovery is retained; completed-character editing uses explicit save. Old Forms remain available in source, and Form/Frame duplication remains an intermediate implementation detail.

The common connection is published from startup at <data-root>/Exchange/workspace-<pid>.json, routing=common-command, apiVersion=2. app-* commands operate on the Workspace; psd-* uses the active PSD editor Session; movie-* uses the shared movie Session; legacy-* and existing unprefixed editor commands use the legacy Frame. schema includes the existing movie command schema. An explicit movie command/schema request may create the Session lazily. Independent PSD entry/connection remains compatible.

Requests and responses are limited to UTF-8 60KB. Large image payloads use validated file references inside the selected data root and the existing PSD/movie file exchange paths. Closed connection files are moved to owned completed jobs for recovery.

Debug and usual-entry Release each passed 28 navigation checks plus 11 PSD page checks. The actual Debug common named pipe passed 16 checks. The final Release main window was captured with DPI-aware PrintWindow for Home, PSD, movie and legacy pages; this confirms native controls and layout but is not full physical mouse/file-dialog automation. PaintTo smoke capture does not reliably include dark VCL style hooks; use the native captures for visual evidence.

Normal build: after Embarcadero 37.0 rsvars.bat, MSBuild.exe RIGMMaker.dproj /t:Build /p:Config=Release /p:Platform=Win64. Default MSBuild.exe RIGMMaker.dproj /t:Build uses Debug/Win64. Both standard builds are verified; see [BUILD-FIX-20261005.md](BUILD-FIX-20261005.md).
Isolated validation build: Source/Psd/build-integrated.ps1 -Configuration Release -Project RIGMMaker.dpr
Isolated executable: Win64/Validation/IntegratedPsd/Release/RIGMMaker.exe
Override data: --data-root <external-folder>
Reproduction: Source/Psd/Validation/Invoke-WizardFlow.ps1 -Configuration Release -ExecutableName RIGMMaker
Native release window: Source/Psd/Validation/Invoke-ReleaseWindow.ps1

All character fixtures and scratch .rigm files stay in identified external Temp validation roots. No user EXE was stopped or overwritten while running.
