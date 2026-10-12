use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};
struct Fake {
    drops: Arc<AtomicUsize>,
    active: bool,
}
impl Backend for Fake {
    fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError> {
        if path == Path::new("panic") {
            panic!("fixture panic");
        }
        if path == Path::new("slow") {
            thread::sleep(Duration::from_millis(100));
        }
        if path == Path::new("bad") || path.extension().is_some_and(|x| x == "wav") {
            return Err(EngineError::Output("no device".into()));
        }
        self.active = true;
        Ok(Snapshot {
            path: path.to_string_lossy().into(),
            title: path.to_string_lossy().into(),
            ..Snapshot::default()
        })
    }
    fn pause(&mut self) {}
    fn play(&mut self) {}
    fn stop(&mut self) {
        if self.active {
            self.drops.fetch_add(1, Ordering::SeqCst);
            self.active = false;
        }
    }
    fn poll(&mut self) -> Result<(f64, bool), EngineError> {
        Ok((1.0, false))
    }
}
fn engine() -> (Engine, Arc<AtomicUsize>) {
    let drops = Arc::new(AtomicUsize::new(0));
    let copy = drops.clone();
    (
        Engine::with_backend(move || Fake {
            drops: copy,
            active: false,
        })
        .unwrap(),
        drops,
    )
}
fn wait(e: &Engine, state: PlaybackState) {
    let until = std::time::Instant::now() + Duration::from_secs(2);
    loop {
        if e.snapshot().state == state {
            return;
        }
        assert!(std::time::Instant::now() < until, "{:?}", e.snapshot());
        thread::sleep(Duration::from_millis(2));
    }
}
#[test]
fn fifo_load_replacement() {
    let (mut e, _) = engine();
    e.send(Command::Load("slow".into())).unwrap();
    e.send(Command::Load("new".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    assert_eq!(e.snapshot().title, "new");
    e.shutdown().unwrap();
}
#[test]
fn queue_full_returns_immediately() {
    let (mut e, _) = engine();
    e.send(Command::Load("slow".into())).unwrap();
    thread::sleep(Duration::from_millis(10));
    let mut full = false;
    for _ in 0..40 {
        if matches!(e.send(Command::Pause), Err(EngineError::QueueFull)) {
            full = true;
            break;
        }
    }
    assert!(full);
    e.shutdown().unwrap();
}
#[test]
fn output_failure_then_valid_load_recovers() {
    let (mut e, _) = engine();
    e.send(Command::Load("bad".into())).unwrap();
    wait(&e, PlaybackState::Error);
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    assert!(e.snapshot().error.is_none());
    e.shutdown().unwrap();
}
#[test]
fn stop_drops_source_and_stream() {
    let (mut e, d) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Stop).unwrap();
    wait(&e, PlaybackState::Stopped);
    assert!(d.load(Ordering::SeqCst) > 0);
    e.shutdown().unwrap();
}
#[test]
fn shutdown_during_load_joins() {
    let (mut e, _) = engine();
    e.send(Command::Load("slow".into())).unwrap();
    e.shutdown().unwrap();
    assert!(e.worker.is_none());
}
#[test]
fn worker_panic_becomes_error() {
    let (mut e, _) = engine();
    e.send(Command::Load("panic".into())).unwrap();
    wait(&e, PlaybackState::Error);
    assert!(e.snapshot().error.unwrap().contains("panic"));
    e.shutdown().unwrap();
}
#[test]
fn stopped_play_reloads_without_deadlock() {
    let (mut e, _) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Stop).unwrap();
    wait(&e, PlaybackState::Stopped);
    e.send(Command::Play).unwrap();
    wait(&e, PlaybackState::Playing);
    e.shutdown().unwrap();
}
#[test]
fn device_builder_uses_os_buffer_size() {
    let builder = configure_output(
        DeviceSinkBuilder::default().with_buffer_size(rodio::cpal::BufferSize::Fixed(2048)),
    );
    assert!(format!("{builder:?}").contains("buffer_size: Default"));
}
#[test]
fn output_failure_retains_metadata() {
    let (mut e, _) = engine();
    let p = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/pcm16-44100-1.wav");
    e.send(Command::Load(p)).unwrap();
    wait(&e, PlaybackState::Error);
    assert_eq!(e.snapshot().sample_rate, Some(44100));
    assert_eq!(e.snapshot().title, "pcm16-44100-1");
    e.shutdown().unwrap();
}
#[test]
fn in_flight_replacement_never_publishes_old_metadata() {
    struct Blocking {
        started: mpsc::Sender<()>,
        release: mpsc::Receiver<()>,
    }
    impl Backend for Blocking {
        fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError> {
            if path == Path::new("old") {
                self.started.send(()).unwrap();
                self.release.recv().unwrap();
            }
            Ok(Snapshot {
                path: path.to_string_lossy().into(),
                title: path.to_string_lossy().into(),
                ..Snapshot::default()
            })
        }
        fn play(&mut self) {}
        fn pause(&mut self) {}
        fn stop(&mut self) {}
        fn poll(&mut self) -> Result<(f64, bool), EngineError> {
            Ok((0.0, false))
        }
    }
    let (started_tx, started_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    let mut e = Engine::with_backend(move || Blocking {
        started: started_tx,
        release: release_rx,
    })
    .unwrap();
    e.send(Command::Load("old".into())).unwrap();
    started_rx.recv_timeout(Duration::from_secs(1)).unwrap();
    e.send(Command::Load("new".into())).unwrap();
    assert_eq!(e.snapshot().path, "new");
    assert!(e.snapshot().title.is_empty());
    release_tx.send(()).unwrap();
    wait(&e, PlaybackState::Playing);
    assert_eq!(e.snapshot().title, "new");
    e.shutdown().unwrap();
}
#[test]
fn commands_do_not_wait_for_backend_teardown() {
    struct SlowStop {
        active: bool,
        started: mpsc::Sender<()>,
        release: mpsc::Receiver<()>,
    }
    impl Backend for SlowStop {
        fn load(&mut self, p: &Path) -> Result<Snapshot, EngineError> {
            self.active = true;
            Ok(Snapshot {
                path: p.to_string_lossy().into(),
                title: "track".into(),
                ..Snapshot::default()
            })
        }
        fn play(&mut self) {}
        fn pause(&mut self) {}
        fn stop(&mut self) {
            if self.active {
                self.active = false;
                self.started.send(()).unwrap();
                self.release.recv().unwrap();
            }
        }
        fn poll(&mut self) -> Result<(f64, bool), EngineError> {
            Ok((0.0, false))
        }
    }
    let (started_tx, started_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    let mut e = Engine::with_backend(move || SlowStop {
        active: false,
        started: started_tx,
        release: release_rx,
    })
    .unwrap();
    e.send(Command::Load("a".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Stop).unwrap();
    started_rx.recv_timeout(Duration::from_secs(1)).unwrap();
    let (done_tx, done_rx) = mpsc::channel();
    let sender = thread::spawn(move || {
        let result = e.send(Command::Pause);
        done_tx.send(result.is_ok()).unwrap();
        e
    });
    let immediate = done_rx
        .recv_timeout(Duration::from_millis(100))
        .unwrap_or(false);
    release_tx.send(()).unwrap();
    let mut e = sender.join().unwrap();
    e.shutdown().unwrap();
    assert!(immediate, "enqueue waited for backend teardown");
}
struct Monitored {
    failed: Arc<AtomicBool>,
    polls: Arc<AtomicUsize>,
    drops: Arc<AtomicUsize>,
    active: bool,
}
impl Backend for Monitored {
    fn load(&mut self, p: &Path) -> Result<Snapshot, EngineError> {
        self.failed.store(false, Ordering::SeqCst);
        self.active = true;
        Ok(Snapshot {
            path: p.to_string_lossy().into(),
            title: "monitored".into(),
            ..Snapshot::default()
        })
    }
    fn play(&mut self) {}
    fn pause(&mut self) {}
    fn stop(&mut self) {
        if self.active {
            self.active = false;
            self.drops.fetch_add(1, Ordering::SeqCst);
        }
    }
    fn poll(&mut self) -> Result<(f64, bool), EngineError> {
        let count = self.polls.fetch_add(1, Ordering::SeqCst) + 1;
        if self.failed.load(Ordering::SeqCst) {
            return Err(EngineError::Output("paused output failed".into()));
        }
        Ok((count as f64, false))
    }
}
fn monitored() -> (Engine, Arc<AtomicBool>, Arc<AtomicUsize>, Arc<AtomicUsize>) {
    let failed = Arc::new(AtomicBool::new(false));
    let polls = Arc::new(AtomicUsize::new(0));
    let drops = Arc::new(AtomicUsize::new(0));
    let backend = Monitored {
        failed: failed.clone(),
        polls: polls.clone(),
        drops: drops.clone(),
        active: false,
    };
    (
        Engine::with_backend(move || backend).unwrap(),
        failed,
        polls,
        drops,
    )
}
#[test]
fn paused_output_failure_is_detected_and_replay_recovers() {
    let (mut e, failed, _, drops) = monitored();
    e.send(Command::Load("a".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    failed.store(true, Ordering::SeqCst);
    // Check before asserting so the old implementation always shuts down on failure.
    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    while e.snapshot().state != PlaybackState::Error && std::time::Instant::now() < deadline {
        thread::sleep(Duration::from_millis(5));
    }
    let detected = e.snapshot().state == PlaybackState::Error;
    if !detected {
        e.shutdown().unwrap();
        assert!(detected, "paused backend failure was not observed");
        return;
    }
    e.send(Command::Play).unwrap();
    wait(&e, PlaybackState::Playing);
    assert!(e.snapshot().error.is_none());
    assert!(drops.load(Ordering::SeqCst) > 0);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    failed.store(true, Ordering::SeqCst);
    wait(&e, PlaybackState::Error);
    e.send(Command::Load("b".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    assert_eq!(e.snapshot().path, "b");
    e.shutdown().unwrap();
}
#[test]
fn paused_checks_are_modest_and_position_is_frozen() {
    let (mut e, _, polls, _) = monitored();
    e.send(Command::Load("a".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    thread::sleep(Duration::from_millis(120));
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    let position = e.snapshot().position_seconds;
    let before = polls.load(Ordering::SeqCst);
    thread::sleep(Duration::from_millis(1150));
    let checks = polls.load(Ordering::SeqCst) - before;
    let after = e.snapshot().position_seconds;
    e.shutdown().unwrap();
    assert!((1..=4).contains(&checks), "paused checks: {checks}");
    assert_eq!(after, position);
}
#[test]
fn no_stream_means_no_backend_polling() {
    let (mut e, _, polls, _) = monitored();
    thread::sleep(Duration::from_millis(650));
    assert_eq!(polls.load(Ordering::SeqCst), 0);
    e.send(Command::Load("a".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Stop).unwrap();
    wait(&e, PlaybackState::Stopped);
    let before = polls.load(Ordering::SeqCst);
    thread::sleep(Duration::from_millis(650));
    assert_eq!(polls.load(Ordering::SeqCst), before);
    e.shutdown().unwrap();
}
