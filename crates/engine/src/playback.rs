use crate::state::{Command, PlaybackState, Snapshot};
use rodio::cpal::traits::{DeviceTrait, HostTrait};
use rodio::Source;
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
    if !matches!(ext.as_str(), "wav" | "flac" | "mp3") {
        return Err(EngineError::InvalidInput(
            "Choose a FLAC, PCM WAV or MP3 file".into(),
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
    let mut metadata = probed.metadata.get();
    let format_metadata = probed.format.metadata();
    if let Some(meta) = metadata
        .as_mut()
        .and_then(|m| m.current())
        .or_else(|| format_metadata.current())
    {
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
pub fn output_devices() -> Result<Vec<crate::state::OutputDevice>, EngineError> {
    rodio::cpal::default_host()
        .output_devices()
        .map_err(|e| EngineError::Output(e.to_string()))?
        .map(|d| {
            Ok(crate::state::OutputDevice {
                id: d
                    .id()
                    .map_err(|e| EngineError::Output(e.to_string()))?
                    .to_string(),
                name: d
                    .description()
                    .map_err(|e| EngineError::Output(e.to_string()))?
                    .name()
                    .to_owned(),
            })
        })
        .collect()
}

pub fn prepared_decoder(
    path: &Path,
    seconds: f64,
) -> Result<Decoder<std::io::BufReader<File>>, EngineError> {
    if !seconds.is_finite() || seconds < 0.0 {
        return Err(EngineError::InvalidInput(
            "Seek position must be finite and nonnegative".into(),
        ));
    }
    let file = File::open(path).map_err(|e| EngineError::Io(e.to_string()))?;
    let mut decoder = Decoder::try_from(file).map_err(|e| EngineError::Decode(e.to_string()))?;
    if seconds > 0.0 {
        if seconds
            > decoder
                .total_duration()
                .map(|d| d.as_secs_f64())
                .unwrap_or(u32::MAX as f64)
        {
            return Err(EngineError::InvalidInput(
                "Seek exceeds source duration".into(),
            ));
        }
        // Symphonia floors time to frames. A midpoint avoids nanosecond rounding
        // just below an exact frame boundary (e.g. frame 13 at 48 kHz).
        decoder
            .try_seek(Duration::from_secs_f64(
                (seconds * decoder.sample_rate().get() as f64).round()
                    / decoder.sample_rate().get() as f64
                    + 0.5 / decoder.sample_rate().get() as f64,
            ))
            .map_err(|e| EngineError::Decode(format!("Seek failed: {e}")))?;
    }
    Ok(decoder)
}

trait Backend {
    fn seek(&mut self, _path: &Path, _seconds: f64, _paused: bool) -> Result<(), EngineError> {
        Err(EngineError::Decode("Seeking unavailable".into()))
    }
    fn gain(&mut self, _gain: f32) {}
    fn device(&mut self, _id: Option<String>) {}
    fn devices(&mut self) -> Result<Vec<crate::state::OutputDevice>, EngineError> {
        output_devices()
    }
    fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError>;
    fn play(&mut self);
    fn pause(&mut self);
    fn stop(&mut self);
    fn poll(&mut self) -> Result<(f64, bool), EngineError>;
    fn take_output_notice(&mut self) -> Option<String> {
        None
    }
}
// Player::stop is serviced periodically by rodio. This inexpensive fence
// prevents its retired decoder contributing samples to a replacement player.
struct FencedSource<S> {
    inner: S,
    active: Arc<AtomicBool>,
}
impl<S: Source> Iterator for FencedSource<S> {
    type Item = f32;
    fn next(&mut self) -> Option<f32> {
        if self.active.load(Ordering::Acquire) {
            self.inner.next()
        } else {
            None
        }
    }
}
impl<S: Source> Source for FencedSource<S> {
    fn current_span_len(&self) -> Option<usize> {
        self.inner.current_span_len()
    }
    fn channels(&self) -> rodio::ChannelCount {
        self.inner.channels()
    }
    fn sample_rate(&self) -> rodio::SampleRate {
        self.inner.sample_rate()
    }
    fn total_duration(&self) -> Option<Duration> {
        self.inner.total_duration()
    }
}
#[derive(Default)]
struct RodioBackend {
    player: Option<Player>,
    stream: Option<MixerDeviceSink>,
    output_events: Option<OutputEvents>,
    source_active: Option<Arc<AtomicBool>>,
    preferred: Option<String>,
    gain: f32,
    offset: f64,
}
impl Backend for RodioBackend {
    fn load(&mut self, path: &Path) -> Result<Snapshot, EngineError> {
        self.stop();
        let mut info = probe(path)?;
        let decoder = prepared_decoder(path, 0.0)?;
        self.offset = 0.0;
        let (callback, events) = output_events();
        let host = rodio::cpal::default_host();
        let device = if let Some(id) = &self.preferred {
            host.output_devices()
                .map_err(|e| EngineError::Output(e.to_string()))?
                .find(|d| d.id().is_ok_and(|candidate| candidate.to_string() == *id))
                .ok_or_else(|| {
                    EngineError::Output(
                        "Selected output is unavailable; reconnect it or select System Default"
                            .into(),
                    )
                })?
        } else {
            host.default_output_device()
                .ok_or_else(|| EngineError::Output("No default output device".into()))?
        };
        let mut stream = configure_output(
            DeviceSinkBuilder::from_device(device)
                .map_err(|e| EngineError::Output(format!("Output configuration: {e}")))?,
        )
        .with_error_callback(callback)
        .open_stream()
        .map_err(|e| EngineError::Output(format!("Output stream initialization: {e}")))?;
        stream.log_on_drop(false);
        info.output_rate = Some(stream.config().sample_rate().get());
        info.output_channels = Some(stream.config().channel_count().get());
        info.output_sample_format = Some(format!("{:?}", stream.config().sample_format()));
        let player = Player::connect_new(stream.mixer());
        player.pause();
        player.set_volume(self.gain);
        let active = Arc::new(AtomicBool::new(true));
        player.append(FencedSource {
            inner: decoder,
            active: active.clone(),
        });
        self.source_active = Some(active);
        self.player = Some(player);
        self.stream = Some(stream);
        self.output_events = Some(events);
        Ok(info)
    }
    fn seek(&mut self, path: &Path, seconds: f64, paused: bool) -> Result<(), EngineError> {
        // Prepare and seek off the callback. Failure leaves the existing player intact.
        let decoder = prepared_decoder(path, seconds)?;
        let stream = self
            .stream
            .as_ref()
            .ok_or_else(|| EngineError::Output("No active output; press Play to recover".into()))?;
        if let Some(active) = self.source_active.take() {
            active.store(false, Ordering::Release);
        }
        if let Some(old) = self.player.take() {
            old.stop();
        }
        let player = Player::connect_new(stream.mixer());
        player.pause();
        player.set_volume(self.gain);
        let active = Arc::new(AtomicBool::new(true));
        player.append(FencedSource {
            inner: decoder,
            active: active.clone(),
        });
        self.source_active = Some(active);
        if !paused {
            player.play();
        }
        self.player = Some(player);
        self.offset = seconds;
        Ok(())
    }
    fn gain(&mut self, gain: f32) {
        self.gain = gain;
        if let Some(player) = &self.player {
            player.set_volume(gain);
        }
    }
    fn device(&mut self, id: Option<String>) {
        self.preferred = id;
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
        if let Some(active) = self.source_active.take() {
            active.store(false, Ordering::Release);
        }
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
            .map(|p| (self.offset + p.get_pos().as_secs_f64(), p.empty()))
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
        let shared = Arc::new(Mutex::new(Snapshot {
            volume: 1.0,
            ..Snapshot::default()
        }));
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
                    s.fail("Playback worker panic; restart reson".into());
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
        if self.closing.load(Ordering::Relaxed) {
            return Err(EngineError::Disconnected);
        }
        if matches!(command, Command::Seek { seconds, .. } if !seconds.is_finite())
            || matches!(command, Command::Volume(v) if !v.is_finite())
        {
            return Err(EngineError::InvalidInput(
                "Position and volume must be finite".into(),
            ));
        }
        let mut s = lock(&self.shared);
        let command = if matches!(command, Command::Play)
            && matches!(
                s.state,
                PlaybackState::Stopped | PlaybackState::Ended | PlaybackState::Error
            )
            && !s.path.is_empty()
        {
            Command::Load(s.path.clone().into())
        } else {
            command
        };
        let sequence = self.sequence + 1;
        let generation =
            s.generation + u64::from(matches!(command, Command::Load(_) | Command::Stop));
        let seek =
            matches!(command, Command::Seek { generation, .. } if generation == s.generation);
        let stop = matches!(command, Command::Stop);
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
        if seek {
            s.seek_request = sequence;
        }
        if stop {
            s.generation = generation;
        }
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
    let mut volume = 1.0_f32;
    let mut remembered = 1.0_f32;
    let mut muted = false;
    let mut preferred = None;
    let mut active_generation = 0;
    backend.gain(1.0);
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
                if env.generation != lock(shared).generation
                    && !matches!(
                        env.command,
                        Command::Volume(_)
                            | Command::Mute(_)
                            | Command::Device(_)
                            | Command::RefreshDevices
                    )
                {
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
                    if s.generation != env.generation || closing.load(Ordering::Relaxed) {
                        drop(s);
                        backend.stop();
                        continue;
                    }
                    match result {
                        Ok(mut info) => {
                            info.volume = volume;
                            info.muted = muted;
                            info.preferred_device = preferred.clone();
                            info.devices = s.devices.clone();
                            info.generation = env.generation;
                            info.state = PlaybackState::Playing;
                            info.acknowledged = env.sequence;
                            *s = info;
                            backend.play();
                            playing = true;
                            output_active = true;
                            active_generation = env.generation;
                        }
                        Err(e) => {
                            if let Some(mut info) = fallback {
                                info.volume = volume;
                                info.muted = muted;
                                info.preferred_device = preferred.clone();
                                info.devices = s.devices.clone();
                                info.generation = env.generation;
                                *s = info;
                            }
                            let kind = if matches!(
                                e,
                                EngineError::Io(_)
                                    | EngineError::Decode(_)
                                    | EngineError::InvalidInput(_)
                            ) {
                                "file"
                            } else {
                                "output"
                            };
                            s.fail(e.to_string());
                            s.failure_kind = Some(kind.into());
                            s.acknowledged = env.sequence;
                        }
                    }
                } else {
                    let mut operation_error = None;
                    let mut seek_position = None;
                    let mut device_info = None;
                    let mut device_position = None;
                    match &env.command {
                        Command::Volume(v) => {
                            volume = v.clamp(0.0, 1.0);
                            if volume > 0.0 {
                                remembered = volume;
                                muted = false;
                            }
                            backend.gain(if muted { 0.0 } else { volume });
                        }
                        Command::Mute(value) => {
                            muted = *value;
                            if !muted && volume == 0.0 {
                                volume = remembered;
                            }
                            backend.gain(if muted { 0.0 } else { volume });
                        }
                        Command::RefreshDevices => match backend.devices() {
                            Ok(devices) => lock(shared).devices = devices,
                            Err(e) => operation_error = Some(e.to_string()),
                        },
                        Command::Seek {
                            seconds,
                            generation,
                        } => {
                            let s = lock(shared).clone();
                            if *generation == s.generation
                                && env.sequence == s.seek_request
                                && matches!(s.state, PlaybackState::Playing | PlaybackState::Paused)
                            {
                                let end = s.duration_seconds.unwrap_or(u32::MAX as f64).max(0.0);
                                // Keep one source frame before EOF so a seek itself cannot consume the queue.
                                let target = seconds.clamp(
                                    0.0,
                                    (end - 1.0 / s.sample_rate.unwrap_or(44100) as f64).max(0.0),
                                );
                                let rate = s.sample_rate.unwrap_or(44100) as f64;
                                let target = (target * rate).round() / rate;
                                match backend.seek(Path::new(&s.path), target, !playing) {
                                    Ok(()) => seek_position = Some(target),
                                    Err(e) => operation_error = Some(e.to_string()),
                                }
                            }
                        }
                        Command::Device(id) => {
                            preferred = id.clone();
                            backend.device(id.clone());
                            let s = lock(shared).clone();
                            if (output_active
                                || (s.state == PlaybackState::Error
                                    && s.failure_kind.as_deref() == Some("output")))
                                && !s.path.is_empty()
                                && env.generation == s.generation
                            {
                                backend.pause();
                                let position = if output_active {
                                    backend
                                        .poll()
                                        .map(|(pos, _)| pos)
                                        .unwrap_or(s.position_seconds)
                                } else {
                                    s.position_seconds
                                };
                                let rate = s.sample_rate.unwrap_or(44100) as f64;
                                let position = position.min(
                                    (s.duration_seconds.unwrap_or(u32::MAX as f64) - 1.0 / rate)
                                        .max(0.0),
                                );
                                backend.stop();
                                output_active = false;
                                let result = backend.load(Path::new(&s.path)).and_then(|info| {
                                    backend.pause();
                                    backend.seek(Path::new(&s.path), position, !playing)?;
                                    Ok(info)
                                });
                                match result {
                                    Ok(info) => {
                                        device_position = Some(position);
                                        device_info = Some(info);
                                        output_active = true;
                                        active_generation = env.generation;
                                    }
                                    Err(e) => {
                                        backend.stop();
                                        operation_error = Some(e.to_string());
                                        playing = false;
                                    }
                                }
                            }
                        }

                        Command::Play => backend.play(),
                        Command::Pause => backend.pause(),
                        Command::Stop => {
                            backend.stop();
                            output_active = false;
                        }
                        _ => {}
                    }
                    let mut s = lock(shared);
                    if s.generation != env.generation || closing.load(Ordering::Relaxed) {
                        continue;
                    }
                    if matches!(env.command, Command::Seek { .. }) && env.sequence != s.seek_request
                    {
                        s.acknowledged = env.sequence;
                        continue;
                    }
                    match &env.command {
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
                    s.volume = volume;
                    s.muted = muted;
                    s.preferred_device = preferred.clone();
                    if let Some(position) = device_position {
                        s.position_seconds = position;
                    }
                    if let Some(info) = device_info {
                        s.state = if playing {
                            PlaybackState::Playing
                        } else {
                            PlaybackState::Paused
                        };
                        s.error = None;
                        s.failure_kind = None;
                        s.output_rate = info.output_rate;
                        s.output_channels = info.output_channels;
                        s.output_sample_format = info.output_sample_format;
                        s.output_notice = None;
                    }
                    if env.sequence == s.seek_request {
                        if let Some(pos) = seek_position {
                            s.position_seconds = pos;
                        }
                    }
                    if matches!(env.command, Command::Device(_)) && operation_error.is_some() {
                        s.fail(operation_error.clone().unwrap());
                        s.failure_kind = Some("output".into());
                    }
                    s.operation_error = operation_error;
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
                        s.failure_kind = Some("output".into());
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
