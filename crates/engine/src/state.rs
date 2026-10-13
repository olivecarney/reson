use std::path::PathBuf;

#[repr(u32)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum PlaybackState {
    #[default]
    Empty = 0,
    Loading = 1,
    Playing = 2,
    Paused = 3,
    Stopped = 4,
    Ended = 5,
    Error = 6,
}
#[derive(Clone, Debug, Default)]
pub struct Snapshot {
    pub generation: u64,
    pub state: PlaybackState,
    pub position_seconds: f64,
    pub duration_seconds: Option<f64>,
    pub path: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub sample_rate: Option<u32>,
    pub channels: Option<u16>,
    pub bit_depth: Option<u16>,
    pub format: String,
    pub error: Option<String>,
    pub failure_kind: Option<String>,
    pub output_notice: Option<String>,
    pub output_rate: Option<u32>,
    pub output_channels: Option<u16>,
    pub output_sample_format: Option<String>,
    pub acknowledged: u64,
}
#[derive(Debug)]
pub enum Command {
    Load(PathBuf),
    Play,
    Pause,
    Stop,
    Shutdown,
}
impl Snapshot {
    pub fn begin_load(&mut self, path: String) {
        let generation = self.generation + 1;
        let acknowledged = self.acknowledged;
        *self = Self {
            generation,
            acknowledged,
            path,
            state: PlaybackState::Loading,
            ..Self::default()
        };
    }
    pub fn finish_load(&mut self, generation: u64, title: String) {
        if self.generation == generation {
            self.title = title;
            self.state = PlaybackState::Playing;
            self.error = None;
        }
    }
    pub fn pause(&mut self) {
        if self.state == PlaybackState::Playing {
            self.state = PlaybackState::Paused;
        }
    }
    pub fn play(&mut self) {
        match self.state {
            PlaybackState::Paused => self.state = PlaybackState::Playing,
            PlaybackState::Stopped | PlaybackState::Ended | PlaybackState::Error
                if !self.path.is_empty() =>
            {
                self.position_seconds = 0.0;
                self.state = PlaybackState::Loading;
                self.error = None;
            }
            _ => {}
        }
    }
    pub fn stop(&mut self) {
        if !self.path.is_empty() {
            self.state = PlaybackState::Stopped;
            self.position_seconds = 0.0;
        }
    }
    pub fn end(&mut self) {
        self.state = PlaybackState::Ended;
    }
    pub fn fail(&mut self, message: String) {
        self.state = PlaybackState::Error;
        self.error = Some(message);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn playing() -> Snapshot {
        let mut s = Snapshot::default();
        s.begin_load("a.wav".into());
        s.finish_load(s.generation, "A".into());
        s.position_seconds = 4.0;
        s
    }
    #[test]
    fn pause_resume_preserves_position() {
        let mut s = playing();
        s.pause();
        assert_eq!(s.state, PlaybackState::Paused);
        s.play();
        assert_eq!(s.state, PlaybackState::Playing);
        assert_eq!(s.position_seconds, 4.0);
    }
    #[test]
    fn stop_resets_position_retains_path() {
        let mut s = playing();
        s.stop();
        assert_eq!(s.state, PlaybackState::Stopped);
        assert_eq!(s.position_seconds, 0.0);
        assert_eq!(s.path, "a.wav");
    }
    #[test]
    fn ended_play_restarts() {
        let mut s = playing();
        s.end();
        s.play();
        assert_eq!(s.state, PlaybackState::Loading);
        assert_eq!(s.position_seconds, 0.0);
    }
    #[test]
    fn valid_load_recovers_error() {
        let mut s = playing();
        s.fail("bad file".into());
        s.begin_load("b.flac".into());
        s.finish_load(s.generation, "B".into());
        assert_eq!(s.state, PlaybackState::Playing);
        assert!(s.error.is_none());
    }
    #[test]
    fn replacement_generation_rejects_stale_result() {
        let mut s = playing();
        let old = s.generation;
        s.begin_load("b.wav".into());
        s.finish_load(old, "stale".into());
        assert_eq!(s.state, PlaybackState::Loading);
        assert_eq!(s.path, "b.wav");
        assert_ne!(s.title, "stale");
    }
}
