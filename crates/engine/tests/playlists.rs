use reson_engine::library::{LibraryStore, Sort, Track};
use reson_engine::library_worker::Library;
use serde_json::json;

fn seed(store: &mut LibraryStore) -> Vec<i64> {
    for n in 0..4 {
        store
            .upsert(&Track {
                path: format!("/music/{n}.wav"),
                title: format!("Song {n}"),
                format: "WAV".into(),
                ..Default::default()
            })
            .unwrap();
    }
    store
        .query("", Sort::Title, false, 0, 500)
        .unwrap()
        .iter()
        .map(|t| t.id)
        .collect()
}
#[test]
fn crud_duplicates_atomic_moves_and_reopen() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut s = LibraryStore::open(&db).unwrap();
    let ids = seed(&mut s);
    let p = s.create_playlist("Test").unwrap();
    assert!(s.playlist_entries(p.id, 0, 500).unwrap().is_empty());
    s.add_playlist_tracks(p.id, &[ids[0], ids[1], ids[0], ids[2]], 0)
        .unwrap();
    let entries = s.playlist_entries(p.id, 0, 500).unwrap();
    assert_ne!(entries[0].id, entries[2].id);
    s.move_playlist_entries(p.id, &[entries[0].id, entries[2].id], 4)
        .unwrap();
    let moved = s.playlist_entries(p.id, 0, 500).unwrap();
    assert_eq!(
        moved
            .iter()
            .map(|e| e.track.title.as_str())
            .collect::<Vec<_>>(),
        ["Song 1", "Song 2", "Song 0", "Song 0"]
    );
    assert!(s.add_playlist_tracks(p.id, &[ids[3], 99999], 0).is_err());
    assert!(s
        .move_playlist_entries(p.id, &[entries[1].id, 99999], 0)
        .is_err());
    assert!(s
        .remove_playlist_entries(p.id, &[entries[1].id, 99999])
        .is_err());
    assert_eq!(
        s.playlist_entries(p.id, 0, 500)
            .unwrap()
            .iter()
            .map(|e| e.id)
            .collect::<Vec<_>>(),
        moved.iter().map(|e| e.id).collect::<Vec<_>>()
    );
    s.rename_playlist(p.id, "Renamed").unwrap();
    drop(s);
    let mut s = LibraryStore::open(&db).unwrap();
    assert_eq!(s.playlists().unwrap()[0].name, "Renamed");
    assert_eq!(s.playlist_entries(p.id, 0, 500).unwrap().len(), 4);
    s.remove_playlist_entries(p.id, &[entries[0].id]).unwrap();
    assert_eq!(s.playlist_entries(p.id, 0, 500).unwrap().len(), 3);
    s.delete_playlist(p.id).unwrap();
    assert!(s.playlists().unwrap().is_empty());
    let next = s.create_playlist("Next").unwrap();
    assert!(next.id > p.id);
    assert!(s.rename_playlist(p.id, "stale").is_err());
    assert!(s.create_playlist(" \n ").is_err());
    assert!(s.add_playlist_tracks(next.id, &[ids[0]], 1).is_err());
}
#[test]
fn migrates_real_v1_database_and_retains_missing_and_deleted_references() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut s = LibraryStore::open(&db).unwrap();
    let ids = seed(&mut s);
    drop(s);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("DROP TABLE playlist_entries; DROP TABLE playlists; PRAGMA user_version=1;")
        .unwrap();
    drop(c);
    let mut s = LibraryStore::open(&db).unwrap();
    assert_eq!(
        s.query("", Sort::Title, false, 0, 500).unwrap()[0].id,
        ids[0]
    );
    let p = s.create_playlist("Survives").unwrap();
    s.add_playlist_tracks(p.id, &[ids[0]], 0).unwrap();
    drop(s);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("PRAGMA foreign_keys=ON; UPDATE tracks SET missing=1;")
        .unwrap();
    drop(c);
    let mut s = LibraryStore::open(&db).unwrap();
    assert!(s.playlist_entries(p.id, 0, 500).unwrap()[0].track.missing);
    s.upsert(&Track {
        path: "/music/0.wav".into(),
        title: "Restored".into(),
        format: "WAV".into(),
        ..Default::default()
    })
    .unwrap();
    assert!(!s.playlist_entries(p.id, 0, 500).unwrap()[0].track.missing);
    drop(s);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("PRAGMA foreign_keys=ON; DELETE FROM tracks;")
        .unwrap();
    drop(c);
    let s = LibraryStore::open(&db).unwrap();
    let e = s.playlist_entries(p.id, 0, 500).unwrap();
    assert_eq!(e[0].track.path, "/music/0.wav");
    assert!(e[0].track.missing);
    drop(s);
    let c = rusqlite::Connection::open(&db).unwrap();
    assert_eq!(
        c.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "ok"
    );
}
#[test]
fn worker_mutations_are_persistent_and_shutdown_terminal() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut l = Library::new(db.clone()).unwrap();
    let p = l
        .request(json!({"op":"playlist_create","name":"Worker"}))
        .unwrap();
    let id = p["playlist"]["id"].as_i64().unwrap();
    assert!(l
        .request(json!({"op":"playlist_rename","playlist_id":id,"name":""}))
        .unwrap()["error"]
        .is_string());
    l.shutdown();
    assert!(l.request(json!({"op":"playlists"})).is_err());
    let mut l = Library::new(db).unwrap();
    assert_eq!(
        l.request(json!({"op":"playlists"})).unwrap()["playlists"][0]["name"],
        "Worker"
    );
}

