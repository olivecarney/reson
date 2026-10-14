//! Identical rodio/CPAL lifecycle measurements usable with v0.3 and v0.4.
use std::time::Instant;
fn report(name: &str, mut values: Vec<f64>) {
    values.sort_by(f64::total_cmp);
    println!(
        "{name}: median_ms={:.3} p95_ms={:.3}",
        values[values.len() / 2],
        values[values.len() * 95 / 100]
    );
}
fn main() {
    let mut open = Vec::new();
    let mut close = Vec::new();
    for _ in 0..15 {
        let t = Instant::now();
        let mut stream = rodio::DeviceSinkBuilder::from_default_device()
            .unwrap()
            .with_buffer_size(rodio::cpal::BufferSize::Default)
            .open_stream()
            .unwrap();
        stream.log_on_drop(false);
        open.push(t.elapsed().as_secs_f64() * 1000.0);
        let t = Instant::now();
        drop(stream);
        close.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    report("stream_open", open);
    report("stream_drop", close);
}
