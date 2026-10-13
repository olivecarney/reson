fn main() {
    let path = std::env::args().nth(1).unwrap();
    let start = std::time::Instant::now();
    let c = rusqlite::Connection::open(path).unwrap();
    c.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS tracks(id INTEGER PRIMARY KEY, path TEXT UNIQUE);").unwrap();
    let _: i64 = c
        .query_row("SELECT COUNT(*) FROM tracks", [], |r| r.get(0))
        .unwrap();
    drop(c);
    println!(
        "runtime={} startup_us={}",
        rusqlite::version(),
        start.elapsed().as_micros()
    );
}
