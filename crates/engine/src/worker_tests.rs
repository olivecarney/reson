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
        if path == Path::new("bad") {
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
