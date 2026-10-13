//! A dedicated database/scanner worker, independent of the playback engine.
use crate::library::{LibraryStore, Result, Scan, ScanSummary, Sort};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, SyncSender},
        Arc,
    },
    thread::JoinHandle,
};
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Request {
    op: String,
    path: String,
    search: String,
    sort: u32,
    descending: bool,
    offset: u32,
    limit: u32,
}
#[derive(Default, Serialize)]
struct Status {
    busy: bool,
    revision: u64,
    summary: ScanSummary,
}
struct Message {
    request: Value,
    reply: mpsc::Sender<Value>,
}
pub struct Library {
    sender: Option<SyncSender<Message>>,
    closing: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}
impl Library {
    pub fn new(path: PathBuf) -> Result<Self> {
        let (tx, rx) = mpsc::sync_channel::<Message>(16);
        let (ready_tx, ready_rx) = mpsc::channel();
        let closing = Arc::new(AtomicBool::new(false));
        let shutdown = closing.clone();
        let worker = std::thread::Builder::new()
            .name("reson-library".into())
            .spawn(move || run(path, rx, ready_tx, shutdown))?;
        match ready_rx.recv()? {
            Ok(()) => Ok(Self {
                sender: Some(tx),
                closing,
                worker: Some(worker),
            }),
            Err(e) => {
                let _ = worker.join();
                Err(e.into())
            }
        }
    }
    pub fn request(&mut self, request: Value) -> Result<Value> {
        let (tx, rx) = mpsc::channel();
        self.sender
            .as_ref()
            .ok_or("Library is closed")?
            .try_send(Message { request, reply: tx })?;
        Ok(rx.recv()?)
    }
    pub fn shutdown(&mut self) {
        self.closing.store(true, Ordering::Relaxed);
        self.sender.take();
        if let Some(w) = self.worker.take() {
            let _ = w.join();
        }
    }
}
impl Drop for Library {
    fn drop(&mut self) {
        self.shutdown();
    }
}

struct Worker {
    store: LibraryStore,
    status: Status,
    active: Option<Scan>,
    pending: std::collections::VecDeque<PathBuf>,
}
fn run(
    path: PathBuf,
    receiver: mpsc::Receiver<Message>,
    ready: mpsc::Sender<std::result::Result<(), String>>,
    closing: Arc<AtomicBool>,
) {
    let store = match LibraryStore::open(&path) {
        Ok(store) => {
            let _ = ready.send(Ok(()));
            store
        }
        Err(error) => {
            let _ = ready.send(Err(error.to_string()));
            return;
        }
    };
    let mut worker = Worker {
        store,
        status: Status::default(),
        active: None,
        pending: Default::default(),
    };
    while !closing.load(Ordering::Relaxed) {
        let message = if worker.status.busy {
            match receiver.try_recv() {
                Ok(message) => Some(message),
                Err(mpsc::TryRecvError::Empty) => None,
                Err(_) => break,
            }
        } else {
            match receiver.recv() {
                Ok(message) => Some(message),
                Err(_) => break,
            }
        };
        if let Some(message) = message {
            let response = serde_json::from_value::<Request>(message.request)
                .map_err(|error| -> Box<dyn std::error::Error + Send + Sync> { Box::new(error) })
                .and_then(|request| worker.respond(request))
                .unwrap_or_else(|error| json!({"error": error.to_string()}));
            let _ = message.reply.send(response);
        }
        if worker.status.busy {
            worker.step();
        }
    }
}
impl Worker {
    fn respond(&mut self, request: Request) -> Result<Value> {
        match request.op.as_str() {
            "query" => {
                if request.search.len() > 4096 || request.limit > 500 {
                    return Err("Invalid query bounds".into());
                }
                let sort = Sort::from_code(request.sort).ok_or("Invalid sort column")?;
                let limit = if request.limit == 0 {
                    500
                } else {
                    request.limit
                };
                Ok(
                    json!({"tracks": self.store.query(&request.search, sort, request.descending, request.offset, limit)?, "revision": self.status.revision}),
                )
            }
            "status" => Ok(serde_json::to_value(&self.status)?),
            "import" | "rescan" => {
                if self.status.busy {
                    return Err("An import is already running".into());
                }
                let paths = if request.op == "rescan" {
                    self.store.folders()?
                } else {
                    if request.path.is_empty() || request.path.len() > 32768 {
                        return Err("Invalid folder path".into());
                    }
                    vec![PathBuf::from(request.path)]
                };
                self.pending = paths.into();
                self.status.summary = ScanSummary::default();
                self.status.busy = !self.pending.is_empty();
                Ok(json!({}))
            }
            "cancel" => {
                self.pending.clear();
                self.active = None;
                self.status.busy = false;
                self.status.summary.cancelled = true;
                self.status.revision += 1;
                Ok(json!({}))
            }
            _ => Err("Unknown library operation".into()),
        }
    }
    fn fail(&mut self, error: impl std::fmt::Display) {
        self.status.summary.failed += 1;
        self.status.summary.error = Some(error.to_string());
    }
    fn step(&mut self) {
        if self.active.is_none() {
            if let Some(path) = self.pending.pop_front() {
                match self.store.begin_scan(&path) {
                    Ok(scan) => self.active = Some(scan),
                    Err(error) => self.fail(error),
                }
            } else {
                self.status.busy = false;
                self.status.revision += 1;
                return;
            }
        }
        let Some(scan) = self.active.as_mut() else {
            return;
        };
        let before = scan.summary.clone();
        match self.store.step(scan) {
            Ok(true) => {
                self.status.summary.visited += scan.summary.visited - before.visited;
                self.status.summary.indexed += scan.summary.indexed - before.indexed;
                self.status.summary.failed += scan.summary.failed - before.failed;
                if scan.summary.error.is_some() {
                    self.status.summary.error = scan.summary.error.clone();
                }
                self.status.revision += 1;
            }
            Ok(false) => {
                if let Err(error) = self.store.finish(scan) {
                    self.fail(error);
                }
                self.active = None;
                self.status.revision += 1;
            }
            Err(error) => {
                self.fail(error);
                self.active = None;
            }
        }
    }
}
