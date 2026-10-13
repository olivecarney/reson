use reson_engine::library::{LibraryStore, Track};
#[test]
fn unicode_relative_absolute_duplicates_missing_and_roundtrip() {
    let d = tempfile::tempdir().unwrap();
    let source = d.path().join("list.m3u8");
    let root = d.path().canonicalize().unwrap();
    let music = root.join("音 楽.wav");
    let mut s = LibraryStore::open(&d.path().join("db")).unwrap();
    s.upsert(&Track {
        path: music.to_str().unwrap().into(),
        title: "Unicode".into(),
        format: "WAV".into(),
        ..Default::default()
    })
    .unwrap();
    std::fs::write(&source,format!("\u{feff}#EXTM3U\n#EXTINF:3,Title\n音 楽.wav\n{}\n# comment\n#EXTINF:bad,Missing title\nmissing.wav\nhttps://example.com/no.wav\nfile:///no.wav\n",music.display())).unwrap();
    let (p, skipped) = s.import_m3u8(&source, "Imported").unwrap();
    assert_eq!(skipped, 2);
    let entries = s.playlist_entries(p.id, 0, 500).unwrap();
    assert_eq!(entries.len(), 3);
    assert!(entries[0].track.id > 0);
    assert_eq!(entries[0].track.id, entries[1].track.id);
    assert_ne!(entries[0].id, entries[1].id);
    assert!(entries[2].track.missing);
    assert_eq!(entries[2].track.title, "Missing title");
    let export = d.path().join("export.m3u8");
    s.export_m3u8(p.id, &export).unwrap();
    let (p2, _) = s.import_m3u8(&export, "Roundtrip").unwrap();
    let e2 = s.playlist_entries(p2.id, 0, 500).unwrap();
    assert_eq!(
        e2.iter().map(|e| &e.track.path).collect::<Vec<_>>(),
        entries.iter().map(|e| &e.track.path).collect::<Vec<_>>()
    );
    s.upsert(&Track {
        path: root.join("missing.wav").to_str().unwrap().into(),
        title: "Found".into(),
        format: "WAV".into(),
        ..Default::default()
    })
    .unwrap();
    assert!(!s.playlist_entries(p.id, 0, 500).unwrap()[2].track.missing);
}
#[test]
fn invalid_utf8_and_ambiguous_export_leave_existing_data_intact() {
    let d = tempfile::tempdir().unwrap();
    let source = d.path().join("bad.m3u8");
    let mut s = LibraryStore::open(&d.path().join("db")).unwrap();
    std::fs::write(&source, [0xff]).unwrap();
    assert!(s.import_m3u8(&source, "Bad").is_err());
    assert!(s.playlists().unwrap().is_empty());
    s.upsert(&Track {
        path: "/music/new\nline.wav".into(),
        title: "Bad".into(),
        format: "WAV".into(),
        ..Default::default()
    })
    .unwrap();
    let id = s
        .query("", reson_engine::library::Sort::Title, false, 0, 500)
        .unwrap()[0]
        .id;
    let p = s.create_playlist("Bad export").unwrap();
    s.add_playlist_tracks(p.id, &[id], 0).unwrap();
    std::fs::write(&source, "previous").unwrap();
    assert!(s.export_m3u8(p.id, &source).is_err());
    assert_eq!(std::fs::read_to_string(&source).unwrap(), "previous");
}

#[test]
fn relative_symlink_parent_is_resolved_before_lexical_fallback() {
    let d = tempfile::tempdir().unwrap();
    let base = d.path().join("base");
    let target = d.path().join("target/child");
    std::fs::create_dir_all(&base).unwrap();
    std::fs::create_dir_all(&target).unwrap();
    std::os::unix::fs::symlink(&target, base.join("linked")).unwrap();
    let file = d.path().join("target/a.wav");
    std::fs::write(&file, b"fixture").unwrap();
    let source = base.join("list.m3u8");
    std::fs::write(&source, "linked/../a.wav\n").unwrap();
    let mut s = LibraryStore::open(&d.path().join("db")).unwrap();
    let (p, _) = s.import_m3u8(&source, "Symlink").unwrap();
    assert_eq!(
        s.playlist_entries(p.id, 0, 500).unwrap()[0].track.path,
        file.canonicalize().unwrap().to_str().unwrap()
    );
}
#[test]
fn export_collision_does_not_delete_a_preexisting_file() {
    let d = tempfile::tempdir().unwrap();
    let mut s = LibraryStore::open(&d.path().join("db")).unwrap();
    let p = s.create_playlist("Empty").unwrap();
    for n in 0..100 {
        std::fs::write(
            d.path()
                .join(format!(".reson-m3u8-{}-{n}.tmp", std::process::id())),
            "existing",
        )
        .unwrap();
    }
    assert!(s.export_m3u8(p.id, &d.path().join("export.m3u8")).is_err());
    for n in 0..100 {
        assert_eq!(
            std::fs::read_to_string(
                d.path()
                    .join(format!(".reson-m3u8-{}-{n}.tmp", std::process::id()))
            )
            .unwrap(),
            "existing"
        );
    }
}

#[test]
fn missing_leaf_under_a_symlink_keeps_the_recoverable_physical_parent() {
    let d = tempfile::tempdir().unwrap();
    let base = d.path().join("base");
    let target = d.path().join("target/child");
    std::fs::create_dir_all(&base).unwrap();
    std::fs::create_dir_all(&target).unwrap();
    std::os::unix::fs::symlink(&target, base.join("linked")).unwrap();
    let source = base.join("list.m3u8");
    std::fs::write(&source, "linked/../missing.wav\n").unwrap();
    let mut s = LibraryStore::open(&d.path().join("db")).unwrap();
    let (p, _) = s.import_m3u8(&source, "Missing").unwrap();
    let expected = d
        .path()
        .join("target")
        .canonicalize()
        .unwrap()
        .join("missing.wav");
    assert_eq!(
        s.playlist_entries(p.id, 0, 500).unwrap()[0].track.path,
        expected.to_str().unwrap()
    );
}
