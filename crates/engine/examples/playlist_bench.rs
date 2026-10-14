use reson_engine::library::{LibraryStore, Sort};
use std::{path::Path, time::Instant};
fn main() {
    let root = std::env::args().nth(1).expect("fixture database directory");
    for count in [270, 5000, 25000] {
        let path = Path::new(&root).join(format!("{count}.db"));
        let before = std::fs::metadata(&path).unwrap().len();
        let mut store = LibraryStore::open(&path).unwrap();
        let playlist = store.create_playlist("Benchmark").unwrap();
        let mut ids = Vec::new();
        let mut offset = 0;
        loop {
            let page = store.query("", Sort::Title, false, offset, 500).unwrap();
            let n = page.len();
            ids.extend(page.iter().map(|t| t.id));
            if n < 500 {
                break;
            }
            offset += 500;
        }
        for chunk in ids.chunks(1000) {
            let position = store.playlist_count(playlist.id).unwrap();
            store
                .add_playlist_tracks(playlist.id, chunk, position)
                .unwrap();
        }
        let mut queries = Vec::new();
        let mut moves = Vec::new();
        let entries = store.playlist_entries(playlist.id, 0, 500).unwrap();
        let selected = [entries[0].id, entries[2].id, entries[4].id];
        for n in 0..30 {
            let start = Instant::now();
            std::hint::black_box(
                store
                    .playlist_entries(playlist.id, ((n * 499) % count) as u32, 500)
                    .unwrap(),
            );
            queries.push(start.elapsed().as_secs_f64() * 1000.0);
            let start = Instant::now();
            store
                .move_playlist_entries(
                    playlist.id,
                    &selected,
                    if n % 2 == 0 { count as u32 } else { 0 },
                )
                .unwrap();
            moves.push(start.elapsed().as_secs_f64() * 1000.0);
        }
        queries.sort_by(f64::total_cmp);
        moves.sort_by(f64::total_cmp);
        drop(store);
        let after = std::fs::metadata(&path).unwrap().len();
        println!("PLAYLIST count={count} query_median_ms={:.4} query_p95_ms={:.4} move_median_ms={:.4} move_p95_ms={:.4} before_bytes={before} after_bytes={after} delta_bytes={}",queries[15],queries[28],moves[15],moves[28],after-before);
    }
}
