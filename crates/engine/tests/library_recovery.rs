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
