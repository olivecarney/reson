use rusqlite::{params, Connection};
use std::process::{Command, Stdio};
fn open(path: &std::path::Path) -> Connection {
    let c = Connection::open(path).unwrap();
    c.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        .unwrap();
    c
}
#[test]
fn transactions_reopen_features_and_system_reader() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("音 楽.db");
    let mut c = open(&path);
    println!("SQLite runtime {}", rusqlite::version());
    c.execute_batch("CREATE TABLE tracks(id INTEGER PRIMARY KEY, path TEXT UNIQUE, title TEXT); PRAGMA user_version=1;").unwrap();
    {
        let t = c.transaction().unwrap();
        t.execute(
            "INSERT INTO tracks(path,title) VALUES(?1,?2)",
            params!["/音 ' 楽.wav", "Committed"],
        )
        .unwrap();
        t.commit().unwrap();
    }
    {
        let t = c.transaction().unwrap();
        t.execute(
            "INSERT INTO tracks(path,title) VALUES(?1,?2)",
            params!["rollback", "No"],
        )
        .unwrap();
    }
    c.execute("INSERT INTO tracks(path,title) VALUES(?1,?2) ON CONFLICT(path) DO UPDATE SET title=excluded.title",params!["/音 ' 楽.wav","Committed"]).unwrap();
    assert_eq!(
        c.query_row("SELECT json_extract('{\"a\":1}', '$.a')", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        1
    );
    drop(c);
    let c = open(&path);
    assert_eq!(
        c.query_row("SELECT COUNT(*) FROM tracks", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
    assert_eq!(
        c.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
    let out = Command::new("/usr/bin/sqlite3")
        .arg(path)
        .arg("PRAGMA integrity_check; SELECT title FROM tracks;")
        .output()
        .unwrap();
    assert!(out.status.success());
    assert_eq!(String::from_utf8_lossy(&out.stdout), "ok\nCommitted\n");
}
#[test]
fn interruption_child() {
    let Ok(path) = std::env::var("RESON_SQLITE_SPIKE_PATH") else {
        return;
    };
    let c = open(std::path::Path::new(&path));
    c.execute_batch(
        "CREATE TABLE probe(id INTEGER PRIMARY KEY); BEGIN IMMEDIATE; INSERT INTO probe VALUES(1);",
    )
    .unwrap();
    if std::env::var("RESON_SQLITE_SPIKE_COMMIT").unwrap() == "1" {
        c.execute_batch("COMMIT").unwrap();
    }
    println!("SPIKE_READY");
    use std::io::Write;
    std::io::stdout().flush().unwrap();
    loop {
        std::thread::park();
    }
}
#[test]
fn killed_process_recovers_committed_and_uncommitted_transactions() {
    use std::io::{BufRead, BufReader};
    let dir = tempfile::tempdir().unwrap();
    for commit in [false, true] {
        let path = dir.path().join(format!("kill-{commit}.db"));
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "interruption_child", "--nocapture"])
            .env("RESON_SQLITE_SPIKE_PATH", &path)
            .env("RESON_SQLITE_SPIKE_COMMIT", if commit { "1" } else { "0" })
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let stdout = child.stdout.take().unwrap();
        let (tx, rx) = std::sync::mpsc::channel();
        let reader = std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                if line.contains("SPIKE_READY") {
                    let _ = tx.send(());
                    break;
                }
            }
        });
        let ready = rx.recv_timeout(std::time::Duration::from_secs(10)).is_ok();
        child.kill().unwrap();
        child.wait().unwrap();
        reader.join().unwrap();
        assert!(ready);
        let c = open(&path);
        assert_eq!(
            c.query_row("SELECT COUNT(*) FROM probe", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            i64::from(commit)
        );
        assert_eq!(
            c.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "ok"
        );
    }
}
