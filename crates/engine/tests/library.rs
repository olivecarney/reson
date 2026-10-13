use reson_engine::library::{LibraryStore, Sort, Track};
#[test]
fn persistence_duplicates_updates_search_sort_and_version() {
    let d = tempfile::tempdir().unwrap();
    let p = d.path().join("library.db");
    let mut store = LibraryStore::open(&p).unwrap();
    let mut track = Track {
        path: "/音 ' 100%.wav".into(),
        title: "Zulu".into(),
        ..Track::default()
    };
    store.upsert(&track).unwrap();
    track.title = "Alpha".into();
    store.upsert(&track).unwrap();
    track.path = "/second.wav".into();
    store.upsert(&track).unwrap();
    let rows = store.query("", Sort::Title, false, 0, 50).unwrap();
    assert_eq!(rows.len(), 2);
    assert!(rows[0].id < rows[1].id);
    assert_eq!(
        store
            .query("100%", Sort::Title, false, 0, 50)
            .unwrap()
            .len(),
        1
    );
    assert!(store
        .query("' OR 1=1 --", Sort::Title, false, 0, 50)
        .unwrap()
        .is_empty());
    drop(store);
    let store = LibraryStore::open(&p).unwrap();
    assert_eq!(
        store
            .query("alpha", Sort::Title, false, 0, 50)
            .unwrap()
            .len(),
        2
    );
    drop(store);
    let c = rusqlite::Connection::open(&p).unwrap();
    c.pragma_update(None, "user_version", 99).unwrap();
    drop(c);
    assert!(LibraryStore::open(&p).is_err());
}
#[test]
fn scanner_handles_duplicates_unicode_malformed_and_missing() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("音 楽");
    std::fs::create_dir(&music).unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    std::fs::copy(fixture, music.join("a.wav")).unwrap();
    std::fs::write(music.join("bad.flac"), b"broken").unwrap();
    std::fs::write(music.join("skip.mp3"), b"skip").unwrap();
    let mut store = LibraryStore::open(&d.path().join("db")).unwrap();
    let cancel = std::sync::atomic::AtomicBool::new(false);
    let summary = store.scan(&music, &cancel, |_| {}).unwrap();
    assert_eq!(summary.indexed, 1);
    assert_eq!(summary.failed, 1);
    store.scan(&music, &cancel, |_| {}).unwrap();
    assert_eq!(store.query("", Sort::Title, false, 0, 50).unwrap().len(), 1);
    std::fs::remove_file(music.join("a.wav")).unwrap();
    store.scan(&music, &cancel, |_| {}).unwrap();
    assert!(store.query("", Sort::Title, false, 0, 50).unwrap()[0].missing);
    std::fs::remove_dir_all(&music).unwrap();
    assert!(store.scan(&music, &cancel, |_| {}).is_err());
    assert_eq!(store.query("", Sort::Title, false, 0, 50).unwrap().len(), 1);
}

