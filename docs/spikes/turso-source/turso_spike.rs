use std::process::Command;
#[test]
fn local_transactions_reopen_and_sqlite_reader() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("音 楽.db");
    pollster::block_on(async {
        let db = turso::Builder::new_local(path.to_str().unwrap())
            .build()
            .await
            .unwrap();
        let conn = db.connect().unwrap();
        conn.execute(
            "CREATE TABLE tracks (id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, title TEXT)",
            (),
        )
        .await
        .unwrap();
        conn.execute("BEGIN IMMEDIATE", ()).await.unwrap();
        conn.execute(
            "INSERT INTO tracks(path,title) VALUES (?1,?2)",
            ("/music/音 ' 楽.wav", "Committed"),
        )
        .await
        .unwrap();
        conn.execute("PRAGMA user_version=1", ()).await.unwrap();
        conn.execute("COMMIT", ()).await.unwrap();
        conn.execute("BEGIN IMMEDIATE", ()).await.unwrap();
        conn.execute(
            "INSERT INTO tracks(path,title) VALUES (?1,?2)",
            ("rollback.wav", "Rollback"),
        )
        .await
        .unwrap();
        conn.execute("ROLLBACK", ()).await.unwrap();
        let mut checkpoint = conn
            .query("PRAGMA wal_checkpoint(TRUNCATE)", ())
            .await
            .unwrap();
        while checkpoint.next().await.unwrap().is_some() {}
    });
    pollster::block_on(async {
        let db = turso::Builder::new_local(path.to_str().unwrap())
            .build()
            .await
            .unwrap();
        let conn = db.connect().unwrap();
        let mut rows = conn
            .query("SELECT title FROM tracks ORDER BY id", ())
            .await
            .unwrap();
        assert_eq!(
            rows.next()
                .await
                .unwrap()
                .unwrap()
                .get::<String>(0)
                .unwrap(),
            "Committed"
        );
        assert!(rows.next().await.unwrap().is_none());
        let mut rows = conn.query("PRAGMA user_version", ()).await.unwrap();
        assert_eq!(
            rows.next().await.unwrap().unwrap().get::<i64>(0).unwrap(),
            1
        );
    });
    let out = Command::new("/usr/bin/sqlite3")
        .arg(&path)
        .arg("PRAGMA integrity_check; SELECT title FROM tracks; PRAGMA user_version;")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout), "ok\nCommitted\n1\n");
}

#[test]
fn interruption_child() {
    let Ok(path) = std::env::var("RESON_TURSO_SPIKE_PATH") else {
        return;
    };
    pollster::block_on(async {
        let db = turso::Builder::new_local(&path).build().await.unwrap();
        let conn = db.connect().unwrap();
        conn.execute("CREATE TABLE probe(id INTEGER PRIMARY KEY, title TEXT)", ())
            .await
            .unwrap();
        conn.execute("BEGIN IMMEDIATE", ()).await.unwrap();
        conn.execute("INSERT INTO probe VALUES(?1,?2)", (1, "durable"))
            .await
            .unwrap();
        if std::env::var("RESON_TURSO_SPIKE_COMMIT").unwrap() == "1" {
            conn.execute("COMMIT", ()).await.unwrap();
        }
        println!("SPIKE_READY");
        use std::io::Write;
        std::io::stdout().flush().unwrap();
        loop {
            std::thread::park();
        }
    });
}
#[test]
fn killed_process_preserves_commits_and_discards_uncommitted_changes() {
    use std::{
        io::{BufRead, BufReader},
        process::Stdio,
        sync::mpsc,
        time::Duration,
    };
    let dir = tempfile::tempdir().unwrap();
    for commit in [false, true] {
        let path = dir.path().join(format!("kill-{commit}.db"));
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "interruption_child", "--nocapture"])
            .env("RESON_TURSO_SPIKE_PATH", &path)
            .env("RESON_TURSO_SPIKE_COMMIT", if commit { "1" } else { "0" })
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let stdout = child.stdout.take().unwrap();
        let (tx, rx) = mpsc::channel();
        let reader = std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                if line.contains("SPIKE_READY") {
                    let _ = tx.send(());
                    break;
                }
            }
        });
        let ready = rx.recv_timeout(Duration::from_secs(10)).is_ok();
        let _ = child.kill();
        let _ = child.wait();
        reader.join().unwrap();
        assert!(ready, "child did not reach interruption point");
        let out = Command::new("/usr/bin/sqlite3")
            .arg(&path)
            .arg("PRAGMA integrity_check; SELECT COUNT(*) FROM probe;")
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert_eq!(
            String::from_utf8_lossy(&out.stdout),
            format!("ok\n{}\n", i32::from(commit))
        );
        pollster::block_on(async {
            let db = turso::Builder::new_local(path.to_str().unwrap())
                .build()
                .await
                .unwrap();
            let conn = db.connect().unwrap();
            let mut rows = conn.query("SELECT COUNT(*) FROM probe", ()).await.unwrap();
            assert_eq!(
                rows.next().await.unwrap().unwrap().get::<i64>(0).unwrap(),
                i64::from(commit)
            );
        });
    }
}
