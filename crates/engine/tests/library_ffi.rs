use reson_engine::library_ffi::*;
#[test]
fn caller_owned_results_and_invalid_arguments() {
    unsafe {
        assert_eq!(
            reson_library_create(std::ptr::null(), 0, std::ptr::null_mut()),
            1
        );
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("db");
        let bytes = path.to_str().unwrap().as_bytes();
        let mut h = std::ptr::null_mut();
        assert_eq!(reson_library_create(bytes.as_ptr(), bytes.len(), &mut h), 0);
        assert_eq!(reson_library_request(h, b"bad".as_ptr(), 3), 1);
        let request = br#"{"op":"query","limit":500}"#;
        assert_eq!(reson_library_request(h, request.as_ptr(), request.len()), 0);
        let mut required = 0;
        assert_eq!(
            reson_library_read(h, std::ptr::null_mut(), 0, &mut required),
            4
        );
        assert!(required > 1);
        let mut out = vec![0; required];
        assert_eq!(
            reson_library_read(h, out.as_mut_ptr(), out.len(), &mut required),
            0
        );
        assert_eq!(out[required - 1], 0);
        let value: serde_json::Value = serde_json::from_slice(&out[..required - 1]).unwrap();
        assert_eq!(value["tracks"].as_array().unwrap().len(), 0);
        assert_eq!(
            reson_library_read(h, std::ptr::null_mut(), 1, &mut required),
            1
        );
        reson_library_destroy(h);
        reson_library_destroy(std::ptr::null_mut());
    }
}
