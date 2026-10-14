use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};
struct Fake {
    drops: Arc<AtomicUsize>,
    active: bool,
    position: f64,
}
impl Backend for Fake {
    fn seek(&mut self, _path: &Path, _seconds: f64, _paused: bool) -> Result<(), EngineError> {
        self.position = _seconds;
        Ok(())
    }
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
        self.position = 0.0;
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
        Ok((self.position, false))
    }
}
fn engine() -> (Engine, Arc<AtomicUsize>) {
    let drops = Arc::new(AtomicUsize::new(0));
    let copy = drops.clone();
    (
        Engine::with_backend(move || Fake {
            drops: copy,
            active: false,
            position: 0.0,
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

#[test]
fn output_callback_preserves_native_error_details_and_stage() {
    let (mut callback, events) = output_events();
    let mut backend = RodioBackend {
        output_events: Some(events),
        ..Default::default()
    };
    callback(rodio::cpal::Error::with_message(
        rodio::cpal::ErrorKind::BackendError,
        "CoreAudio OSStatus -50: fixture detail",
    ));
    let error = backend.poll().unwrap_err().to_string();
    assert!(error.contains("callback"));
    assert!(error.contains("BackendError"));
    assert!(error.contains("OSStatus -50: fixture detail"));
    assert!(error.contains("Play"));
}

#[test]
fn nonfatal_output_events_are_visible_without_failing_playback() {
    for kind in [
        rodio::cpal::ErrorKind::DeviceChanged,
        rodio::cpal::ErrorKind::Xrun,
        rodio::cpal::ErrorKind::RealtimeDenied,
    ] {
        let (mut callback, events) = output_events();
        let mut backend = RodioBackend {
            output_events: Some(events),
            ..Default::default()
        };
        callback(rodio::cpal::Error::with_message(
            kind,
            "fixture notification",
        ));
        assert!(
            backend.poll().is_ok(),
            "{kind:?} is not a fatal stream error"
        );
        let notice = backend.take_output_notice().unwrap();
        assert!(notice.contains("fixture notification"));
        assert!(notice.contains(&format!("{kind:?}")));
        assert!(backend.take_output_notice().is_none());
    }
}
#[test]
fn notice_flood_cannot_hide_fatal_error_or_cross_stream_lifetimes() {
    let (mut old_callback, old_events) = output_events();
    drop(old_events);
    let (mut callback, events) = output_events();
    let mut backend = RodioBackend {
        output_events: Some(events),
        ..Default::default()
    };
    old_callback(rodio::cpal::Error::with_message(
        rodio::cpal::ErrorKind::DeviceNotAvailable,
        "stale old stream",
    ));
    assert!(backend.poll().is_ok());
    for _ in 0..100 {
        callback(rodio::cpal::ErrorKind::DeviceChanged.into());
    }
    callback(rodio::cpal::Error::with_message(
        rodio::cpal::ErrorKind::DeviceNotAvailable,
        "fixture disconnected",
    ));
    let error = backend.poll().unwrap_err().to_string();
    assert!(error.contains("DeviceNotAvailable"));
    assert!(error.contains("fixture disconnected"));
    backend.stop();
    assert!(backend.output_events.is_none());
}

#[test]
fn worker_keeps_rerouted_stream_active_and_cleans_up_real_failures() {
    struct CallbackBackend {
        output: RodioBackend,
        active: bool,
        drops: Arc<AtomicUsize>,
    }
    impl Backend for CallbackBackend {
        fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError> {
            self.active = true;
            Ok(Snapshot {
                path: path.to_string_lossy().into(),
                title: "fixture".into(),
                ..Default::default()
            })
        }
        fn play(&mut self) {}
        fn pause(&mut self) {}
        fn stop(&mut self) {
            if self.active {
                self.drops.fetch_add(1, Ordering::SeqCst);
                self.active = false;
                self.output.stop();
            }
        }
        fn poll(&mut self) -> Result<(f64, bool), EngineError> {
            self.output.poll()?;
            Ok((4.0, false))
        }
        fn take_output_notice(&mut self) -> Option<String> {
            self.output.take_output_notice()
        }
    }
    let (mut callback, events) = output_events();
    let drops = Arc::new(AtomicUsize::new(0));
    let copy = drops.clone();
    let mut engine = Engine::with_backend(move || CallbackBackend {
        output: RodioBackend {
            output_events: Some(events),
            ..Default::default()
        },
        active: false,
        drops: copy,
    })
    .unwrap();
    engine.send(Command::Load("fixture".into())).unwrap();
    wait(&engine, PlaybackState::Playing);
    callback(rodio::cpal::Error::with_message(
        rodio::cpal::ErrorKind::DeviceChanged,
        "default output device changed",
    ));
    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    while engine.snapshot().output_notice.is_none() {
        assert!(std::time::Instant::now() < deadline);
        thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(engine.snapshot().state, PlaybackState::Playing);
    assert!(engine.snapshot().error.is_none());
    assert_eq!(drops.load(Ordering::SeqCst), 0);
    engine.send(Command::Pause).unwrap();
    wait(&engine, PlaybackState::Paused);
    callback(rodio::cpal::Error::with_message(
        rodio::cpal::ErrorKind::DeviceNotAvailable,
        "fixture disconnected",
    ));
    wait(&engine, PlaybackState::Error);
    assert!(engine
        .snapshot()
        .error
        .unwrap()
        .contains("fixture disconnected"));
    assert_eq!(drops.load(Ordering::SeqCst), 1);
    engine.send(Command::Load("recovered".into())).unwrap();
    wait(&engine, PlaybackState::Playing);
    assert!(engine.snapshot().output_notice.is_none());
    assert!(engine.snapshot().error.is_none());
    engine.shutdown().unwrap();
    assert_eq!(drops.load(Ordering::SeqCst), 2);
}

#[test]
fn eof_is_distinct_from_stop_and_output_failure_and_replay_has_new_generation() {
    struct End {
        fail: bool,
    }
    impl Backend for End {
        fn load(&mut self, p: &Path) -> Result<Snapshot, EngineError> {
            self.fail = p == Path::new("fail");
            Ok(Snapshot {
                path: p.to_string_lossy().into(),
                ..Default::default()
            })
        }
        fn play(&mut self) {}
        fn pause(&mut self) {}
        fn stop(&mut self) {}
        fn poll(&mut self) -> Result<(f64, bool), EngineError> {
            if self.fail {
                Err(EngineError::Output("fatal".into()))
            } else {
                Ok((1.0, true))
            }
        }
    }
    let mut e = Engine::with_backend(|| End { fail: false }).unwrap();
    e.send(Command::Load("end".into())).unwrap();
    wait(&e, PlaybackState::Ended);
    let generation = e.snapshot().generation;
    e.send(Command::Play).unwrap();
    wait(&e, PlaybackState::Playing);
    assert!(
        e.snapshot().generation > generation,
        "replaying must fence the old EOF"
    );
    e.send(Command::Stop).unwrap();
    wait(&e, PlaybackState::Stopped);
    thread::sleep(Duration::from_millis(150));
    assert_eq!(e.snapshot().state, PlaybackState::Stopped);
    e.send(Command::Load("fail".into())).unwrap();
    wait(&e, PlaybackState::Error);
    assert_eq!(e.snapshot().failure_kind.as_deref(), Some("output"));
    e.shutdown().unwrap();
}

#[test]
fn seek_is_generation_fenced_and_paused_position_is_preserved() {
    let (mut e, _) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    let generation = e.snapshot().generation;
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    e.send(Command::Seek {
        seconds: 12.5,
        generation,
    })
    .unwrap();
    thread::sleep(Duration::from_millis(20));
    assert_eq!(e.snapshot().position_seconds, 12.5);
    assert_eq!(e.snapshot().state, PlaybackState::Paused);
    e.send(Command::Load("new".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Seek {
        seconds: 8.0,
        generation,
    })
    .unwrap();
    thread::sleep(Duration::from_millis(20));
    assert_eq!(e.snapshot().position_seconds, 0.0);
    assert!(e
        .send(Command::Seek {
            seconds: f64::NAN,
            generation: e.snapshot().generation
        })
        .is_err());
    e.shutdown().unwrap();
}

#[test]
fn gain_bounds_mute_restore_and_track_replacement() {
    let (mut e, _) = engine();
    e.send(Command::Volume(0.4)).unwrap();
    e.send(Command::Mute(true)).unwrap();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    assert_eq!(e.snapshot().volume, 0.4);
    assert!(e.snapshot().muted);
    e.send(Command::Mute(false)).unwrap();
    thread::sleep(Duration::from_millis(20));
    assert!(!e.snapshot().muted);
    assert_eq!(e.snapshot().volume, 0.4);
    e.send(Command::Volume(2.0)).unwrap();
    thread::sleep(Duration::from_millis(20));
    assert_eq!(e.snapshot().volume, 1.0);
    assert!(e.send(Command::Volume(f32::INFINITY)).is_err());
    e.shutdown().unwrap();
}

#[test]
fn failed_seek_leaves_playback_recoverable_without_eof() {
    let (mut e, _, _, _) = monitored();
    e.send(Command::Load("a".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    let pos = e.snapshot().position_seconds;
    e.send(Command::Seek {
        seconds: 6.0,
        generation: e.snapshot().generation,
    })
    .unwrap();
    thread::sleep(Duration::from_millis(20));
    assert_eq!(e.snapshot().state, PlaybackState::Paused);
    assert_eq!(e.snapshot().position_seconds, pos);
    assert!(e.snapshot().operation_error.unwrap().contains("Seeking"));
    e.shutdown().unwrap();
}

#[test]
fn selected_device_rebuild_preserves_paused_position_and_gain() {
    let (mut e, drops) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    e.send(Command::Seek {
        seconds: 3.0,
        generation: e.snapshot().generation,
    })
    .unwrap();
    e.send(Command::Volume(0.3)).unwrap();
    e.send(Command::Device(Some("fixture-device".into())))
        .unwrap();
    thread::sleep(Duration::from_millis(30));
    let s = e.snapshot();
    assert_eq!(s.state, PlaybackState::Paused);
    assert_eq!(s.position_seconds, 3.0);
    assert_eq!(s.volume, 0.3);
    assert_eq!(s.preferred_device.as_deref(), Some("fixture-device"));
    assert_eq!(drops.load(Ordering::SeqCst), 1);
    e.shutdown().unwrap();
    assert_eq!(drops.load(Ordering::SeqCst), 2);
}

#[test]
fn in_flight_seek_cannot_publish_after_stop_or_replacement() {
    struct Seeking {
        started: mpsc::Sender<()>,
        release: mpsc::Receiver<()>,
    }
    impl Backend for Seeking {
        fn load(&mut self, p: &Path) -> Result<Snapshot, EngineError> {
            Ok(Snapshot {
                path: p.to_string_lossy().into(),
                duration_seconds: Some(20.0),
                ..Default::default()
            })
        }
        fn seek(&mut self, _: &Path, _: f64, _: bool) -> Result<(), EngineError> {
            self.started.send(()).unwrap();
            self.release.recv().unwrap();
            Ok(())
        }
        fn play(&mut self) {}
        fn pause(&mut self) {}
        fn stop(&mut self) {}
        fn poll(&mut self) -> Result<(f64, bool), EngineError> {
            Ok((0.0, false))
        }
    }
    for replace in [false, true] {
        let (tx, rx) = mpsc::channel();
        let (release, waiting) = mpsc::channel();
        let mut e = Engine::with_backend(move || Seeking {
            started: tx,
            release: waiting,
        })
        .unwrap();
        e.send(Command::Load("old".into())).unwrap();
        wait(&e, PlaybackState::Playing);
        e.send(Command::Seek {
            seconds: 10.0,
            generation: e.snapshot().generation,
        })
        .unwrap();
        rx.recv_timeout(Duration::from_secs(1)).unwrap();
        e.send(if replace {
            Command::Load("new".into())
        } else {
            Command::Stop
        })
        .unwrap();
        release.send(()).unwrap();
        wait(
            &e,
            if replace {
                PlaybackState::Playing
            } else {
                PlaybackState::Stopped
            },
        );
        assert_eq!(e.snapshot().position_seconds, 0.0);
        assert_eq!(e.snapshot().path, if replace { "new" } else { "old" });
        e.shutdown().unwrap();
        assert!(matches!(
            e.send(Command::Volume(0.5)),
            Err(EngineError::Disconnected)
        ));
    }
}

#[test]
fn repeated_device_switches_and_seek_at_end_do_not_signal_eof() {
    let (mut e, drops) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    for n in 0..40 {
        e.send(Command::Device(Some(format!("device-{n}"))))
            .unwrap();
        let sequence = e.sequence;
        let until = std::time::Instant::now() + Duration::from_secs(1);
        while e.snapshot().acknowledged < sequence {
            assert!(std::time::Instant::now() < until);
            thread::sleep(Duration::from_millis(1));
        }
        assert_eq!(e.snapshot().state, PlaybackState::Paused);
    }
    e.shutdown().unwrap();
    assert_eq!(drops.load(Ordering::SeqCst), 41);
}

#[test]
fn retired_source_cannot_mix_samples_with_seek_replacement() {
    use rodio::source::SineWave;
    let active = Arc::new(AtomicBool::new(true));
    let mut source = FencedSource {
        inner: SineWave::new(440.0),
        active: active.clone(),
    };
    assert!(source.next().is_some());
    active.store(false, Ordering::Release);
    assert_eq!(source.next(), None);
}

#[test]
fn natural_end_reports_full_duration_and_released_output() {
    let mut snapshot = Snapshot {
        duration_seconds: Some(2.0),
        position_seconds: 1.995,
        output_rate: Some(48000),
        ..Default::default()
    };
    snapshot.end();
    assert_eq!(snapshot.position_seconds, 2.0);
    assert_eq!(snapshot.output_rate, None);
}

#[test]
fn finite_seek_requests_clamp_to_source_frames_without_resuming() {
    let (mut e, _) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    {
        let mut s = lock(&e.shared);
        s.duration_seconds = Some(2.0);
        s.sample_rate = Some(48000);
    }
    for (request, expected) in [
        (-10.0, 0.0),
        (99.0, 2.0 - 1.0 / 48000.0),
        (0.000270833333, 13.0 / 48000.0),
    ] {
        e.send(Command::Seek {
            seconds: request,
            generation: e.snapshot().generation,
        })
        .unwrap();
        let sequence = e.sequence;
        let deadline = std::time::Instant::now() + Duration::from_secs(1);
        while e.snapshot().acknowledged < sequence {
            assert!(std::time::Instant::now() < deadline);
            thread::sleep(Duration::from_millis(1));
        }
        assert!((e.snapshot().position_seconds - expected).abs() < 1e-10);
        assert_eq!(e.snapshot().state, PlaybackState::Paused);
    }
    assert!(e
        .send(Command::Seek {
            seconds: f64::INFINITY,
            generation: e.snapshot().generation
        })
        .is_err());
    e.shutdown().unwrap();
}

#[test]
fn rapid_paused_seeks_publish_only_latest_accepted_request() {
    let (mut e, _) = engine();
    e.send(Command::Load("ok".into())).unwrap();
    wait(&e, PlaybackState::Playing);
    e.send(Command::Pause).unwrap();
    wait(&e, PlaybackState::Paused);
    let generation = e.snapshot().generation;
    // Hold the snapshot mutex to deterministically enqueue a complete batch before the worker can inspect it.
    let shared = e.shared.clone();
    let mut s = lock(&shared);
    for seconds in [8.0, 1.0, 6.0, 2.0] {
        e.sequence += 1;
        e.sender
            .as_ref()
            .unwrap()
            .try_send(Envelope {
                command: Command::Seek {
                    seconds,
                    generation,
                },
                sequence: e.sequence,
                generation,
            })
            .unwrap();
        s.seek_request = e.sequence;
    }
    drop(s);
    let deadline = std::time::Instant::now() + Duration::from_secs(1);
    while e.snapshot().acknowledged < e.sequence {
        assert!(std::time::Instant::now() < deadline);
        thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(e.snapshot().position_seconds, 2.0);
    assert_eq!(e.snapshot().state, PlaybackState::Paused);
    e.shutdown().unwrap();
}
