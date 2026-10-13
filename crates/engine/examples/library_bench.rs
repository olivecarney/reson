use reson_engine::library::{LibraryStore, Sort, Track};
use std::time::Instant;
fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}
fn main() {
    let root = std::env::args().nth(1).expect("output directory");
    std::fs::create_dir_all(&root).unwrap();
    for count in [270, 5000, 25000] {
        let path = std::path::Path::new(&root).join(format!("{count}.db"));
        let mut store = LibraryStore::open(&path).unwrap();
        let start = Instant::now();
        for n in 0..count {
            store
                .upsert(&Track {
                    path: format!("/synthetic/music/track-{n:05}.flac"),
                    title: format!("Track {n:05}"),
                    artist: Some(format!("Artist {}", n % 100)),
                    album: Some(format!("Album {}", n % 250)),
                    genre: Some("Electronic".into()),
                    duration: Some(180.0),
                    sample_rate: Some(44100),
                    channels: Some(2),
                    bit_depth: Some(16),
                    format: "FLAC".into(),
                    bpm: Some(120.0),
                    key: Some("8A".into()),
                    size: 25000000,
                    modified: 1,
                    imported: 1,
                    ..Track::default()
                })
                .unwrap();
        }
        let insert_ms = start.elapsed().as_secs_f64() * 1000.0;
        drop(store);
        let start = Instant::now();
        let store = LibraryStore::open(&path).unwrap();
        let first = store.query("", Sort::Title, false, 0, 500).unwrap();
        let reopen_ms = start.elapsed().as_secs_f64() * 1000.0;
        for (name, search, sort) in [
            ("browse", "", Sort::Title),
            ("search", "Artist 42", Sort::Title),
            ("sort", "", Sort::Bpm),
        ] {
            let mut timings = Vec::new();
            for _ in 0..30 {
                let start = Instant::now();
                let rows = store.query(search, sort, false, 0, 500).unwrap();
                std::hint::black_box(rows);
                timings.push(start.elapsed().as_secs_f64() * 1000.0);
            }
            println!("count={count} {name}_median_ms={:.4}", median(timings));
        }
        let start = Instant::now();
        let mut offset = 0;
        loop {
            let rows = store.query("", Sort::Title, false, offset, 500).unwrap();
            let len = rows.len();
            offset += len as u32;
            if len < 500 {
                break;
            }
        }
        println!("count={count} seed_ms={insert_ms:.3} reopen_first_page_ms={reopen_ms:.3} all_pages_ms={:.3} first_rows={}",start.elapsed().as_secs_f64()*1000.0,first.len());
        drop(store);
        println!(
            "count={count} database_bytes={}",
            std::fs::metadata(path).unwrap().len()
        );
    }
    let music = std::path::Path::new(&root).join("import270");
    std::fs::create_dir_all(&music).unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    for n in 0..270 {
        let path = music.join(format!("{n}.wav"));
        if !path.exists() {
            std::fs::copy(&fixture, path).unwrap();
        }
    }
    let mut store = LibraryStore::open(&std::path::Path::new(&root).join("import.db")).unwrap();
    let cancel = std::sync::atomic::AtomicBool::new(false);
    for name in ["import", "rescan"] {
        let start = Instant::now();
        let summary = store.scan(&music, &cancel, |_| {}).unwrap();
        println!(
            "{name}270_ms={:.3} indexed={}",
            start.elapsed().as_secs_f64() * 1000.0,
            summary.indexed
        );
    }
}
