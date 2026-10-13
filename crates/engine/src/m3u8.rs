//! Local UTF-8 playlists. Unindexed entries retain recoverable paths without scanning folders.
use crate::{
    library::{LibraryStore, Result},
    playlists::Playlist,
};
use rusqlite::{params, OptionalExtension};
use std::{
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};
fn normalize(path: &Path) -> PathBuf {
    let mut result = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                result.pop();
            }
            p => result.push(p.as_os_str()),
        }
    }
    result
}
impl LibraryStore {
    pub fn import_m3u8(&mut self, path: &Path, name: &str) -> Result<(Playlist, usize)> {
        let name = name.trim();
        if name.is_empty() || name.len() > 1024 || name.chars().any(char::is_control) {
            return Err("Invalid playlist name".into());
        }
        let mut bytes = Vec::new();
        std::fs::File::open(path)?
            .take(16 * 1024 * 1024 + 1)
            .read_to_end(&mut bytes)?;
        if bytes.len() > 16 * 1024 * 1024 {
            return Err("M3U8 exceeds 16 MiB".into());
        }
        let text = std::str::from_utf8(&bytes)?.trim_start_matches('\u{feff}');
        let absolute = std::path::absolute(path)?;
        let base = absolute.parent().ok_or("Invalid M3U8 location")?;
        let mut entries = Vec::new();
        let mut skipped = 0;
        let mut metadata = None;
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            if let Some(info) = line.strip_prefix("#EXTINF:") {
                metadata = info.split_once(',').map(|(duration, title)| {
                    (
                        duration
                            .parse::<f64>()
                            .ok()
                            .filter(|n| n.is_finite() && *n >= 0.0),
                        title.to_owned(),
                    )
                });
                continue;
            }
            if line.starts_with('#') {
                continue;
            }
            let meta = metadata.take();
            // URI schemes (including file:) are not paths; never fetch anything.
            let scheme = line.split_once(':').is_some_and(|(s, _)| {
                !s.is_empty()
                    && s.chars()
                        .all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c))
            });
            if scheme || line.chars().any(char::is_control) {
                skipped += 1;
                continue;
            }
            let file = Path::new(line);
            let file = if file.is_absolute() {
                file.to_owned()
            } else {
                base.join(file)
            };
            if !file
                .extension()
                .and_then(|e| e.to_str())
                .is_some_and(|e| e.eq_ignore_ascii_case("flac") || e.eq_ignore_ascii_case("wav"))
            {
                skipped += 1;
                continue;
            }
            let file = file.canonicalize().unwrap_or_else(|_| {
                file.parent()
                    .and_then(|p| p.canonicalize().ok())
                    .zip(file.file_name())
                    .map(|(parent, leaf)| parent.join(leaf))
                    .unwrap_or_else(|| normalize(&file))
            });
            let path = file.to_str().ok_or("Path is not UTF-8")?.to_owned();
            let (duration, title) = meta.unwrap_or_else(|| {
                (
                    None,
                    file.file_stem()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .into_owned(),
                )
            });
            entries.push((path, title, duration));
            if entries.len() > 100000 {
                return Err("M3U8 exceeds 100000 entries".into());
            }
        }
        let tx = self.connection.transaction()?;
        tx.execute("INSERT INTO playlists(name) VALUES(?1)", [name])?;
        let id = tx.last_insert_rowid();
        {
            let mut find = tx.prepare("SELECT id FROM tracks WHERE path=?1")?;
            let mut insert=tx.prepare("INSERT INTO playlist_entries(playlist_id,track_id,path,title,duration,position) VALUES(?1,?2,?3,?4,?5,?6)")?;
            for (position, (path, title, duration)) in entries.iter().enumerate() {
                let track: Option<i64> = find.query_row([path], |r| r.get(0)).optional()?;
                insert.execute(params![id, track, path, title, duration, position as i64])?;
            }
        }
        tx.commit()?;
        Ok((
            Playlist {
                id,
                name: name.into(),
                revision: 0,
            },
            skipped,
        ))
    }
    pub fn export_m3u8(&self, id: i64, path: &Path) -> Result<()> {
        self.playlist_revision(id)?;
        let absolute = std::path::absolute(path)?;
        let base = absolute.parent().ok_or("Invalid export path")?;
        let mut text = String::from("#EXTM3U\n");
        let mut offset = 0;
        loop {
            let entries = self.playlist_entries(id, offset, 500)?;
            for e in &entries {
                let source = Path::new(&e.track.path);
                if !source.is_absolute()
                    || e.track.path.trim() != e.track.path
                    || e.track.path.chars().any(char::is_control)
                {
                    return Err("Track path cannot be represented safely in M3U8".into());
                }
                let display = source
                    .strip_prefix(base)
                    .map(|p| format!("./{}", p.display()))
                    .unwrap_or_else(|_| e.track.path.clone());
                let title = e.track.title.replace(['\n', '\r'], " ");
                text.push_str(&format!(
                    "#EXTINF:{},{}\n{}\n",
                    e.track
                        .duration
                        .filter(|n| n.is_finite() && *n >= 0.0)
                        .map(|n| n.floor() as i64)
                        .unwrap_or(-1),
                    title,
                    display
                ));
            }
            if entries.len() < 500 {
                break;
            }
            offset += 500;
        }
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let temporary = base.join(format!(
            ".reson-m3u8-{}-{}.tmp",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let mut created = false;
        let result = (|| -> Result<()> {
            let mut file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            created = true;
            file.write_all(text.as_bytes())?;
            file.sync_all()?;
            std::fs::rename(&temporary, &absolute)?;
            std::fs::File::open(base)?.sync_all()?;
            Ok(())
        })();
        if result.is_err() && created {
            let _ = std::fs::remove_file(temporary);
        }
        result
    }
}
