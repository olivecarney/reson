//! C ABI: caller must provide valid, aligned pointers and serialize every handle call.
//! No call may overlap destroy; a destroyed handle must never be reused.
use crate::{
    playback::{Engine, EngineError},
    state::Command,
};
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
};
pub struct ResonEngine {
    engine: Engine,
}
#[repr(C)]
#[derive(Default)]
pub struct ResonSnapshot {
    pub generation: u64,
    pub acknowledged: u64,
    pub state: u32,
    pub position_seconds: f64,
    pub duration_seconds: f64,
    pub sample_rate: u32,
    pub channels: u32,
    pub bit_depth: u32,
}
fn guard(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(5)
}
fn status(result: Result<(), EngineError>) -> i32 {
    match result {
        Ok(()) => 0,
        Err(EngineError::QueueFull) => 2,
        Err(EngineError::Disconnected) => 3,
        Err(_) => 5,
    }
}
/// # Safety
/// `out` must be writable and aligned for one pointer. The returned handle is caller-owned.
#[no_mangle]
pub unsafe extern "C" fn reson_engine_create(out: *mut *mut ResonEngine) -> i32 {
    guard(|| {
        if out.is_null() {
            return 1;
        }
        unsafe {
            *out = ptr::null_mut();
        }
        match Engine::new() {
            Ok(engine) => {
                unsafe {
                    *out = Box::into_raw(Box::new(ResonEngine { engine }));
                }
                0
            }
            Err(_) => 5,
        }
    })
}
/// # Safety
/// Non-null handle must be live, uniquely owned, and have no concurrent calls. Consumes it.
#[no_mangle]
pub unsafe extern "C" fn reson_engine_destroy(handle: *mut ResonEngine) {
    let _ = guard(|| {
        if !handle.is_null() {
            let mut h = unsafe { Box::from_raw(handle) };
            let _ = h.engine.shutdown();
        }
        0
    });
}
/// # Safety
/// Handle must be live and serialized; path must reference `length` readable bytes during the call.
#[no_mangle]
pub unsafe extern "C" fn reson_engine_load(
    handle: *mut ResonEngine,
    path: *const u8,
    length: usize,
) -> i32 {
    guard(|| {
        if handle.is_null() || path.is_null() || length == 0 || length > isize::MAX as usize {
            return 1;
        }
        let bytes = unsafe { std::slice::from_raw_parts(path, length) };
        let Ok(path) = std::str::from_utf8(bytes) else {
            return 1;
        };
        if path.contains('\0') {
            return 1;
        }
        status(
            unsafe { &mut *handle }
                .engine
                .send(Command::Load(path.into())),
        )
    })
}
macro_rules! command {
    ($name:ident,$command:expr) => {
        /// # Safety
        /// Handle must be live and all accesses serialized; no call may overlap destruction.
        #[no_mangle]
        pub unsafe extern "C" fn $name(handle: *mut ResonEngine) -> i32 {
            guard(|| {
                if handle.is_null() {
                    1
                } else {
                    status(unsafe { &mut *handle }.engine.send($command))
                }
            })
        }
    };
}
command!(reson_engine_play, Command::Play);
command!(reson_engine_pause, Command::Pause);
command!(reson_engine_stop, Command::Stop);
/// # Safety
/// Handle must be live and serialized; json references length readable bytes.
#[no_mangle]
pub unsafe extern "C" fn reson_engine_control(
    handle: *mut ResonEngine,
    json: *const u8,
    length: usize,
) -> i32 {
    guard(|| {
        if handle.is_null() || json.is_null() || length == 0 || length > 4096 {
            return 1;
        }
        let bytes = unsafe { std::slice::from_raw_parts(json, length) };
        let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else {
            return 1;
        };
        let command = match value["op"].as_str() {
            Some("seek") => match (value["seconds"].as_f64(), value["generation"].as_u64()) {
                (Some(seconds), Some(generation)) => Command::Seek {
                    seconds,
                    generation,
                },
                _ => return 1,
            },
            Some("volume") => match value["value"].as_f64() {
                Some(v) if v.is_finite() => Command::Volume(v.clamp(0.0, 1.0) as f32),
                _ => return 1,
            },
            Some("mute") => match value["value"].as_bool() {
                Some(v) => Command::Mute(v),
                _ => return 1,
            },
            Some("device") => match &value["id"] {
                serde_json::Value::Null => Command::Device(None),
                serde_json::Value::String(id) if !id.is_empty() => {
                    Command::Device(Some(id.clone()))
                }
                _ => return 1,
            },
            Some("devices") => Command::RefreshDevices,
            _ => return 1,
        };
        status(unsafe { &mut *handle }.engine.send(command))
    })
}
/// # Safety
/// Handle must be live and serialized. out/required must be writable and aligned.
/// text must have capacity writable bytes, or be null with capacity zero. Buffers must not overlap.
#[no_mangle]
pub unsafe extern "C" fn reson_engine_snapshot(
    handle: *mut ResonEngine,
    out: *mut ResonSnapshot,
    text: *mut u8,
    capacity: usize,
    required: *mut usize,
) -> i32 {
    guard(|| {
        if handle.is_null()
            || out.is_null()
            || required.is_null()
            || capacity > isize::MAX as usize
            || (text.is_null() && capacity != 0)
        {
            return 1;
        }
        let s = unsafe { &*handle }.engine.snapshot();
        let json = serde_json::json!({"path":s.path,"title":s.title,"artist":s.artist,"album":s.album,"format":s.format,"error":s.error,"failure_kind":s.failure_kind,"output_notice":s.output_notice,"output_rate":s.output_rate,"output_channels":s.output_channels,"output_sample_format":s.output_sample_format,"volume":s.volume,"muted":s.muted,"preferred_device":s.preferred_device,"devices":s.devices,"operation_error":s.operation_error});
        let Ok(bytes) = serde_json::to_vec(&json) else {
            return 5;
        };
        unsafe {
            *required = bytes.len() + 1;
            *out = ResonSnapshot {
                generation: s.generation,
                acknowledged: s.acknowledged,
                state: s.state as u32,
                position_seconds: s.position_seconds,
                duration_seconds: s.duration_seconds.unwrap_or(-1.0),
                sample_rate: s.sample_rate.unwrap_or(0),
                channels: s.channels.unwrap_or(0) as u32,
                bit_depth: s.bit_depth.unwrap_or(0) as u32,
            };
        }
        if capacity < bytes.len() + 1 {
            return 4;
        }
        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr(), text, bytes.len());
            *text.add(bytes.len()) = 0;
        }
        0
    })
}
