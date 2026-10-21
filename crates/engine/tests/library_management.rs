use reson_engine::library_worker::Library;
use serde_json::{json, Value};
use std::{
    path::Path,
    time::{Duration, Instant},
};
fn request(library: &mut Library, value: Value) -> Value {
    let reply = library.request(value).unwrap();
    assert!(reply.get("error").is_none(), "{reply}");
    reply
}
fn scan(library: &mut Library, root: Option<&Path>) -> Value {
    request(
        library,
        root.map_or(
            json!({"op":"rescan"}),
            |path| json!({"op":"import","path":path}),
        ),
    );
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let s = request(library, json!({"op":"status"}));
        if s["busy"] == false {
            return s;
        }
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(1));
    }
}
fn rows(library: &mut Library) -> Vec<Value> {
    request(library, json!({"op":"query"}))["tracks"]
        .as_array()
        .unwrap()
        .clone()
}
fn fixture() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/pcm16-44100-1.wav")
}
#[test]
fn sidecars_are_ignored_before_probe_but_corrupt_audio_is_reported() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    std::fs::copy(fixture(), music.join("valid.wav")).unwrap();
    for name in ["._valid.wav", ".DS_Store"] {
        std::fs::write(music.join(name), b"metadata").unwrap();
    }
    let metadata = music.join("__MACOSX");
    std::fs::create_dir(&metadata).unwrap();
    std::fs::write(metadata.join("garbage.wav"), b"metadata").unwrap();
    std::fs::write(music.join("corrupt.wav"), b"corrupt").unwrap();
    let mut l = Library::new(d.path().join("db")).unwrap();
    let s = scan(&mut l, Some(&music));
    assert_eq!(s["summary"]["indexed"], 1);
    assert_eq!(s["summary"]["failed"], 1);
    assert!(s["summary"]["error"]
        .as_str()
        .unwrap()
        .contains("corrupt.wav"));
    assert_eq!(rows(&mut l).len(), 1);
}
#[test]
fn removals_persist_restore_and_keep_playlists_and_source_files() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    for n in 0..3 {
        std::fs::copy(fixture(), music.join(format!("{n}.wav"))).unwrap();
    }
    let db = d.path().join("db");
    let mut l = Library::new(db.clone()).unwrap();
    scan(&mut l, Some(&music));
    let original = rows(&mut l);
    let ids: Vec<_> = original.iter().map(|t| t["id"].clone()).collect();
    let p =
        request(&mut l, json!({"op":"playlist_create","name":"Keep"}))["playlist"]["id"].clone();
    request(
        &mut l,
        json!({"op":"playlist_add","playlist_id":p,"ids":ids}),
    );
    // Invalid batches roll back completely.
    let failure = l
        .request(json!({"op":"tracks_remove","ids":[ids[0],999999]}))
        .unwrap();
    assert!(failure.get("error").is_some());
    assert_eq!(rows(&mut l).len(), 3);
    request(&mut l, json!({"op":"tracks_remove","ids":[ids[0]]}));
    request(&mut l, json!({"op":"tracks_remove","ids":[ids[1],ids[2]]}));
    assert!(rows(&mut l).is_empty());
    scan(&mut l, None);
    assert!(rows(&mut l).is_empty());
    drop(l);
    let mut l = Library::new(db.clone()).unwrap();
    scan(&mut l, None);
    assert!(rows(&mut l).is_empty());
    // A replacement at the same path remains excluded until explicit restoration.
    std::fs::copy(fixture(), music.join("0.wav")).unwrap();
    scan(&mut l, None);
    assert!(rows(&mut l).is_empty());
    let excluded = request(&mut l, json!({"op":"sources"}));
    assert_eq!(excluded["exclusions"].as_array().unwrap().len(), 3);
    request(
        &mut l,
        json!({"op":"exclusion_restore","path":original[0]["path"]}),
    );
    scan(&mut l, None);
    assert_eq!(rows(&mut l).len(), 1);
    let entries = request(&mut l, json!({"op":"playlist_entries","playlist_id":p}));
    assert_eq!(entries["entries"].as_array().unwrap().len(), 3);
    assert_eq!(entries["entries"][0]["track"]["missing"], false);
    assert_eq!(entries["entries"][1]["track"]["missing"], true);
    request(
        &mut l,
        json!({"op":"folder_remove","path":music.canonicalize().unwrap()}),
    );
    assert!(rows(&mut l).is_empty());
    scan(&mut l, Some(&music));
    assert_eq!(
        rows(&mut l).len(),
        3,
        "Removing last covering source clears its exclusions"
    );
    for n in 0..3 {
        assert!(music.join(format!("{n}.wav")).is_file());
    }
    drop(l);
    let c = rusqlite::Connection::open(db).unwrap();
    assert_eq!(
        c.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "ok"
    );
}
#[test]
fn nested_sources_and_similar_prefixes_are_independent_even_when_offline() {
    let d = tempfile::tempdir().unwrap();
    let parent = d.path().join("music");
    let child = parent.join("nested");
    let sibling = d.path().join("music-other");
    for path in [&parent, &child, &sibling] {
        std::fs::create_dir_all(path).unwrap();
        std::fs::copy(fixture(), path.join("a.wav")).unwrap();
    }
    let mut l = Library::new(d.path().join("db")).unwrap();
    for p in [&parent, &child, &sibling] {
        scan(&mut l, Some(p));
    }
    request(
        &mut l,
        json!({"op":"folder_remove","path":parent.canonicalize().unwrap()}),
    );
    assert_eq!(rows(&mut l).len(), 2);
    // Unregistering an unavailable source must not require canonicalizing it again.
    let path = child.canonicalize().unwrap();
    std::fs::rename(&parent, d.path().join("offline")).unwrap();
    request(&mut l, json!({"op":"folder_remove","path":path}));
    let remaining = rows(&mut l);
    assert_eq!(remaining.len(), 1);
    assert!(remaining[0]["path"]
        .as_str()
        .unwrap()
        .contains("music-other"));
}

