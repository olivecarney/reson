//! Library-only removal; source files are never mutated. Paths are canonical at import.
use crate::library::{LibraryStore, Result};
use rusqlite::params;
use std::{
    collections::HashSet,
    path::{Path, PathBuf},
};

impl LibraryStore {
    pub fn exclusions(&self) -> Result<Vec<String>> {
        Ok(self
            .connection
            .prepare("SELECT path FROM library_exclusions ORDER BY path")?
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?)
    }
    pub fn remove_tracks(&mut self, ids: &[i64]) -> Result<()> {
        let unique: HashSet<_> = ids.iter().copied().collect();
        if ids.is_empty() || ids.len() > 1000 || unique.len() != ids.len() {
            return Err("Select between 1 and 1000 distinct indexed tracks".into());
        }
        let tx = self.connection.transaction()?;
        for id in ids {
            // Unknown IDs fail the whole transaction, including earlier exclusions.
            let path: String =
                tx.query_row("SELECT path FROM tracks WHERE id=?1", [id], |r| r.get(0))?;
            tx.execute(
                "INSERT OR IGNORE INTO library_exclusions(path) VALUES(?1)",
                [&path],
            )?;
            tx.execute("DELETE FROM tracks WHERE id=?1", [id])?;
        }
        tx.commit()?;
        Ok(())
    }
    pub fn restore_exclusion(&mut self, path: &str) -> Result<()> {
        if self
            .connection
            .execute("DELETE FROM library_exclusions WHERE path=?1", [path])?
            != 1
        {
            return Err("Unknown excluded track".into());
        }
        Ok(())
    }
    pub fn remove_folder(&mut self, path: &Path) -> Result<()> {
        // Use the registered spelling even for disconnected volumes. Path::starts_with
        // compares components: /Music-other is not inside /Music.
        let folders = self.folders()?;
        if !folders.iter().any(|p| p == path) {
            return Err("Unknown library folder".into());
        }
        let remaining: Vec<_> = folders.into_iter().filter(|p| p != path).collect();
        let uncovered = |candidate: &Path| {
            candidate.starts_with(path) && !remaining.iter().any(|p| candidate.starts_with(p))
        };
        let candidates: Vec<(i64, PathBuf)> = self
            .connection
            .prepare("SELECT id,path FROM tracks")?
            .query_map([], |r| {
                Ok((r.get(0)?, PathBuf::from(r.get::<_, String>(1)?)))
            })?
            .collect::<rusqlite::Result<_>>()?;
        let exclusions = self.exclusions()?;
        let tx = self.connection.transaction()?;
        for (id, _) in candidates.into_iter().filter(|(_, p)| uncovered(p)) {
            tx.execute("DELETE FROM tracks WHERE id=?1", [id])?;
        }
        // Removing the last source covering an exclusion resets it, so re-adding
        // that folder is an explicit fresh import. Other sources keep exclusions.
        for excluded in exclusions.iter().filter(|p| uncovered(Path::new(p))) {
            tx.execute("DELETE FROM library_exclusions WHERE path=?1", [excluded])?;
        }
        tx.execute(
            "DELETE FROM folders WHERE path=?1",
            params![path.to_str().ok_or("Invalid path")?],
        )?;
        tx.commit()?;
        Ok(())
    }
}
