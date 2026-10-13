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

#[test]
fn playlist_json_buffers_are_caller_owned_and_malformed_requests_do_not_mutate() {
    unsafe {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("db");
        let path = path.to_str().unwrap().as_bytes();
        let mut h = std::ptr::null_mut();
        assert_eq!(reson_library_create(path.as_ptr(), path.len(), &mut h), 0);
        let create = r#"{"op":"playlist_create","name":"Unicode 音"}"#.as_bytes();
        assert_eq!(reson_library_request(h, create.as_ptr(), create.len()), 0);
        let mut n = 0;
        assert_eq!(reson_library_read(h, std::ptr::null_mut(), 0, &mut n), 4);
        let mut owned = vec![0; n];
        assert_eq!(
            reson_library_read(h, owned.as_mut_ptr(), owned.len(), &mut n),
            0
        );
        let saved = owned.clone();
        let malformed = br#"{"op":"playlist_delete","playlist_id":"wrong"}"#;
        assert_eq!(
            reson_library_request(h, malformed.as_ptr(), malformed.len()),
            0
        );
        assert_eq!(owned, saved); // the next response never aliases a caller's previous bytes
        let query = br#"{"op":"playlists"}"#;
        assert_eq!(reson_library_request(h, query.as_ptr(), query.len()), 0);
        assert_eq!(reson_library_read(h, std::ptr::null_mut(), 0, &mut n), 4);
        let mut reply = vec![0; n];
        assert_eq!(
            reson_library_read(h, reply.as_mut_ptr(), reply.len(), &mut n),
            0
        );
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&reply[..n - 1]).unwrap()["playlists"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        reson_library_destroy(h);
    }
}
