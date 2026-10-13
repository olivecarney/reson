fn main() {
    pollster::block_on(async {
        for count in [270, 5000, 25000] {
            let source = format!("build/library-bench/{count}.db");
            let path = format!("build/turso-bench/{count}.db");
            std::fs::copy(source, &path).unwrap();
            let db = turso::Builder::new_local(&path).build().await.unwrap();
            let conn = db.connect().unwrap();
            for (name, search, column) in [
                ("browse", "", "title"),
                ("search", "Artist 42", "title"),
                ("sort", "", "bpm"),
            ] {
                let sql=format!("SELECT id,path,title,artist,album,genre,duration,sample_rate,channels,bit_depth,format,bpm,musical_key,size,modified,imported,missing FROM tracks WHERE title LIKE ?1 ESCAPE '\\' OR artist LIKE ?1 ESCAPE '\\' OR album LIKE ?1 ESCAPE '\\' OR genre LIKE ?1 ESCAPE '\\' OR path LIKE ?1 ESCAPE '\\' ORDER BY {column} COLLATE NOCASE ASC,id ASC LIMIT ?2 OFFSET ?3");
                let mut times = Vec::new();
                for _ in 0..30 {
                    let start = std::time::Instant::now();
                    let mut rows = conn
                        .query(&sql, (format!("%{search}%"), 500, 0))
                        .await
                        .unwrap();
                    while let Some(row) = rows.next().await.unwrap() {
                        for i in [1, 2, 3, 4, 5, 10, 12] {
                            std::hint::black_box(row.get::<String>(i).unwrap());
                        }
                        for i in [0, 7, 8, 9, 13, 14, 15, 16] {
                            std::hint::black_box(row.get::<i64>(i).unwrap());
                        }
                        for i in [6, 11] {
                            std::hint::black_box(row.get::<f64>(i).unwrap());
                        }
                    }
                    times.push(start.elapsed().as_secs_f64() * 1000.0);
                }
                times.sort_by(f64::total_cmp);
                println!(
                    "count={count} {name}_median_ms={:.4}",
                    times[times.len() / 2]
                );
            }
        }
    });
}
