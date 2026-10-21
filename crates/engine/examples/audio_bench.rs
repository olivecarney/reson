//! Opt-in real CoreAudio benchmark; only use generate-audio-fixtures.py's silent sources.
use reson_engine::{
    playback::{output_devices, prepared_decoder, Engine},
    state::{Command, PlaybackState, Snapshot},
};
use std::{
    path::Path,
    thread,
    time::{Duration, Instant},
};
fn acknowledged(engine: &Engine, sequence: u64) -> Snapshot {
    let until = Instant::now() + Duration::from_secs(10);
    loop {
        let s = engine.snapshot();
        if s.acknowledged >= sequence {
            assert_ne!(s.state, PlaybackState::Error, "{:?}", s.error);
            return s;
        }
        assert!(Instant::now() < until);
        thread::sleep(Duration::from_millis(1));
    }
}
fn timed(engine: &mut Engine, sequence: &mut u64, command: Command) -> (f64, Snapshot) {
    let start = Instant::now();
    engine.send(command).unwrap();
    *sequence += 1;
    let s = acknowledged(engine, *sequence);
    (start.elapsed().as_secs_f64() * 1000.0, s)
}
fn report(name: &str, mut times: Vec<f64>) {
    times.sort_by(f64::total_cmp);
    println!(
        "{name}: median_ms={:.3} p95_ms={:.3} n={}",
        times[times.len() / 2],
        times[times.len() * 95 / 100],
        times.len()
    );
}
fn resources(label: &str) {
    let pid = std::process::id().to_string();
    for (kind, cmd, args) in [
        ("threads", "ps", vec!["-M", "-p", &pid]),
        ("fds", "lsof", vec!["-n", "-P", "-p", &pid]),
    ] {
        let out = std::process::Command::new(cmd).args(args).output().unwrap();
        println!(
            "{label} {kind}={}",
            String::from_utf8_lossy(&out.stdout)
                .lines()
                .count()
                .saturating_sub(1)
        );
    }
}
fn main() {
    let root = std::env::args()
        .nth(1)
        .expect("synthetic fixture directory");
    let mut engine = Engine::new().unwrap();
    let mut seq = 0;
    timed(&mut engine, &mut seq, Command::Mute(true));
    let devices = output_devices().unwrap();
    println!("devices={devices:?}");
    for ext in ["wav", "flac"] {
        let path = Path::new(&root).join(format!("silent.{ext}"));
        let mut decoder = Vec::new();
        let mut seek = Vec::new();
        for n in 0..30 {
            let t = Instant::now();
            drop(prepared_decoder(&path, 0.0).unwrap());
            decoder.push(t.elapsed().as_secs_f64() * 1000.0);
            let t = Instant::now();
            drop(prepared_decoder(&path, 1.0 + (n % 6) as f64).unwrap());
            seek.push(t.elapsed().as_secs_f64() * 1000.0);
        }
        report(&format!("{ext}_decoder_start"), decoder);
        report(&format!("{ext}_decoder_seek"), seek);
        timed(&mut engine, &mut seq, Command::Load(path));
        timed(&mut engine, &mut seq, Command::Pause);
        let mut seeks = Vec::new();
        for n in 0..30 {
            let generation = engine.snapshot().generation;
            seeks.push(
                timed(
                    &mut engine,
                    &mut seq,
                    Command::Seek {
                        seconds: 1.0 + (n % 6) as f64,
                        generation,
                    },
                )
                .0,
            );
        }
        report(&format!("{ext}_worker_seek_ack"), seeks);
    }
    thread::sleep(Duration::from_millis(200));
    resources("active_before");
    let mut gain = Vec::new();
    let mut enumerate = Vec::new();
    let mut switches = Vec::new();
    for n in 0..30 {
        gain.push(timed(&mut engine, &mut seq, Command::Volume(n as f32 / 30.0)).0);
    }
    for _ in 0..10 {
        let t = Instant::now();
        output_devices().unwrap();
        enumerate.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    for n in 0..30 {
        switches.push(
            timed(
                &mut engine,
                &mut seq,
                Command::Device(if n % 2 == 0 {
                    Some(devices[0].id.clone())
                } else {
                    None
                }),
            )
            .0,
        );
    }
    thread::sleep(Duration::from_millis(200));
    resources("active_after");
    for n in 0..30 {
        timed(
            &mut engine,
            &mut seq,
            Command::Device(if n % 2 == 0 {
                Some(devices[0].id.clone())
            } else {
                None
            }),
        );
    }
    thread::sleep(Duration::from_millis(200));
    resources("active_after_60");
    report("gain_ack", gain);
    report("enumerate", enumerate);
    report("switch_ack", switches);
    timed(&mut engine, &mut seq, Command::Stop);
    engine.shutdown().unwrap();
    thread::sleep(Duration::from_millis(100));
    resources("closed");
    let mut engine = Engine::new().unwrap();
    let mut seq = 0;
    timed(&mut engine, &mut seq, Command::Mute(true));
    for (label, next) in [
        ("same_format_eof_to_load_ack", "boundary-b.flac"),
        ("mixed_format_eof_to_load_ack", "boundary-48k.wav"),
    ] {
        let mut gaps = Vec::new();
        let mut eof_delays = Vec::new();
        for _ in 0..12 {
            let (_, s) = timed(
                &mut engine,
                &mut seq,
                Command::Load(Path::new(&root).join("boundary-a.flac")),
            );
            let started = Instant::now();
            let until = started + Duration::from_secs(5);
            while engine.snapshot().state != PlaybackState::Ended {
                assert!(Instant::now() < until);
                thread::sleep(Duration::from_millis(1));
            }
            eof_delays
                .push((started.elapsed().as_secs_f64() - s.duration_seconds.unwrap()) * 1000.0);
            gaps.push(
                timed(
                    &mut engine,
                    &mut seq,
                    Command::Load(Path::new(&root).join(next)),
                )
                .0,
            );
            timed(&mut engine, &mut seq, Command::Stop);
        }
        report(label, gaps);
        report(
            &format!("{label}_eof_observation_after_source_duration"),
            eof_delays,
        );
    }
    engine.shutdown().unwrap();
    let mut build = Vec::new();
    let mut teardown = Vec::new();
    for _ in 0..15 {
        let t = Instant::now();
        let mut stream = rodio::DeviceSinkBuilder::from_default_device()
            .unwrap()
            .with_buffer_size(rodio::cpal::BufferSize::Default)
            .open_stream()
            .unwrap();
        stream.log_on_drop(false);
        build.push(t.elapsed().as_secs_f64() * 1000.0);
        let t = Instant::now();
        drop(stream);
        teardown.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    report("stream_open", build);
    report("stream_drop", teardown);
}
