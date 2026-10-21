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
#[test]
fn blank_tags_remain_unknown_and_title_falls_back_to_filename() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("fallback.wav");
    let mut bytes = std::fs::read(fixture("tagged.wav")).unwrap();
    for text in [b"Fixture title".as_slice(), b"Fixture artist".as_slice()] {
        let offset = bytes.windows(text.len()).position(|w| w == text).unwrap();
        bytes[offset..offset + text.len()].fill(b' ');
    }
    std::fs::write(&path, bytes).unwrap();
    let info = probe(&path).unwrap();
    assert_eq!(info.title, "fallback");
    assert_eq!(info.artist, None);
}

#[test]
fn prepared_seeks_reach_exact_reference_samples_in_both_codecs() {
    use reson_engine::playback::prepared_decoder;
    // The original fixtures repeat four hand-checked PCM values.
    for (bits, rate, channels) in [(16, 44100, 1), (24, 48000, 2)] {
        for ext in ["wav", "flac"] {
            let p = fixture(&format!("pcm{bits}-{rate}-{channels}.{ext}"));
            for frame in [0, 13, rate / 20, rate / 10 - 2] {
                let mut decoder = prepared_decoder(&p, frame as f64 / rate as f64).unwrap();
                let index = (frame * channels as u32) % 4;
                let expected =
                    [0.0, 0.25, -0.25, 0.5 - 1.0 / (1u32 << (bits - 1)) as f32][index as usize];
                assert!(
                    (decoder.next().unwrap() - expected).abs() < 1e-7,
                    "{ext} {rate} frame {frame}"
                );
            }
        }
    }
}

#[test]
fn source_adaptation_to_48k_stereo_changes_samples_as_reported() {
    // Characterize the rodio adaptation that the actual output mixer uses:
    // 44.1k mono [0, .25, -.25] linearly interpolates to these first 48k frames.
    let decoder =
        reson_engine::playback::prepared_decoder(&fixture("pcm16-44100-1.flac"), 0.0).unwrap();
    let output = rodio::source::UniformSourceIterator::new(
        decoder,
        std::num::NonZeroU16::new(2).unwrap(),
        std::num::NonZeroU32::new(48000).unwrap(),
    );
    assert_eq!(output.channels().get(), 2);
    assert_eq!(output.sample_rate().get(), 48000);
    let samples: Vec<_> = output.collect();
    assert!((9598..=9602).contains(&samples.len()));
    for (actual, expected) in samples
        .iter()
        .take(6)
        .zip([0.0, 0.0, 0.2296875, 0.2296875, -0.16875, -0.16875])
    {
        assert!((actual - expected).abs() < 1e-6, "{actual} != {expected}");
    }
}

#[test]
fn mp3_metadata_duration_decode_and_seek_use_existing_engine() {
    use reson_engine::playback::prepared_decoder;
    let path = fixture("synthetic.mp3");
    let info = probe(&path).unwrap();
    assert_eq!(info.format, "MP3");
    assert_eq!(info.sample_rate, Some(44100));
    assert_eq!(info.title, "Synthetic MP3");
    assert_eq!(info.artist.as_deref(), Some("Reson fixture"));
    assert!((info.duration_seconds.unwrap() - 1.0).abs() < 0.1);
    assert_eq!(
        info.bit_depth, None,
        "Lossy MP3 has no PCM source bit depth"
    );
    for seconds in [0.0, 0.75, 0.1, 0.95] {
        let samples: Vec<_> = prepared_decoder(&path, seconds)
            .unwrap()
            .take(2000)
            .collect();
        assert_eq!(samples.len(), 2000);
        assert!(samples.iter().all(|s| s.is_finite()));
        assert!(
            samples.iter().any(|s| s.abs() > 0.001),
            "No decoded signal at {seconds}"
        );
    }
}