#[test]
fn worker_append_uses_current_count_and_rejects_stale_edits() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut s = LibraryStore::open(&db).unwrap();
    let ids = seed(&mut s);
    drop(s);
    let mut l = Library::new(db).unwrap();
    let p = l
        .request(json!({"op":"playlist_create","name":"Append"}))
        .unwrap();
    let id = p["playlist"]["id"].as_i64().unwrap();
    for t in &ids[..2] {
        assert!(l
            .request(json!({"op":"playlist_add","playlist_id":id,"ids":[t]}))
            .unwrap()["error"]
            .is_null());
    }
    let e = l
        .request(json!({"op":"playlist_entries","playlist_id":id}))
        .unwrap();
    assert_eq!(e["entries"][0]["track"]["id"], ids[0]);
    let entry = e["entries"][0]["id"].as_i64().unwrap();
    assert!(l
        .request(
            json!({"op":"playlist_move","playlist_id":id,"ids":[entry],"position":2,"revision":0})
        )
        .unwrap()["error"]
        .is_string());
}

#[test]
fn failed_sql_write_rolls_back_partial_reorder_and_playlist_entries_survive_rescan() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    let file = music.join("a.wav");
    std::fs::copy(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../tests/fixtures/pcm16-44100-1.wav"),
        &file,
    )
    .unwrap();
    let cancel = std::sync::atomic::AtomicBool::new(false);
    let mut s = LibraryStore::open(&db).unwrap();
    s.scan(&music, &cancel, |_| {}).unwrap();
    let t = s.query("", Sort::Title, false, 0, 500).unwrap()[0].id;
    let p = s.create_playlist("Rescan").unwrap();
    s.add_playlist_tracks(p.id, &[t, t, t], 0).unwrap();
    let before = s
        .playlist_entries(p.id, 0, 500)
        .unwrap()
        .iter()
        .map(|e| e.id)
        .collect::<Vec<_>>();
    drop(s);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch(&format!("CREATE TRIGGER reject_reorder BEFORE UPDATE OF position ON playlist_entries WHEN OLD.id={} BEGIN SELECT RAISE(ABORT,'injected failed write'); END;",before[0])).unwrap();
    drop(c);
    let mut s = LibraryStore::open(&db).unwrap();
    assert!(s.move_playlist_entries(p.id, &[before[0]], 3).is_err());
    assert_eq!(
        s.playlist_entries(p.id, 0, 500)
            .unwrap()
            .iter()
            .map(|e| e.id)
            .collect::<Vec<_>>(),
        before
    );
    drop(s);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("DROP TRIGGER reject_reorder").unwrap();
    drop(c);
    std::fs::remove_file(&file).unwrap();
    let mut s = LibraryStore::open(&db).unwrap();
    s.scan(&music, &cancel, |_| {}).unwrap();
    assert!(s
        .playlist_entries(p.id, 0, 500)
        .unwrap()
        .iter()
        .all(|e| e.track.missing));
    std::fs::copy(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../tests/fixtures/pcm16-44100-1.wav"),
        &file,
    )
    .unwrap();
    s.scan(&music, &cancel, |_| {}).unwrap();
    let restored = s.playlist_entries(p.id, 0, 500).unwrap();
    assert!(restored.iter().all(|e| !e.track.missing && e.track.id == t));
    assert_eq!(restored.iter().map(|e| e.id).collect::<Vec<_>>(), before);
}

#[test]
fn playlist_edits_are_serviced_during_import_and_survive_cancellation() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    for n in 0..500 {
        std::fs::hard_link(&fixture, music.join(format!("{n}.wav"))).unwrap();
    }
    let mut l = Library::new(d.path().join("db")).unwrap();
    l.request(json!({"op":"import","path":music})).unwrap();
    let p = l
        .request(json!({"op":"playlist_create","name":"During import"}))
        .unwrap();
    let id = p["playlist"]["id"].as_i64().unwrap();
    let t = l.request(json!({"op":"query"})).unwrap()["tracks"][0]["id"]
        .as_i64()
        .unwrap();
    assert!(l
        .request(json!({"op":"playlist_add","playlist_id":id,"ids":[t,t]}))
        .unwrap()["error"]
        .is_null());
    assert_eq!(l.request(json!({"op":"status"})).unwrap()["busy"], true);
    l.request(json!({"op":"cancel"})).unwrap();
    l.shutdown();
    let mut l = Library::new(d.path().join("db")).unwrap();
    assert_eq!(
        l.request(json!({"op":"playlist_entries","playlist_id":id}))
            .unwrap()["entries"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn stale_foreign_key_cannot_attach_a_reused_track_id_to_the_wrong_file() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut s = LibraryStore::open(&db).unwrap();
    let ids = seed(&mut s);
    let p = s.create_playlist("Recovery").unwrap();
    s.add_playlist_tracks(p.id, &[ids[0]], 0).unwrap();
    drop(s);
    // An external SQLite client without foreign_keys enabled violates the reference.
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("DELETE FROM tracks; INSERT INTO tracks(id,path,title,format,size,modified,imported) VALUES(1,'/different.wav','Wrong file','WAV',0,0,0);").unwrap();
    drop(c);
    let s = LibraryStore::open(&db).unwrap();
    let e = s.playlist_entries(p.id, 0, 500).unwrap();
    assert_eq!(e[0].track.path, "/music/0.wav");
    assert!(e[0].track.missing);
}