#[test]
fn mixed_270_tracks_and_270_sidecars_index_without_errors_and_mp3_round_trips() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    for n in 0..270 {
        let (ext, name) = match n % 3 {
            0 => ("wav", "pcm16-44100-1.wav"),
            1 => ("flac", "pcm16-44100-1.flac"),
            _ => ("mp3", "synthetic.mp3"),
        };
        let fixture = fixture().with_file_name(name);
        std::fs::copy(fixture, music.join(format!("{n}.{ext}"))).unwrap();
        std::fs::write(music.join(format!("._{n}.{ext}")), b"AppleDouble metadata").unwrap();
    }
    let start = Instant::now();
    let mut l = Library::new(d.path().join("db")).unwrap();
    let status = scan(&mut l, Some(&music));
    assert_eq!(status["summary"]["indexed"], 270);
    assert_eq!(status["summary"]["visited"], 270);
    assert_eq!(status["summary"]["failed"], 0);
    println!(
        "MIXED_270_IMPORT_MS={:.3}",
        start.elapsed().as_secs_f64() * 1000.0
    );
    let mp3 = request(
        &mut l,
        json!({"op":"query","search":"Synthetic MP3","sort":6}),
    );
    let tracks = mp3["tracks"].as_array().unwrap();
    assert_eq!(tracks.len(), 90);
    assert_eq!(tracks[0]["genre"], "Electronic");
    assert_eq!(tracks[0]["bpm"], 120.0);
    assert_eq!(tracks[0]["key"], "8A");
    let playlist =
        request(&mut l, json!({"op":"playlist_create","name":"MP3 mix"}))["playlist"]["id"].clone();
    request(
        &mut l,
        json!({"op":"playlist_add","playlist_id":playlist,"ids":[tracks[0]["id"],tracks[1]["id"]]}),
    );
    let export = d.path().join("mix.m3u8");
    request(
        &mut l,
        json!({"op":"m3u8_export","playlist_id":playlist,"path":export}),
    );
    let imported = request(
        &mut l,
        json!({"op":"m3u8_import","name":"Round trip","path":export}),
    );
    assert_eq!(imported["skipped"], 0);
    let entries = request(
        &mut l,
        json!({"op":"playlist_entries","playlist_id":imported["playlist"]["id"]}),
    );
    assert_eq!(entries["entries"].as_array().unwrap().len(), 2);
    assert_eq!(entries["entries"][0]["track"]["format"], "MP3");
}

#[test]
fn v2_migration_preserves_tracks_folders_playlists_and_rolls_back_on_failure() {
    use reson_engine::library::{LibraryStore, Sort, Track};
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("db");
    let mut store = LibraryStore::open(&db).unwrap();
    store
        .upsert(&Track {
            path: "/original.wav".into(),
            title: "Original".into(),
            format: "WAV".into(),
            ..Default::default()
        })
        .unwrap();
    let track = store.query("", Sort::Title, false, 0, 1).unwrap()[0].id;
    let playlist = store.create_playlist("Keep").unwrap();
    store.add_playlist_tracks(playlist.id, &[track], 0).unwrap();
    drop(store);
    let c = rusqlite::Connection::open(&db).unwrap();
    c.execute_batch("DROP TABLE library_exclusions; PRAGMA user_version=2; CREATE VIEW library_exclusions AS SELECT 1 AS invalid;").unwrap();
    drop(c);
    assert!(LibraryStore::open(&db).is_err());
    let c = rusqlite::Connection::open(&db).unwrap();
    assert_eq!(
        c.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        2
    );
    c.execute_batch("DROP VIEW library_exclusions;").unwrap();
    drop(c);
    let store = LibraryStore::open(&db).unwrap();
    assert_eq!(
        store.query("", Sort::Title, false, 0, 1).unwrap()[0].id,
        track
    );
    assert_eq!(store.playlist_entries(playlist.id, 0, 10).unwrap().len(), 1);
    assert!(store.exclusions().unwrap().is_empty());
}
