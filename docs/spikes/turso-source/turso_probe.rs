//! Isolated local database spike; never touches user library data.
use std::time::Instant;
fn main() {
    let path = std::env::args().nth(1).expect("temporary database path");
    let start = Instant::now();
    pollster::block_on(async {
        let db = turso::Builder::new_local(&path).build().await.unwrap();
        let conn = db.connect().unwrap();
        conn.execute(
            "CREATE TABLE IF NOT EXISTS probe(id INTEGER PRIMARY KEY, title TEXT)",
            (),
        )
        .await
        .unwrap();
        let mut rows = conn.query("SELECT COUNT(*) FROM probe", ()).await.unwrap();
        assert_eq!(
            rows.next().await.unwrap().unwrap().get::<i64>(0).unwrap(),
            0
        );
    });
    println!("open_schema_query_us={}", start.elapsed().as_micros());
}
