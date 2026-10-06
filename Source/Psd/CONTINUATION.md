# Latest handoff: resumed 2026-10-05

The user explicitly requested resumption at 22:25 UTC. Registration editing and the single-main-form shell are deployed. A subsequent user-reported IDE build failure was reproduced and corrected in the normal project; both default Debug/Win64 and Release/Win64 standard builds now pass. See [BUILD-FIX-20261005.md](BUILD-FIX-20261005.md) for the current EXE hash, standard build logs and IDE reload note; [RESUMED-20261005.md](RESUMED-20261005.md) for registration, backups and limitations; [WIZARD.md](WIZARD.md) for the entry point; [OPERATIONS.md](OPERATIONS.md) for operation.

Latest GUI correction: [THUMBNAILS-20261005.md](THUMBNAILS-20261005.md) records image-card selection, PSD readiness/UI caching, preview buffering, timing/counter evidence and the current Release EXE hash/backup. It supersedes the preceding build/deployment hash. Normal Debug/Release builds and the short actual-window checks passed; completion regression now has 13 checks.

The current implementation is uncommitted. HEAD remains 466d574c812bf4330513606434d8efa803a6a431; no commit/push was performed during resumption. Earlier .rigm cleanup is separate, and user application data and Documents remain preserved.

[PAUSED-20261005.md](PAUSED-20261005.md) is the historical shutdown snapshot. Its EXE hashes, missing-material statements and pause instruction describe that earlier state.
