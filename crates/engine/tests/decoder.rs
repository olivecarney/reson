use reson_engine::playback::probe;
use rodio::{Decoder, Source};
use std::{fs::File, path::PathBuf};
fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures")
        .join(name)
}
#[test]
fn fixture_properties_match_headers() {
    for (bits, rate, channels) in [(16, 44100, 1), (24, 48000, 2)] {
        for ext in ["wav", "flac"] {
            let p = fixture(&format!("pcm{bits}-{rate}-{channels}.{ext}"));
            let info = probe(&p).unwrap();
            assert_eq!(info.sample_rate, Some(rate));
            assert_eq!(info.channels, Some(channels));
            assert_eq!(info.bit_depth, Some(bits));
            assert!((info.duration_seconds.unwrap() - 0.1).abs() < 0.0001);
        }
    }
}
#[test]
fn decoded_samples_match_reference() {
    for (bits, rate, channels) in [(16, 44100, 1), (24, 48000, 2)] {
        for ext in ["wav", "flac"] {
            let d = Decoder::try_from(
                File::open(fixture(&format!("pcm{bits}-{rate}-{channels}.{ext}"))).unwrap(),
            )
            .unwrap();
            assert_eq!(d.sample_rate().get(), rate);
            let actual: Vec<_> = d.take(4).collect();
            let expected = [0.0, 0.25, -0.25, 0.5 - 1.0 / (1u32 << (bits - 1)) as f32];
            for (a, b) in actual.iter().zip(expected) {
                assert!((a - b).abs() < 1e-7, "{a} != {b}");
            }
            assert_eq!(actual.len(), 4);
        }
    }
}
#[test]
fn malformed_input_returns_error() {
    assert!(probe(&fixture("malformed.wav")).is_err());
}
#[test]
fn missing_path_returns_error() {
    assert!(probe(&fixture("missing.wav")).is_err());
}
#[test]
fn metadata_text_has_no_container_padding() {
    let info = probe(&fixture("tagged.wav")).unwrap();
    assert_eq!(info.title, "Fixture title");
    assert_eq!(info.artist.as_deref(), Some("Fixture artist"));
}
