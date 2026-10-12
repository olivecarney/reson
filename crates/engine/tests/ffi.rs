use reson_engine::ffi::*;
use std::ptr;
unsafe fn create() -> *mut ResonEngine {
    let mut e = ptr::null_mut();
    assert_eq!(unsafe { reson_engine_create(&mut e) }, 0);
    e
}
#[test]
fn lifecycle_and_null_arguments() {
    unsafe {
        assert_eq!(reson_engine_create(ptr::null_mut()), 1);
        assert_eq!(reson_engine_play(ptr::null_mut()), 1);
        reson_engine_destroy(ptr::null_mut());
        for _ in 0..20 {
            let e = create();
            reson_engine_destroy(e);
        }
    }
}
#[test]
fn invalid_utf8_and_empty_path() {
    unsafe {
        let e = create();
        assert_eq!(reson_engine_load(e, [255].as_ptr(), 1), 1);
        assert_eq!(reson_engine_load(e, ptr::null(), 1), 1);
        assert_eq!(reson_engine_load(e, ptr::null(), 0), 1);
        reson_engine_destroy(e);
    }
}
#[test]
fn sizing_snapshot_and_copied_unicode_path() {
    unsafe {
        let e = create();
        let mut path = "/missing/音 楽.wav".as_bytes().to_vec();
        let original = path.clone();
        assert_eq!(reson_engine_load(e, path.as_ptr(), path.len()), 0);
        path.fill(b'x');
        let mut s = ResonSnapshot::default();
        let mut required = 0;
        assert_eq!(
            reson_engine_snapshot(e, &mut s, ptr::null_mut(), 0, &mut required),
            4
        );
        assert!(required > 1);
        let mut tiny = [0];
        assert_eq!(
            reson_engine_snapshot(e, &mut s, tiny.as_mut_ptr(), 1, &mut required),
            4
        );
        let mut buf = vec![0u8; required + 1024];
        let cap = buf.len();
        assert_eq!(
            reson_engine_snapshot(e, &mut s, buf.as_mut_ptr(), cap, &mut required),
            0
        );
        let json: serde_json::Value = serde_json::from_slice(&buf[..required - 1]).unwrap();
        assert_eq!(json["path"], String::from_utf8(original).unwrap());
        assert_eq!(s.generation, 1);
        assert_eq!(buf[required - 1], 0);
        assert!([1, 6].contains(&s.state));
        reson_engine_destroy(e);
    }
}
#[test]
fn destroy_after_queued_commands() {
    unsafe {
        let e = create();
        let p = b"/missing/file.wav";
        assert_eq!(reson_engine_load(e, p.as_ptr(), p.len()), 0);
        assert_eq!(reson_engine_pause(e), 0);
        assert_eq!(reson_engine_stop(e), 0);
        reson_engine_destroy(e);
    }
}
