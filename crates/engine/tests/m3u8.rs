use reson_engine::library::{LibraryStore, Track};
#[test]
fn unicode_relative_absolute_duplicates_missing_and_roundtrip() {
    let d = tempfile::tempdir().unwrap();
    let source = d.path().join("list.m3u8");
    let music = d.path().join("音 楽.wav");
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
        path: d.path().join("missing.wav").to_str().unwrap().into(),
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
