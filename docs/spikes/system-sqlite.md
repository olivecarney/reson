# macOS system SQLite / rusqlite spike

Decision: use rusqlite 0.40.2, defaults disabled, no bundled SQLite. Its libsqlite3-sys 0.38.2 minimum bindings target SQLite 3.34.1. The observed Apple runtime is 3.54.0. WAL, FULL synchronous durability, unique constraints, bound Unicode parameters, UPSERT, transactions, schema versions and JSON extraction pass. The library does not require JSON or FTS extensions.

Three spike tests pass: commit/rollback/reopen with an independent /usr/bin/sqlite3 integrity check; child helper; SIGKILL recovery both before and after commit. The runtime is compatible on this host. Older supported macOS releases have not been physically tested; pre-existing Rust standard-library deployment warnings remain.

A temporary native in-memory create-table call links to /usr/lib/libsqlite3.dylib (verified by otool). Native release executable is 2,224,560 bytes, versus v0.1.1 2,196,672 (+27,888, 1.27%) and Turso thin LTO 15,968,368. This passes the footprint gate. Temporary native probe removed. Rust-only sqlite_probe is retained for reproduction; .cargo/config.toml suppresses Homebrew pkg-config discovery.

Turso history remains at commit e26a693 and docs/spikes/turso-0.8.3.md. Its source files are archived in turso-source; reproduce on that commit. No Turso dependency remains in ordinary builds. No user library was modified by either spike.

Standalone open/schema/count/close: first 9.137 ms, warm ten runs median 0.9685 ms (Turso 7.799 / 0.6875 ms). Process wall first 26.743 ms, warm median 2.969 ms (Turso 3329.21 / 5.124 ms). First runs are cache/security affected, not controlled cold startup. v0.1.1 has no DB operation. These small differences are acceptable; footprint is decisive. Full library query timings follow separately.
