# Turso 0.8.3 compatibility and footprint spike

13 October 2026. Status: **database integration stopped at the requested footprint checkpoint**. This does not implement the persistent library. No application-support database or real music files were opened or migrated. Playback and the shipped C ABI are unchanged.

## Dependency choice

Verified the current published non-prerelease `turso` version using crates.io and the official crate sources: **0.8.3**, released 12 October 2026. Used `turso`, not `libsql`, pinned exactly in Cargo.toml/Cargo.lock with `default-features = false`. No FTS, mimalloc override or sync feature was enabled. Local API: `Builder::new_local(...).build().await`, `Database::connect`, parameterized `Connection::execute/query`, and async row iteration. `pollster` runs these futures without an async runtime or additional application threads.

The wrapper still brings in turso_core, turso_sdk_kit and turso_sync_sdk_kit. Inspection of the SDK manifest showed its default encryption/pure-Rust-crypto features remain enabled transitively. Disabling the wrapper defaults does not remove those dependencies. Their presence does not establish runtime network activity; no sync/network API was used in this spike.

Official references:

- https://docs.rs/turso/0.8.3
- https://github.com/tursodatabase/turso

## Compatibility and durability

`crates/engine/tests/turso_spike.rs` uses disposable temporary databases and original test strings. Passed:

- Creating a database and table.
- Bound parameters containing apostrophes, Unicode and spaces.
- Explicit transaction commit and rollback.
- Persisting `PRAGMA user_version` and reopening in a new connection/database object.
- Checkpointing and opening with `/usr/bin/sqlite3`, with `PRAGMA integrity_check` returning `ok` and expected committed rows/schema version.
- Killing a child process after a commit: committed rows survived and integrity checks passed.
- Killing a child process with an open uncommitted transaction: no uncommitted row survived; both conventional SQLite and Turso reopened successfully.

The checkpoint pragma returns rows, so it must be issued through `query` and drained. The initial attempt to use `execute` returned `Misuse("unexpected row during execution")`; correcting the API usage resolved it. That was a spike error, not evidence of a durability defect.

These tests are a narrow compatibility probe, not a complete library schema, migration suite, concurrency certification or release approval. No persistence defect was found in the operations tested.

## Executable size

Same arm64 host, v0.1.1 Swift interface, existing build script and audio dependencies. Native probe added only an in-memory Turso create/query call dispatched off the UI thread, which forces actual linking of the database path. Its temporary source diff is preserved in `turso-native-probe.patch`. No library UI or indexing code was included.

| Build | Executable bytes | After `strip -S -x` on a separate copy |
| --- | ---: | ---: |
| v0.1.1 baseline | 2,196,672 | 1,580,944 |
| Native Turso probe, default release profile | 20,580,688 | 16,756,832 |
| Native Turso probe, thin LTO + one codegen unit | 15,968,368 | 13,890,096 |

Default app growth is 9.37×. Even the thin-LTO stripped probe is 8.79× the stripped baseline; LTO was not applied to the baseline, so this is an intentionally favourable comparison for Turso. Stripped copies were measured only, not launched—their existing code signatures are invalidated by stripping.

The native default probe's Mach-O `__TEXT` segment grew from 1,327,104 to 15,302,656 bytes. Consequently the increase is not merely symbols. The standalone release `turso_probe` example is 18,345,472 bytes; it is not substituted for the actual app-size comparison.

The thin-LTO setting was an experimental invocation, not a permanent release-profile change. No compiler/toolchain changes were made. Existing Homebrew Rust macOS 27-versus-14 deployment warnings remain unrelated to this comparison.

## Basic startup cost

`examples/turso_probe.rs` measures local database open + create-if-missing schema + count query, including drop, on a temporary file. One first run and ten warm reopen runs:

- First database initialization: **7.799 ms**.
- Median warm database open/schema/query: **0.6875 ms**.
- First process wall time: **3,329.21 ms**.
- Median warm process wall time: **5.124 ms**.

The first executable run includes OS launch/security/cache effects and is **not** a cold application-startup benchmark or proof of a Turso startup regression. No application-ready timing, resident-memory comparison or 270/5,000/25,000-track benchmark was completed. Those await the database choice and an implemented library. The database operation measurements do not demonstrate an unacceptable startup cost; the checkpoint is specifically about executable footprint.

## Validation and build-cache recovery

All 31 Rust tests (28 existing plus three spike tests) passed. The first lint/rebuild attempt exhausted disk space after about 5.8 GB of generated Cargo artifacts accumulated across debug, native release, explicit-target release and LTO variants. Only project-generated Cargo/SPM caches were cleaned; no source or user music was removed. Recovery validation used `CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0` to avoid large debug-symbol artifacts; production profile settings were unchanged. Final lint, restored app build and Swift test results are recorded in the execution ledger. This cache exhaustion is a local build-environment incident, not a database persistence defect.

## Recommendation and next action

For a player whose existing executable is about 2.2 MB, the unavoidable measured database increase is a material lightweight-design tradeoff. The v0.2 brief explicitly requires reporting such a problem and recommending an alternative before proceeding, so persistent-library integration has not started.

Recommend **conventional SQLite through a small Rust repository interface**, potentially `rusqlite` linked to macOS's system SQLite, if keeping the executable close to the current footprint is the priority. This is a recommendation only: it has not been substituted, installed or benchmarked, and no relative speed claim is made. It would preserve local-only storage, the proposed schema and the worker/FFI architecture, while changing the explicitly requested database implementation.

Alternatively, explicitly accept Turso's measured footprint and continue the approved library milestone with 0.8.3. This spike does not establish that a 14–21 MB executable is inherently unsuitable; it establishes the cost and invokes the brief's checkpoint rather than silently relaxing the lightweight goal.

## Reproduction

The Turso/pollster dependencies are retained as **dev-dependencies only**, so the normal Reson app does not link Turso or open a library database.

```sh
cargo test -p reson-engine --test turso_spike
cargo run --release -p reson-engine --example turso_probe -- /tmp/reson-disposable-probe.db
```

For the native comparison, use a disposable copy of v0.1.1, promote Turso/pollster to normal dependencies with defaults disabled, apply `turso-native-probe.patch` and run `scripts/build.sh`. Measure its executable and compare with an untouched v0.1.1 build. Repeat with:

```sh
CARGO_PROFILE_RELEASE_LTO=thin CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 ./scripts/build.sh
```

All native probe databases are `:memory:`. Do not use a real library path for the command-line probe. Existing validation commands still apply; the application remains v0.1.1 while v0.2 is pending this decision.
