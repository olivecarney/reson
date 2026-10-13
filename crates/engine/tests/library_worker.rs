use reson_engine::library_worker::Library;
#[test]
fn worker_import_query_cancel_and_reopen() {
    let d = tempfile::tempdir().unwrap();
    let db = d.path().join("library.db");
    let music = d.path().join("music");
    std::fs::create_dir(&music).unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    for i in 0..100 {
        std::fs::copy(&fixture, music.join(format!("{i}.wav"))).unwrap();
    }
    let mut library = Library::new(db.clone()).unwrap();
    let response = library
        .request(serde_json::json!({"op":"import","path":music}))
        .unwrap();
    assert!(response.get("error").is_none());
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    loop {
        let status = library.request(serde_json::json!({"op":"status"})).unwrap();
        if status["busy"] == false {
            break;
        }
        assert!(std::time::Instant::now() < deadline);
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    let response = library
        .request(serde_json::json!({"op":"query","limit":500}))
        .unwrap();
    assert_eq!(response["tracks"].as_array().unwrap().len(), 100);
    assert!(library
        .request(serde_json::json!({"op":"query","sort":99}))
        .unwrap()
        .get("error")
        .is_some());
    library.shutdown();
    let mut library = Library::new(db).unwrap();
    assert_eq!(
        library
            .request(serde_json::json!({"op":"query","limit":500}))
            .unwrap()["tracks"]
            .as_array()
            .unwrap()
            .len(),
        100
    );
    library.shutdown();
    assert!(library.request(serde_json::json!({"op":"status"})).is_err());
}
