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
        let worker=std::thread::Builder::new().name("reson-library".into()).spawn(move||{
   let mut store=match LibraryStore::open(&path){Ok(s)=>{let _=ready_tx.send(Ok(()));s},Err(e)=>{let _=ready_tx.send(Err(e.to_string()));return;}};
   let mut status=Status::default();let mut active:Option<Scan>=None;let mut pending=std::collections::VecDeque::<PathBuf>::new();
   while !shutdown.load(Ordering::Relaxed){
    let message=if status.busy {match rx.try_recv(){Ok(m)=>Some(m),Err(mpsc::TryRecvError::Empty)=>None,Err(_)=>break}}else{match rx.recv(){Ok(m)=>Some(m),Err(_)=>break}};
    if let Some(m)=message {
     let response=(||->Result<Value>{
      let r:Request=serde_json::from_value(m.request)?;
      match r.op.as_str(){
       "query"=>{if r.search.len()>4096||r.limit>500{return Err("Invalid query bounds".into());}let sort=Sort::from_code(r.sort).ok_or("Invalid sort column")?;Ok(json!({"tracks":store.query(&r.search,sort,r.descending,r.offset,if r.limit==0{500}else{r.limit})?,"revision":status.revision}))},
       "status"=>Ok(serde_json::to_value(&status)?),
       "import"|"rescan"=>{
        if status.busy{return Err("An import is already running".into());}
        let paths=if r.op=="rescan"{store.folders()?}else{if r.path.is_empty()||r.path.len()>32768{return Err("Invalid folder path".into());}vec![PathBuf::from(r.path)]};
        pending=paths.into();status.summary=ScanSummary::default();status.busy = !pending.is_empty();Ok(json!({}))
       },
       "cancel"=>{pending.clear();active=None;status.busy=false;status.summary.cancelled=true;status.revision+=1;Ok(json!({}))},
       _=>Err("Unknown library operation".into()),
      }
     })().unwrap_or_else(|e|json!({"error":e.to_string()}));let _=m.reply.send(response);
    }
    if status.busy {
     if active.is_none(){if let Some(path)=pending.pop_front(){match store.begin_scan(&path){Ok(s)=>active=Some(s),Err(e)=>{status.summary.failed+=1;status.summary.error=Some(e.to_string());}}}else{status.busy=false;status.revision+=1;continue;}}
     if let Some(scan)=active.as_mut(){let before=scan.summary.clone();match store.step(scan){
      Ok(true)=>{status.summary.visited+=scan.summary.visited-before.visited;status.summary.indexed+=scan.summary.indexed-before.indexed;status.summary.failed+=scan.summary.failed-before.failed;if scan.summary.error.is_some(){status.summary.error=scan.summary.error.clone();}status.revision+=1;},
      Ok(false)=>{if let Err(e)=store.finish(scan){status.summary.failed+=1;status.summary.error=Some(e.to_string());}active=None;status.revision+=1;},
      Err(e)=>{status.summary.failed+=1;status.summary.error=Some(e.to_string());active=None;},
     }}
    }
   }
  })?;
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
