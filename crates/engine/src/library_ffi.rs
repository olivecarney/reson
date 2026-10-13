//! Serialized, caller-owned JSON library ABI. All calls must be off the UI thread.
use crate::library_worker::Library;
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
};
pub struct ResonLibrary {
    library: Library,
    result: Vec<u8>,
}
fn guard(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(5)
}
unsafe fn text<'a>(bytes: *const u8, length: usize, max: usize) -> Option<&'a str> {
    if bytes.is_null() || length == 0 || length > max {
        return None;
    }
    std::str::from_utf8(unsafe { std::slice::from_raw_parts(bytes, length) })
        .ok()
        .filter(|s| !s.contains('\0'))
}
/// # Safety
/// Path must be readable UTF-8; out must be writable/aligned. Caller owns the resulting handle.
#[no_mangle]
pub unsafe extern "C" fn reson_library_create(
    path: *const u8,
    length: usize,
    out: *mut *mut ResonLibrary,
) -> i32 {
    guard(|| {
        if out.is_null() {
            return 1;
        }
        unsafe {
            *out = ptr::null_mut();
        }
        let Some(path) = (unsafe { text(path, length, 32768) }) else {
            return 1;
        };
        match Library::new(path.into()) {
            Ok(library) => {
                unsafe {
                    *out = Box::into_raw(Box::new(ResonLibrary {
                        library,
                        result: b"{}\0".to_vec(),
                    }));
                }
                0
            }
            Err(_) => 5,
        }
    })
}
/// # Safety
/// Handle must be live and uniquely serialized. Input must reference length readable bytes.
#[no_mangle]
pub unsafe extern "C" fn reson_library_request(
    handle: *mut ResonLibrary,
    input: *const u8,
    length: usize,
) -> i32 {
    guard(|| {
        if handle.is_null() {
            return 1;
        }
        let Some(input) = (unsafe { text(input, length, 65536) }) else {
            return 1;
        };
        let Ok(value) = serde_json::from_str(input) else {
            return 1;
        };
        let h = unsafe { &mut *handle };
        match h.library.request(value) {
            Ok(response) => match serde_json::to_vec(&response) {
                Ok(mut bytes) => {
                    bytes.push(0);
                    h.result = bytes;
                    0
                }
                Err(_) => 5,
            },
            Err(_) => 3,
        }
    })
}
/// # Safety
/// Live serialized handle; required writable/aligned; output writable for capacity bytes.
#[no_mangle]
pub unsafe extern "C" fn reson_library_read(
    handle: *mut ResonLibrary,
    output: *mut u8,
    capacity: usize,
    required: *mut usize,
) -> i32 {
    guard(|| {
        if handle.is_null() || required.is_null() || (output.is_null() && capacity != 0) {
            return 1;
        }
        let h = unsafe { &*handle };
        unsafe {
            *required = h.result.len();
        }
        if capacity < h.result.len() {
            return 4;
        }
        unsafe {
            ptr::copy_nonoverlapping(h.result.as_ptr(), output, h.result.len());
        }
        0
    })
}
/// # Safety
/// Consumes a live uniquely owned handle; no concurrent calls. Joins worker off the UI thread.
#[no_mangle]
pub unsafe extern "C" fn reson_library_destroy(handle: *mut ResonLibrary) {
    let _ = guard(|| {
        if !handle.is_null() {
            drop(unsafe { Box::from_raw(handle) });
        }
        0
    });
}
