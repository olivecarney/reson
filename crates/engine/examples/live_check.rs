//! Explicit live-device smoke check. Does not establish audible or bit-perfect output.
use reson_engine::{
    playback::Engine,
    state::{Command, PlaybackState},
};
use std::{
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};
fn wait(engine: &Engine, state: PlaybackState) {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let s = engine.snapshot();
        assert_ne!(s.state, PlaybackState::Error, "{:?}", s.error);
        if s.state == state {
            return;
        }
        assert!(Instant::now() < deadline, "Timed out: {s:?}");
        thread::sleep(Duration::from_millis(5));
    }
}
fn main() {
    let paths: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    assert!(
        !paths.is_empty(),
        "Usage: cargo run --release -p reson-engine --example live_check -- long.wav long.flac"
    );
    let mut engine = Engine::new().unwrap();
    for path in paths {
        engine.send(Command::Load(path)).unwrap();
        wait(&engine, PlaybackState::Playing);
        println!("Configured playback: {:?}", engine.snapshot());
        thread::sleep(Duration::from_millis(400));
        engine.send(Command::Pause).unwrap();
        wait(&engine, PlaybackState::Paused);
        let position = engine.snapshot().position_seconds;
        thread::sleep(Duration::from_millis(100));
        assert_eq!(engine.snapshot().position_seconds, position);
        engine.send(Command::Play).unwrap();
        wait(&engine, PlaybackState::Playing);
        engine.send(Command::Stop).unwrap();
        wait(&engine, PlaybackState::Stopped);
        assert_eq!(engine.snapshot().position_seconds, 0.0);
        engine.send(Command::Play).unwrap();
        wait(&engine, PlaybackState::Playing);
        engine.send(Command::Stop).unwrap();
        wait(&engine, PlaybackState::Stopped);
        println!("Live pause/resume/stop/restart passed");
    }
    let short =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/pcm16-44100-1.flac");
    engine.send(Command::Load(short)).unwrap();
    wait(&engine, PlaybackState::Ended);
    engine
        .send(Command::Load("/missing/reson.wav".into()))
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    while engine.snapshot().state != PlaybackState::Error {
        assert!(Instant::now() < deadline);
        thread::sleep(Duration::from_millis(5));
    }
    let valid =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/pcm24-48000-2.wav");
    engine.send(Command::Load(valid)).unwrap();
    wait(&engine, PlaybackState::Ended);
    engine.shutdown().unwrap();
    println!("Live EOF/error recovery/shutdown passed");
}
