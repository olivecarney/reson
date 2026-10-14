//! Comparable headless playback CPU/RSS observation; pass an original silent 8-second fixture.
use reson_engine::{
    playback::Engine,
    state::{Command, PlaybackState},
};
use std::{
    thread,
    time::{Duration, Instant},
};
fn sample() -> (f64, u64) {
    let pid = std::process::id().to_string();
    let out = std::process::Command::new("ps")
        .args(["-p", &pid, "-o", "time=,rss="])
        .output()
        .unwrap();
    let text = String::from_utf8(out.stdout).unwrap();
    let fields: Vec<_> = text.split_whitespace().collect();
    let cpu = fields[0]
        .split(':')
        .fold(0.0, |sum, p| sum * 60.0 + p.parse::<f64>().unwrap());
    (cpu, fields[1].parse().unwrap())
}
fn main() {
    let path = std::env::args().nth(1).expect("silent fixture path");
    let mut engine = Engine::new().unwrap();
    engine.send(Command::Load(path.into())).unwrap();
    let until = Instant::now() + Duration::from_secs(5);
    while engine.snapshot().state != PlaybackState::Playing {
        assert!(Instant::now() < until);
        assert_ne!(engine.snapshot().state, PlaybackState::Error);
        thread::sleep(Duration::from_millis(2));
    }
    thread::sleep(Duration::from_millis(300));
    let before = sample().0;
    let start = Instant::now();
    thread::sleep(Duration::from_secs(3));
    let after = sample();
    println!(
        "active_cpu_percent={:.3} rss_kib={} position={:.3}",
        (after.0 - before) / start.elapsed().as_secs_f64() * 100.0,
        after.1,
        engine.snapshot().position_seconds
    );
    engine.shutdown().unwrap();
}
