fn main() {
    let builder = rodio::DeviceSinkBuilder::from_default_device().unwrap();
    println!("Default builder: {builder:?}");
    match builder.open_stream() {
        Ok(stream) => println!("Opened {:?}", stream.config()),
        Err(e) => println!("Direct failure: {e:?}"),
    }
    match rodio::DeviceSinkBuilder::open_default_sink() {
        Ok(stream) => println!("Fallback opened {:?}", stream.config()),
        Err(e) => println!("Fallback failure: {e:?}"),
    }
}
