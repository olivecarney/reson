//! System SQLite repository. Connections are owned by the library worker, never audio/UI.
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::{
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
};
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Track {
    pub id: i64,
    pub path: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub genre: Option<String>,
    pub duration: Option<f64>,
    pub sample_rate: Option<u32>,
    pub channels: Option<u16>,
    pub bit_depth: Option<u16>,
    pub format: String,
    pub bpm: Option<f64>,
    pub key: Option<String>,
    pub size: i64,
    pub modified: i64,
    pub imported: i64,
    pub missing: bool,
}
#[derive(Clone, Copy, Debug)]
pub enum Sort {
    Title,
    Artist,
    Album,
    Bpm,
    Key,
    Duration,
    Format,
}
impl Sort {
    pub fn from_code(code: u32) -> Option<Self> {
        Some(match code {
            0 => Self::Title,
            1 => Self::Artist,
            2 => Self::Album,
            3 => Self::Bpm,
            4 => Self::Key,
            5 => Self::Duration,
            6 => Self::Format,
            _ => return None,
        })
    }
    fn column(self) -> &'static str {
        match self {
            Self::Title => "title",
            Self::Artist => "artist",
            Self::Album => "album",
            Self::Bpm => "bpm",
            Self::Key => "musical_key",
            Self::Duration => "duration",
            Self::Format => "format",
        }
    }
}
pub struct LibraryStore {
    pub(crate) connection: Connection,
}
impl LibraryStore {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(p) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(p)?;
        }
        let mut connection = Connection::open(path)?;
        connection.busy_timeout(std::time::Duration::from_secs(2))?;
        let version: i64 = connection.query_row("PRAGMA user_version", [], |r| r.get(0))?;
        if version > 2 {
            return Err("Library was created by a newer Reson version".into());
        }
        connection.execute_batch(
            "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;",
        )?;
        if version == 0 {
            let tx = connection.transaction()?;
            tx.execute_batch("CREATE TABLE tracks(id INTEGER PRIMARY KEY,path TEXT NOT NULL UNIQUE,title TEXT NOT NULL,artist TEXT,album TEXT,genre TEXT,duration REAL,sample_rate INTEGER,channels INTEGER,bit_depth INTEGER,format TEXT NOT NULL,bpm REAL,musical_key TEXT,size INTEGER NOT NULL,modified INTEGER NOT NULL,imported INTEGER NOT NULL,missing INTEGER NOT NULL DEFAULT 0); CREATE TABLE folders(id INTEGER PRIMARY KEY,path TEXT NOT NULL UNIQUE,imported INTEGER NOT NULL,last_scan INTEGER); CREATE INDEX tracks_title ON tracks(title COLLATE NOCASE); CREATE INDEX tracks_artist ON tracks(artist COLLATE NOCASE); CREATE INDEX tracks_album ON tracks(album COLLATE NOCASE); PRAGMA user_version=1;")?;
            tx.commit()?;
        }
        if version < 2 {
            let tx = connection.transaction()?;
            tx.execute_batch("CREATE TABLE playlists(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0); CREATE TABLE playlist_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,track_id INTEGER REFERENCES tracks(id) ON DELETE SET NULL,path TEXT NOT NULL,title TEXT NOT NULL,duration REAL,position INTEGER NOT NULL); CREATE INDEX playlist_order ON playlist_entries(playlist_id,position,id); PRAGMA user_version=2;")?;
            tx.commit()?;
        }
        // Validate even existing databases before returning a usable handle.
        connection.prepare("SELECT id,path,title,artist,album,genre,duration,sample_rate,channels,bit_depth,format,bpm,musical_key,size,modified,imported,missing FROM tracks LIMIT 0")?;
        connection.prepare("SELECT id,path,imported,last_scan FROM folders LIMIT 0")?;
        connection.prepare("SELECT id,name,revision FROM playlists LIMIT 0")?;
        connection.prepare("SELECT id,playlist_id,track_id,path,title,duration,position FROM playlist_entries LIMIT 0")?;
        Ok(Self { connection })
    }
    pub fn upsert(&mut self, t: &Track) -> Result<()> {
        self.connection.execute("INSERT INTO tracks(path,title,artist,album,genre,duration,sample_rate,channels,bit_depth,format,bpm,musical_key,size,modified,imported,missing) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,0) ON CONFLICT(path) DO UPDATE SET title=excluded.title,artist=excluded.artist,album=excluded.album,genre=excluded.genre,duration=excluded.duration,sample_rate=excluded.sample_rate,channels=excluded.channels,bit_depth=excluded.bit_depth,format=excluded.format,bpm=excluded.bpm,musical_key=excluded.musical_key,size=excluded.size,modified=excluded.modified,missing=0",params![t.path,t.title,t.artist,t.album,t.genre,t.duration,t.sample_rate,t.channels,t.bit_depth,t.format,t.bpm,t.key,t.size,t.modified,t.imported])?;
        Ok(())
    }
    pub fn query(
        &self,
        search: &str,
        sort: Sort,
        descending: bool,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<Track>> {
        let escaped = search
            .replace('\\', "\\\\")
            .replace('%', "\\%")
            .replace('_', "\\_");
        let pattern = format!("%{escaped}%");
        let sql=format!("SELECT id,path,title,artist,album,genre,duration,sample_rate,channels,bit_depth,format,bpm,musical_key,size,modified,imported,missing FROM tracks WHERE title LIKE ?1 ESCAPE '\\' OR artist LIKE ?1 ESCAPE '\\' OR album LIKE ?1 ESCAPE '\\' OR genre LIKE ?1 ESCAPE '\\' OR path LIKE ?1 ESCAPE '\\' ORDER BY {} COLLATE NOCASE {},id ASC LIMIT ?2 OFFSET ?3",sort.column(),if descending{"DESC"}else{"ASC"});
        let mut q = self.connection.prepare(&sql)?;
        let rows = q.query_map(params![pattern, limit.clamp(1, 500), offset], |r| {
            Ok(Track {
                id: r.get(0)?,
                path: r.get(1)?,
                title: r.get(2)?,
                artist: r.get(3)?,
                album: r.get(4)?,
                genre: r.get(5)?,
                duration: r.get(6)?,
                sample_rate: r.get(7)?,
                channels: r.get(8)?,
                bit_depth: r.get(9)?,
                format: r.get(10)?,
                bpm: r.get(11)?,
                key: r.get(12)?,
                size: r.get(13)?,
                modified: r.get(14)?,
                imported: r.get(15)?,
                missing: r.get(16)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }
    pub fn folders(&self) -> Result<Vec<PathBuf>> {
        let mut q = self
            .connection
            .prepare("SELECT path FROM folders ORDER BY id")?;
        let paths = q
            .query_map([], |r| r.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .into_iter()
            .map(PathBuf::from)
            .collect();
        Ok(paths)
    }
    pub fn begin_scan(&mut self, path: &Path) -> Result<Scan> {
        let scan = Scan::new(path)?;
        self.connection.execute(
            "INSERT INTO folders(path,imported) VALUES(?1,?2) ON CONFLICT(path) DO NOTHING",
            params![scan.root.to_str().ok_or("Folder path is not UTF-8")?, now()],
        )?;
        Ok(scan)
    }
    pub fn scan(
        &mut self,
        path: &Path,
        cancel: &AtomicBool,
        mut progress: impl FnMut(&ScanSummary),
    ) -> Result<ScanSummary> {
        let mut scan = self.begin_scan(path)?;
        while !cancel.load(Ordering::Relaxed) && self.step(&mut scan)? {
            progress(&scan.summary);
        }
        if cancel.load(Ordering::Relaxed) {
            scan.summary.cancelled = true;
        } else {
            self.finish(&scan)?;
        }
        Ok(scan.summary)
    }
    pub fn step(&mut self, scan: &mut Scan) -> Result<bool> {
        let Some(entry) = scan.next() else {
            return Ok(false);
        };
        match entry {
            Err(e) => {
                scan.summary.failed += 1;
                scan.complete = false;
                scan.summary.error = Some(e);
            }
            Ok(path) => {
                scan.summary.visited += 1;
                match index(&path) {
                    Ok(track) => {
                        self.upsert(&track)?;
                        scan.summary.indexed += 1;
                    }
                    Err(e) => {
                        scan.summary.failed += 1;
                        scan.summary.error = Some(format!("{}: {e}", path.display()));
                    }
                }
            }
        }
        Ok(true)
    }
    pub fn finish(&mut self, scan: &Scan) -> Result<()> {
        if !scan.complete || scan.summary.cancelled {
            return Ok(());
        }
        // Retain missing records. Never infer absence on a disconnected/incompletely read tree.
        let prefix = format!(
            "{}/",
            scan.root
                .to_str()
                .ok_or("Invalid path")?
                .trim_end_matches('/')
        );
        let mut q = self
            .connection
            .prepare("SELECT id,path FROM tracks WHERE substr(path,1,?1)=?2")?;
        let rows = q
            .query_map(params![prefix.chars().count() as i64, prefix], |r| {
                Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        drop(q);
        let tx = self.connection.transaction()?;
        for (id, path) in rows {
            let missing = match std::fs::metadata(path) {
                Ok(_) => false,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => true,
                Err(_) => continue,
            };
            tx.execute(
                "UPDATE tracks SET missing=?1 WHERE id=?2",
                params![missing, id],
            )?;
        }
        tx.execute(
            "UPDATE folders SET last_scan=?1 WHERE path=?2",
            params![now(), scan.root.to_str()],
        )?;
        tx.commit()?;
        Ok(())
    }
}
fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
#[derive(Clone, Debug, Default, Serialize)]
pub struct ScanSummary {
    pub visited: u64,
    pub indexed: u64,
    pub failed: u64,
    pub cancelled: bool,
    pub error: Option<String>,
}
pub struct Scan {
    root: PathBuf,
    stack: Vec<std::fs::ReadDir>,
    pub summary: ScanSummary,
    complete: bool,
}
impl Scan {
    fn new(path: &Path) -> Result<Self> {
        let root = path.canonicalize()?;
        let entries = std::fs::read_dir(&root)?;
        Ok(Self {
            root,
            stack: vec![entries],
            summary: ScanSummary::default(),
            complete: true,
        })
    }
    fn next(&mut self) -> Option<std::result::Result<PathBuf, String>> {
        loop {
            let current = self.stack.last_mut()?;
            match current.next() {
                None => {
                    self.stack.pop();
                }
                Some(Err(e)) => return Some(Err(e.to_string())),
                Some(Ok(e)) => {
                    let ty = match e.file_type() {
                        Ok(t) => t,
                        Err(e) => return Some(Err(e.to_string())),
                    };
                    if ty.is_symlink() {
                        continue;
                    }
                    if ty.is_dir() {
                        match std::fs::read_dir(e.path()) {
                            Ok(d) => self.stack.push(d),
                            Err(e) => return Some(Err(e.to_string())),
                        }
                    } else if ty.is_file()
                        && e.path()
                            .extension()
                            .and_then(|s| s.to_str())
                            .is_some_and(|s| {
                                s.eq_ignore_ascii_case("wav") || s.eq_ignore_ascii_case("flac")
                            })
                    {
                        return Some(Ok(e.path()));
                    }
                }
            }
        }
    }
}
fn index(path: &Path) -> Result<Track> {
    let metadata = std::fs::metadata(path)?;
    let info = crate::playback::probe(path)?;
    let mut track = Track {
        path: path.to_str().ok_or("File path is not UTF-8")?.into(),
        title: info.title,
        artist: info.artist,
        album: info.album,
        duration: info.duration_seconds,
        sample_rate: info.sample_rate,
        channels: info.channels,
        bit_depth: info.bit_depth,
        format: info.format,
        size: i64::try_from(metadata.len())?,
        modified: metadata
            .modified()?
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64,
        imported: now(),
        ..Track::default()
    };
    // Header metadata only: no audio decoding, waveform, artwork or BPM analysis.
    use symphonia::core::{
        formats::FormatOptions,
        io::MediaSourceStream,
        meta::{MetadataOptions, StandardTagKey},
        probe::Hint,
    };
    let mss = MediaSourceStream::new(Box::new(std::fs::File::open(path)?), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
        hint.with_extension(ext);
    }
    let mut p = symphonia::default::get_probe().format(
        &hint,
        mss,
        &FormatOptions::default(),
        &MetadataOptions {
            limit_visual_bytes: symphonia::core::meta::Limit::Maximum(0),
            ..MetadataOptions::default()
        },
    )?;
    if let Some(meta) = p.format.metadata().current() {
        for tag in meta.tags() {
            let text = tag
                .value
                .to_string()
                .trim_end_matches('\0')
                .trim()
                .to_string();
            if text.is_empty() {
                continue;
            }
            match tag.std_key {
                Some(StandardTagKey::Genre) => track.genre = Some(text),
                Some(StandardTagKey::Bpm) => {
                    track.bpm = text
                        .parse::<f64>()
                        .ok()
                        .filter(|n| n.is_finite() && *n > 0.0)
                }
                _ => {
                    if matches!(
                        tag.key.to_ascii_lowercase().as_str(),
                        "initialkey" | "key" | "tkey"
                    ) {
                        track.key = Some(text);
                    }
                }
            }
        }
    }
    Ok(track)
}
