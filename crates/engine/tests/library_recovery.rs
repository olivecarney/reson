use reson_engine::{
    library::{LibraryStore, Sort},
    library_worker::Library,
};
#[test]
fn importing_child() {
    let Ok(root) = std::env::var("RESON_IMPORT_RECOVERY") else {
        return;
    };
    let root = std::path::Path::new(&root);
    let music = root.join("music");
    std::fs::create_dir(&music).unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    for n in 0..2000 {
        std::fs::hard_link(&fixture, music.join(format!("{n}.wav"))).unwrap();
    }
    let mut library = Library::new(root.join("library.db")).unwrap();
    library
        .request(serde_json::json!({"op":"import","path":music}))
        .unwrap();
    loop {
        let s = library.request(serde_json::json!({"op":"status"})).unwrap();
        if s["summary"]["indexed"].as_u64().unwrap() >= 20 {
            break;
        }
    }
    println!("IMPORT_READY");
    use std::io::Write;
    std::io::stdout().flush().unwrap();
    loop {
        std::thread::park();
    }
}
#[test]
fn killed_import_reopens_with_committed_progress_and_integrity() {
    use std::{
        io::{BufRead, BufReader},
        process::{Command, Stdio},
    };
    let d = tempfile::tempdir().unwrap();
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "importing_child", "--nocapture"])
        .env("RESON_IMPORT_RECOVERY", d.path())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    let reader = std::thread::spawn(move || {
        for line in BufReader::new(stdout)
            .lines()
            .map_while(std::result::Result::ok)
        {
            if line.contains("IMPORT_READY") {
                tx.send(()).unwrap();
                break;
            }
        }
    });
    let ready = rx.recv_timeout(std::time::Duration::from_secs(10)).is_ok();
    child.kill().unwrap();
    child.wait().unwrap();
    reader.join().unwrap();
    assert!(ready);
    let store = LibraryStore::open(&d.path().join("library.db")).unwrap();
    assert!(store.query("", Sort::Title, false, 0, 500).unwrap().len() >= 20);
    drop(store);
    let c = rusqlite::Connection::open(d.path().join("library.db")).unwrap();
    assert_eq!(
        c.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "ok"
    );
}

#[test]
fn migration_child() {
    let Ok(path) = std::env::var("RESON_MIGRATION_RECOVERY") else {
        return;
    };
    let c = rusqlite::Connection::open(path).unwrap();
    c.execute_batch("BEGIN IMMEDIATE; CREATE TABLE playlists(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0); PRAGMA user_version=2;").unwrap();
    println!("MIGRATION_READY");
    use std::io::Write;
    std::io::stdout().flush().unwrap();
    loop {
        std::thread::park()
    }
}
#[test]
fn killed_uncommitted_migration_rolls_back_then_v1_migrates_successfully() {
    use std::{
        io::{BufRead, BufReader},
        process::{Command, Stdio},
    };
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut store = LibraryStore::open(&db).unwrap();
    store
        .upsert(&reson_engine::library::Track {
            path: "/fixture.wav".into(),
            title: "Preserved".into(),
            format: "WAV".into(),
            ..Default::default()
        })
        .unwrap();
    drop(store);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("DROP TABLE playlist_entries; DROP TABLE playlists; PRAGMA user_version=1;")
        .unwrap();
    drop(c);
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "migration_child", "--nocapture"])
        .env("RESON_MIGRATION_RECOVERY", &db)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    let reader = std::thread::spawn(move || {
        for line in BufReader::new(stdout)
            .lines()
            .map_while(std::result::Result::ok)
        {
            if line.contains("MIGRATION_READY") {
                tx.send(()).unwrap();
                break;
            }
        }
    });
    let ready = rx.recv_timeout(std::time::Duration::from_secs(10)).is_ok();
    child.kill().unwrap();
    child.wait().unwrap();
    reader.join().unwrap();
    assert!(ready);
    let c = rusqlite::Connection::open(&db).unwrap();
    assert_eq!(
        c.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
    drop(c);
    let mut store = LibraryStore::open(&db).unwrap();
    assert_eq!(
        store.query("", Sort::Title, false, 0, 500).unwrap()[0].title,
        "Preserved"
    );
    assert!(store.create_playlist("Recovered").is_ok());
}
