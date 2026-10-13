use crate::state::{Command, PlaybackState, Snapshot};
use rodio::{Decoder, DeviceSinkBuilder, MixerDeviceSink, Player};
use std::{
    fs::File,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender, TrySendError},
        Arc, Mutex,
    },
    thread::{self, JoinHandle},
    time::Duration,
};
use symphonia::core::{
    formats::FormatOptions, io::MediaSourceStream, meta::MetadataOptions, probe::Hint,
};

#[derive(Debug)]
pub enum EngineError {
    InvalidInput(String),
    Io(String),
    Decode(String),
    Output(String),
    QueueFull,
    Disconnected,
    WorkerPanic,
}
impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidInput(s) | Self::Io(s) | Self::Decode(s) | Self::Output(s) => {
                f.write_str(s)
            }
            Self::QueueFull => f.write_str("Playback command queue is full; try again"),
            Self::Disconnected => f.write_str("Playback worker is unavailable"),
            Self::WorkerPanic => f.write_str("Playback worker panic"),
        }
    }
}
impl std::error::Error for EngineError {}
pub type TrackInfo = Snapshot;
pub fn probe(path: &Path) -> Result<TrackInfo, EngineError> {
    let ext = path
        .extension()
        .and_then(|x| x.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !matches!(ext.as_str(), "wav" | "flac") {
        return Err(EngineError::InvalidInput(
            "Choose a FLAC or PCM WAV file".into(),
        ));
    }
    let file = File::open(path).map_err(|e| EngineError::Io(e.to_string()))?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    hint.with_extension(&ext);
    let mut probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions {
                limit_visual_bytes: symphonia::core::meta::Limit::Maximum(0),
                ..MetadataOptions::default()
            },
        )
        .map_err(|e| EngineError::Decode(e.to_string()))?;
    let track = probed
        .format
        .default_track()
        .ok_or_else(|| EngineError::Decode("No audio track".into()))?;
    let p = &track.codec_params;
    let mut info = Snapshot {
        path: path.to_string_lossy().into(),
        title: path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into(),
        sample_rate: p.sample_rate,
        channels: p.channels.map(|c| c.count() as u16),
        bit_depth: p.bits_per_sample.map(|b| b as u16),
        duration_seconds: p.time_base.zip(p.n_frames).map(|(b, n)| {
            let t = b.calc_time(n);
            t.seconds as f64 + t.frac
        }),
        format: ext.to_uppercase(),
        ..Snapshot::default()
    };
    use symphonia::core::meta::StandardTagKey;
    if let Some(meta) = probed.format.metadata().current() {
        for tag in meta.tags() {
            match tag.std_key {
                Some(StandardTagKey::TrackTitle) => {
                    info.title = tag
                        .value
                        .to_string()
                        .trim_end_matches('\0')
                        .trim()
                        .to_owned()
                }
                Some(StandardTagKey::Artist) => {
                    info.artist = Some(
                        tag.value
                            .to_string()
                            .trim_end_matches('\0')
                            .trim()
                            .to_owned(),
                    )
                }
                Some(StandardTagKey::Album) => {
                    info.album = Some(
                        tag.value
                            .to_string()
                            .trim_end_matches('\0')
                            .trim()
                            .to_owned(),
                    )
                }
                _ => {}
            }
        }
    }
    if info.title.is_empty() {
        info.title = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
    }
    info.artist = info.artist.filter(|text| !text.is_empty());
    info.album = info.album.filter(|text| !text.is_empty());
    Ok(info)
}
trait Backend {
    fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError>;
    fn play(&mut self);
    fn pause(&mut self);
    fn stop(&mut self);
    fn poll(&mut self) -> Result<(f64, bool), EngineError>;
    fn take_output_notice(&mut self) -> Option<String> {
        None
    }
}
#[derive(Default)]
struct RodioBackend {
    player: Option<Player>,
    stream: Option<MixerDeviceSink>,
    output_events: Option<OutputEvents>,
}
impl Backend for RodioBackend {
    fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError> {
        self.stop();
        let mut info = probe(path)?;
        let file = File::open(path).map_err(|e| EngineError::Io(e.to_string()))?;
        let decoder = Decoder::try_from(file).map_err(|e| EngineError::Decode(e.to_string()))?;
        let (callback, events) = output_events();
        let mut stream = configure_output(
            DeviceSinkBuilder::from_default_device()
                .map_err(|e| EngineError::Output(format!("Default output configuration: {e}")))?,
        )
        .with_error_callback(callback)
        .open_stream()
        .map_err(|e| EngineError::Output(format!("Output stream initialization: {e}")))?;
        stream.log_on_drop(false);
        info.output_rate = Some(stream.config().sample_rate().get());
        info.output_channels = Some(stream.config().channel_count().get());
        info.output_sample_format = Some(format!("{:?}", stream.config().sample_format()));
        let player = Player::connect_new(stream.mixer());
        player.append(decoder);
        self.player = Some(player);
        self.stream = Some(stream);
        self.output_events = Some(events);
        Ok(info)
    }
    fn play(&mut self) {
        if let Some(p) = &self.player {
            p.play();
        }
    }
    fn pause(&mut self) {
        if let Some(p) = &self.player {
            p.pause();
        }
    }
    fn stop(&mut self) {
        if let Some(p) = self.player.take() {
            p.stop();
        }
        self.stream.take();
        self.output_events = None;
    }
    fn take_output_notice(&mut self) -> Option<String> {
        let error = self.output_events.as_ref()?.notices.try_recv().ok()?;
        let action = match error.kind() {
            rodio::cpal::ErrorKind::DeviceChanged => {
                "The stream rerouted automatically. Check the selected system output device."
            }
            rodio::cpal::ErrorKind::Xrun => {
                "A glitch may have occurred. Reduce system load if it repeats."
            }
            _ => "Timing may be less reliable under load.",
        };
        Some(format!(
            "Output notice ({:?}): {error} {action}",
            error.kind()
        ))
    }
    fn poll(&mut self) -> Result<(f64, bool), EngineError> {
        if let Some(error) = self
            .output_events
            .as_ref()
            .and_then(|events| events.fatal.try_recv().ok())
        {
            return Err(EngineError::Output(format!(
                "Output stream callback ({:?}): {error} Check the output device, then press Play to retry.", error.kind()
            )));
        }
        Ok(self
            .player
            .as_ref()
            .map(|p| (p.get_pos().as_secs_f64(), p.empty()))
            .unwrap_or((0.0, true)))
    }
}
struct OutputEvents {
    fatal: Receiver<rodio::cpal::Error>,
    notices: Receiver<rodio::cpal::Error>,
}
fn output_events() -> (
    impl FnMut(rodio::cpal::Error) + Send + 'static,
    OutputEvents,
) {
    let (fatal_tx, fatal) = mpsc::sync_channel(1);
    let (notice_tx, notices) = mpsc::sync_channel(1);
    let callback = move |error: rodio::cpal::Error| {
        // CPAL reports these notifications without invalidating the stream.
        // Separate bounded channels prevent a notice flood hiding a fatal error.
        // Keep the actual error; formatting happens on the worker, never here.
        let sender = match error.kind() {
            rodio::cpal::ErrorKind::DeviceChanged
            | rodio::cpal::ErrorKind::Xrun
            | rodio::cpal::ErrorKind::RealtimeDenied => &notice_tx,
            _ => &fatal_tx,
        };
        let _ = sender.try_send(error);
    };
    (callback, OutputEvents { fatal, notices })
}
struct Envelope {
    command: Command,
    sequence: u64,
    generation: u64,
}
pub struct Engine {
    sender: Option<SyncSender<Envelope>>,
    shared: Arc<Mutex<Snapshot>>,
    worker: Option<JoinHandle<()>>,
    closing: Arc<AtomicBool>,
    sequence: u64,
}
fn lock(shared: &Mutex<Snapshot>) -> std::sync::MutexGuard<'_, Snapshot> {
    shared.lock().unwrap_or_else(|e| e.into_inner())
}
impl Engine {
    pub fn new() -> Result<Self, EngineError> {
        Self::with_backend(RodioBackend::default)
    }
    fn with_backend<B: Backend + 'static, F: FnOnce() -> B + Send + 'static>(
        factory: F,
    ) -> Result<Self, EngineError> {
        let (tx, rx) = mpsc::sync_channel(16);
        let shared = Arc::new(Mutex::new(Snapshot::default()));
        let copy = shared.clone();
        let closing = Arc::new(AtomicBool::new(false));
        let close = closing.clone();
        let worker = thread::Builder::new()
            .name("reson-playback".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    run_worker(factory(), rx, &copy, &close)
                }));
                if result.is_err() {
                    let mut s = lock(&copy);
                    s.fail("Playback worker panic; restart Reson".into());
                    s.acknowledged = u64::MAX;
                }
            })
            .map_err(|e| EngineError::Io(e.to_string()))?;
        Ok(Self {
            sender: Some(tx),
            shared,
            worker: Some(worker),
            closing,
            sequence: 0,
        })
    }
    pub fn send(&mut self, command: Command) -> Result<(), EngineError> {
        let mut s = lock(&self.shared);
        let sequence = self.sequence + 1;
        let generation = s.generation + u64::from(matches!(command, Command::Load(_)));
        let path = if let Command::Load(p) = &command {
            Some(p.to_string_lossy().into_owned())
        } else {
            None
        };
        self.sender
            .as_ref()
            .ok_or(EngineError::Disconnected)?
            .try_send(Envelope {
                command,
                sequence,
                generation,
            })
            .map_err(|e| match e {
                TrySendError::Full(_) => EngineError::QueueFull,
                TrySendError::Disconnected(_) => EngineError::Disconnected,
            })?;
        self.sequence = sequence;
        if let Some(path) = path {
            s.begin_load(path);
        }
        Ok(())
    }
    pub fn snapshot(&self) -> Snapshot {
        lock(&self.shared).clone()
    }
    pub fn shutdown(&mut self) -> Result<(), EngineError> {
        self.closing.store(true, Ordering::Relaxed);
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            worker.join().map_err(|_| EngineError::WorkerPanic)?;
        }
        Ok(())
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}
fn run_worker<B: Backend>(
    mut backend: B,
    rx: Receiver<Envelope>,
    shared: &Mutex<Snapshot>,
    closing: &AtomicBool,
) {
    let mut active_generation = 0;
    let mut playing = false;
    let mut output_active = false;
    while !closing.load(Ordering::Relaxed) {
        let received = if output_active {
            rx.recv_timeout(Duration::from_millis(if playing { 100 } else { 500 }))
                .map_err(|e| !matches!(e, mpsc::RecvTimeoutError::Timeout))
        } else {
            rx.recv().map_err(|_| true)
        };
        match received {
            Ok(env) => {
                if matches!(env.command, Command::Shutdown) {
                    break;
                }
                // A newer accepted load supersedes old queued work without changing command ordering.
                if env.generation != lock(shared).generation {
                    continue;
                }
                let load_path = match &env.command {
                    Command::Load(p) => Some(p.clone()),
                    Command::Play
                        if matches!(
                            lock(shared).state,
                            PlaybackState::Stopped | PlaybackState::Ended | PlaybackState::Error
                        ) =>
                    {
                        Some(lock(shared).path.clone().into())
                    }
                    _ => None,
                };
                if let Some(path) = load_path {
                    backend.stop();
                    output_active = false;
                    playing = false;
                    {
                        let mut s = lock(shared);
                        if s.generation == env.generation {
                            s.state = PlaybackState::Loading;
                        }
                    }
                    let result = backend.load(&path);
                    let fallback = if result.is_err() {
                        probe(&path).ok()
                    } else {
                        None
                    };
                    let mut s = lock(shared);
                    if s.generation != env.generation {
                        drop(s);
                        backend.stop();
                        continue;
                    }
                    match result {
                        Ok(mut info) => {
                            info.generation = env.generation;
                            info.state = PlaybackState::Playing;
                            info.acknowledged = env.sequence;
                            *s = info;
                            playing = true;
                            output_active = true;
                            active_generation = env.generation;
                        }
                        Err(e) => {
                            if let Some(mut info) = fallback {
                                info.generation = env.generation;
                                *s = info;
                            }
                            s.fail(e.to_string());
                            s.acknowledged = env.sequence;
                        }
                    }
                } else {
                    match &env.command {
                        Command::Play => backend.play(),
                        Command::Pause => backend.pause(),
                        Command::Stop => {
                            backend.stop();
                            output_active = false;
                        }
                        _ => {}
                    }
                    let mut s = lock(shared);
                    if s.generation != env.generation {
                        continue;
                    }
                    match env.command {
                        Command::Play => {
                            s.play();
                            playing = s.state == PlaybackState::Playing;
                        }
                        Command::Pause => {
                            s.pause();
                            playing = false;
                        }
                        Command::Stop => {
                            s.stop();
                            playing = false;
                        }
                        _ => {}
                    }
                    s.acknowledged = env.sequence;
                }
            }
            Err(true) => break,
            Err(false) => {
                let result = backend.poll();
                let notice = backend.take_output_notice();
                let mut s = lock(shared);
                if s.generation != active_generation {
                    continue;
                }
                match result {
                    Ok((pos, ended)) => {
                        if let Some(notice) = notice {
                            s.output_notice = Some(notice);
                        }
                        if playing {
                            s.position_seconds = pos;
                        }
                        if playing && ended {
                            s.end();
                            drop(s);
                            backend.stop();
                            output_active = false;
                            playing = false;
                        }
                    }
                    Err(e) => {
                        s.fail(e.to_string());
                        drop(s);
                        backend.stop();
                        output_active = false;
                        playing = false;
                    }
                }
            }
        }
    }
    backend.stop();
}
#[cfg(test)]
#[path = "worker_tests.rs"]
mod tests;

fn configure_output(builder: DeviceSinkBuilder) -> DeviceSinkBuilder {
    builder.with_buffer_size(rodio::cpal::BufferSize::Default)
}
