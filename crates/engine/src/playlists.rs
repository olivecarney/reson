//! Ordered, duplicate-safe entries on the library worker's existing connection.
use crate::library::{LibraryStore, Result, Track};
use rusqlite::{params, Connection};
use serde::Serialize;
use std::collections::HashSet;

#[derive(Debug, Serialize)]
pub struct Playlist {
    pub id: i64,
    pub name: String,
    pub revision: i64,
}
#[derive(Debug, Serialize)]
pub struct PlaylistEntry {
    pub id: i64,
    pub track: Track,
}
fn name(value: &str) -> Result<&str> {
    let value = value.trim();
    if value.is_empty() || value.len() > 1024 || value.chars().any(char::is_control) {
        return Err("Invalid playlist name".into());
    }
    Ok(value)
}
fn require(c: &Connection, id: i64) -> Result<()> {
    c.query_row("SELECT id FROM playlists WHERE id=?1", [id], |_| Ok(()))?;
    Ok(())
}
fn order(c: &Connection, id: i64) -> Result<Vec<i64>> {
    require(c, id)?;
    Ok(
        c.prepare("SELECT id FROM playlist_entries WHERE playlist_id=?1 ORDER BY position,id")?
            .query_map([id], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?,
    )
}
fn write_order(c: &Connection, id: i64, ids: &[i64]) -> Result<()> {
    let mut q =
        c.prepare("UPDATE playlist_entries SET position=?1 WHERE id=?2 AND playlist_id=?3")?;
    for (position, entry) in ids.iter().enumerate() {
        q.execute(params![position as i64, entry, id])?;
    }
    c.execute("UPDATE playlists SET revision=revision+1 WHERE id=?1", [id])?;
    Ok(())
}
fn validate_entries(order: &[i64], ids: &[i64]) -> Result<HashSet<i64>> {
    let set: HashSet<_> = ids.iter().copied().collect();
    if ids.is_empty() || set.len() != ids.len() || !set.is_subset(&order.iter().copied().collect())
    {
        return Err("Invalid playlist entry IDs".into());
    }
    Ok(set)
}
impl LibraryStore {
    pub fn playlists(&self) -> Result<Vec<Playlist>> {
        Ok(self
            .connection
            .prepare("SELECT id,name,revision FROM playlists ORDER BY id")?
            .query_map([], |r| {
                Ok(Playlist {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    revision: r.get(2)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?)
    }
    pub fn playlist_count(&self, id: i64) -> Result<u32> {
        require(&self.connection, id)?;
        Ok(self.connection.query_row(
            "SELECT count(*) FROM playlist_entries WHERE playlist_id=?1",
            [id],
            |r| r.get(0),
        )?)
    }
    pub fn playlist_revision(&self, id: i64) -> Result<i64> {
        Ok(self
            .connection
            .query_row("SELECT revision FROM playlists WHERE id=?1", [id], |r| {
                r.get(0)
            })?)
    }
    pub fn create_playlist(&mut self, value: &str) -> Result<Playlist> {
        let name = name(value)?.to_owned();
        self.connection
            .execute("INSERT INTO playlists(name) VALUES(?1)", [&name])?;
        Ok(Playlist {
            id: self.connection.last_insert_rowid(),
            name,
            revision: 0,
        })
    }
    pub fn rename_playlist(&mut self, id: i64, value: &str) -> Result<()> {
        let name = name(value)?;
        if self.connection.execute(
            "UPDATE playlists SET name=?1,revision=revision+1 WHERE id=?2",
            params![name, id],
        )? != 1
        {
            return Err("Unknown playlist".into());
        }
        Ok(())
    }
    pub fn delete_playlist(&mut self, id: i64) -> Result<()> {
        if self
            .connection
            .execute("DELETE FROM playlists WHERE id=?1", [id])?
            != 1
        {
            return Err("Unknown playlist".into());
        }
        Ok(())
    }
    pub fn playlist_entries(&self, id: i64, offset: u32, limit: u32) -> Result<Vec<PlaylistEntry>> {
        require(&self.connection, id)?;
        // Path fallback reconnects a stale/unindexed entry after an explicit folder import.
        let mut q=self.connection.prepare("SELECT e.id,t.id,coalesce(t.path,e.path),coalesce(t.title,e.title),t.artist,t.album,t.genre,coalesce(t.duration,e.duration),t.sample_rate,t.channels,t.bit_depth,coalesce(t.format,''),t.bpm,t.musical_key,coalesce(t.size,0),coalesce(t.modified,0),coalesce(t.imported,0),coalesce(t.missing,1) FROM playlist_entries e LEFT JOIN tracks t ON t.id=coalesce((SELECT id FROM tracks WHERE id=e.track_id AND path=e.path),(SELECT id FROM tracks WHERE path=e.path)) WHERE e.playlist_id=?1 ORDER BY e.position,e.id LIMIT ?2 OFFSET ?3")?;
        let rows = q
            .query_map(params![id, limit.clamp(1, 500), offset], |r| {
                Ok(PlaylistEntry {
                    id: r.get(0)?,
                    track: Track {
                        id: r.get::<_, Option<i64>>(1)?.unwrap_or(0),
                        path: r.get(2)?,
                        title: r.get(3)?,
                        artist: r.get(4)?,
                        album: r.get(5)?,
                        genre: r.get(6)?,
                        duration: r.get(7)?,
                        sample_rate: r.get(8)?,
                        channels: r.get(9)?,
                        bit_depth: r.get(10)?,
                        format: r.get(11)?,
                        bpm: r.get(12)?,
                        key: r.get(13)?,
                        size: r.get(14)?,
                        modified: r.get(15)?,
                        imported: r.get(16)?,
                        missing: r.get(17)?,
                    },
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }
    pub fn add_playlist_tracks(&mut self, id: i64, tracks: &[i64], position: u32) -> Result<()> {
        if tracks.is_empty() || tracks.len() > 1000 {
            return Err("Insert between 1 and 1000 tracks".into());
        }
        let tx = self.connection.transaction()?;
        let mut ordered = order(&tx, id)?;
        let position = position as usize;
        if position > ordered.len() {
            return Err("Invalid insertion position".into());
        }
        let mut inserted = Vec::with_capacity(tracks.len());
        {
            let mut q=tx.prepare("INSERT INTO playlist_entries(playlist_id,track_id,path,title,duration,position) SELECT ?1,id,path,title,duration,0 FROM tracks WHERE id=?2")?;
            for track in tracks {
                if q.execute(params![id, track])? != 1 {
                    return Err("Unknown track".into());
                }
                inserted.push(tx.last_insert_rowid());
            }
        }
        ordered.splice(position..position, inserted);
        write_order(&tx, id, &ordered)?;
        tx.commit()?;
        Ok(())
    }
    pub fn remove_playlist_entries(&mut self, id: i64, ids: &[i64]) -> Result<()> {
        let tx = self.connection.transaction()?;
        let mut ordered = order(&tx, id)?;
        let set = validate_entries(&ordered, ids)?;
        for entry in ids {
            tx.execute(
                "DELETE FROM playlist_entries WHERE playlist_id=?1 AND id=?2",
                params![id, entry],
            )?;
        }
        ordered.retain(|e| !set.contains(e));
        write_order(&tx, id, &ordered)?;
        tx.commit()?;
        Ok(())
    }
    /// Destination is a boundary in the original order. Selected rows keep stored order.
    pub fn move_playlist_entries(&mut self, id: i64, ids: &[i64], position: u32) -> Result<()> {
        let tx = self.connection.transaction()?;
        let ordered = order(&tx, id)?;
        let set = validate_entries(&ordered, ids)?;
        let position = position as usize;
        if position > ordered.len() {
            return Err("Invalid move position".into());
        }
        let destination = ordered[..position]
            .iter()
            .filter(|e| !set.contains(e))
            .count();
        let moving: Vec<_> = ordered
            .iter()
            .copied()
            .filter(|e| set.contains(e))
            .collect();
        let mut remaining: Vec<_> = ordered.into_iter().filter(|e| !set.contains(e)).collect();
        remaining.splice(destination..destination, moving);
        write_order(&tx, id, &remaining)?;
        tx.commit()?;
        Ok(())
    }
}
