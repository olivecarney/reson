# Native execution ledger — plan: docs/superpowers/plans/2026-10-12-reson-foundation.md

Pre-flight: Tasks 1→2 share state/commands; 2→3 share Engine; 3→4 share C ABI; 4→5 share build package. Signatures consistent.
Ruling: current checkout on a local branch, no worktree or subagents — explicit user execution instruction overrides skill defaults.
Tasks: 1 in progress; 2–5 pending.
Task 1: complete — five state tests RED (missing model) → GREEN; cargo fmt check passed. Added acknowledgement sequence and output-format fields for reliable UI command completion and honest format reporting.
Ruling: Engine::send uses &mut self to serialize command sequence assignment; Swift already serializes handle access. No new concurrency abstraction.
Ruling: retain rodio callback decoding/locking as an explicit prototype limitation, not a real-time guarantee; user requested rodio initially. Later callback buffering remains unverified work.
Task 2: complete — 11 state/worker tests and 4 decoder tests passed; clippy and release build passed after replacing a linted match with matches!. Test-first logs show missing probe/worker APIs before implementation.
Task 3: complete — 19 Rust tests passed (including four FFI integration tests RED→GREEN); clippy and C header syntax passed. Caller-owned JSON text contains output fields; snapshot acknowledgement sequence appended to C ABI to prevent stopping UI refresh before queued controls finish.
Task 4: implemented — release arm64 app builds; 24 Rust tests and 2 Swift tests pass; formatting, clippy, C header and plist checks passed. Native UI verified Open/Command-O, WAV/FLAC playback state, pause, stop/reset, restart/Space, double-click, rapid replacement, inspector selection versus current playback, sidebar toggle and quit while playing. Native malformed picker rejected file before engine. Minimum-size drag did not change frame through available automation; resize QA remains unverified.
Ruling: OS default output buffer replaces rodio's fixed 2048-frame choice — AirPods accepted only 15..960 frames, causing observed output setup failure. Two regression tests failed then passed for buffer configuration and retained metadata on output failure.
Ruling: local Homebrew Rust standard library carries a macOS 27 deployment target despite requesting 14 — host app builds/runs, but older OS compatibility remains unverified and will be documented; no global toolchain changes.