#[test]
fn cancellation_retains_commits_and_rescan_restores_missing_track() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    for n in 0..5 {
        std::fs::copy(&fixture, music.join(format!("{n}.wav"))).unwrap();
    }
    let mut store = LibraryStore::open(&d.path().join("db")).unwrap();
    let cancel = std::sync::atomic::AtomicBool::new(false);
    let result = store
        .scan(&music, &cancel, |_| {
            cancel.store(true, std::sync::atomic::Ordering::Relaxed)
        })
        .unwrap();
    assert!(result.cancelled);
    assert_eq!(result.indexed, 1);
    assert_eq!(
        store.query("", Sort::Title, false, 0, 500).unwrap().len(),
        1
    );
    cancel.store(false, std::sync::atomic::Ordering::Relaxed);
    store.scan(&music, &cancel, |_| {}).unwrap();
    let before = store.query("", Sort::Title, false, 0, 500).unwrap();
    let file = std::path::Path::new(&before[0].path);
    std::fs::remove_file(file).unwrap();
    store.scan(&music, &cancel, |_| {}).unwrap();
    assert!(store.query("", Sort::Title, false, 0, 500).unwrap()[0].missing);
    std::fs::copy(&fixture, file).unwrap();
    store.scan(&music, &cancel, |_| {}).unwrap();
    let after = store.query("", Sort::Title, false, 0, 500).unwrap();
    assert!(!after[0].missing);
    assert_eq!(before[0].id, after[0].id);
    std::os::unix::fs::symlink(&music, music.join("loop")).unwrap();
    assert_eq!(store.scan(&music, &cancel, |_| {}).unwrap().indexed, 5);
}
#[test]
fn corrupt_database_fails_without_replacement_and_all_sorts_are_stable() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("bad");
    std::fs::write(&path, b"not a database").unwrap();
    assert!(LibraryStore::open(&path).is_err());
    assert_eq!(std::fs::read(path).unwrap(), b"not a database");
    let mut store = LibraryStore::open(&d.path().join("db")).unwrap();
    for n in 0..7 {
        store
            .upsert(&Track {
                path: format!("/song_{n}.wav"),
                title: format!("Title {n}"),
                artist: Some("Same".into()),
                album: Some(format!("Album {n}")),
                genre: Some("Jazz".into()),
                bpm: Some(n as f64),
                key: Some(format!("{n}A")),
                duration: Some(n as f64),
                format: "WAV".into(),
                ..Track::default()
            })
            .unwrap();
    }
    for code in 0..7 {
        let sort = Sort::from_code(code).unwrap();
        let a = store.query("", sort, false, 0, 500).unwrap();
        let b = store.query("", sort, false, 0, 500).unwrap();
        assert_eq!(
            a.iter().map(|t| t.id).collect::<Vec<_>>(),
            b.iter().map(|t| t.id).collect::<Vec<_>>()
        );
        assert_eq!(a.len(), 7);
    }
    assert_eq!(
        store
            .query("jazz", Sort::Title, false, 0, 500)
            .unwrap()
            .len(),
        7
    );
    assert_eq!(
        store
            .query("song_3", Sort::Title, false, 0, 500)
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        store.query("", Sort::Bpm, true, 0, 1).unwrap()[0].bpm,
        Some(6.0)
    );
    assert_eq!(
        store.query("", Sort::Title, false, 5, 500).unwrap().len(),
        2
    );
}
#[test]
fn flac_metadata_indexes_genre_bpm_key_without_analysis() {
    let d = tempfile::tempdir().unwrap();
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    let source = std::fs::read(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../tests/fixtures/pcm16-44100-1.flac"),
    )
    .unwrap();
    let mut output = source[..4].to_vec();
    let mut offset = 4;
    loop {
        let head = source[offset];
        let length = ((source[offset + 1] as usize) << 16)
            | ((source[offset + 2] as usize) << 8)
            | source[offset + 3] as usize;
        let end = offset + 4 + length;
        if head & 127 == 4 {
            let mut data = Vec::new();
            data.extend(5u32.to_le_bytes());
            data.extend(b"Reson");
            let tags = [
                "TITLE=Tagged song",
                "ARTIST=Artist",
                "ALBUM=Album",
                "GENRE=Jazz",
                "BPM=123.5",
                "INITIALKEY=8A",
            ];
            data.extend((tags.len() as u32).to_le_bytes());
            for tag in tags {
                data.extend((tag.len() as u32).to_le_bytes());
                data.extend(tag.as_bytes());
            }
            output.push(head);
            output.extend([
                (data.len() >> 16) as u8,
                (data.len() >> 8) as u8,
                data.len() as u8,
            ]);
            output.extend(data);
        } else {
            output.extend(&source[offset..end]);
        }
        offset = end;
        if head & 128 != 0 {
            break;
        }
    }
    output.extend(&source[offset..]);
    std::fs::write(music.join("tagged.flac"), output).unwrap();
    let mut store = LibraryStore::open(&d.path().join("db")).unwrap();
    let cancel = std::sync::atomic::AtomicBool::new(false);
    assert_eq!(store.scan(&music, &cancel, |_| {}).unwrap().indexed, 1);
    let row = store
        .query("", Sort::Title, false, 0, 500)
        .unwrap()
        .remove(0);
    assert_eq!(row.title, "Tagged song");
    assert_eq!(row.genre.as_deref(), Some("Jazz"));
    assert_eq!(row.bpm, Some(123.5));
    assert_eq!(row.key.as_deref(), Some("8A"));
}
