mod buffer;
mod ansi_parser;

use buffer::Buffer;
use ansi_parser::AnsiParser;
use std::process::Command;

fn main() {
    // Create a buffer with terminal dimensions
    let mut buffer = Buffer::new(24, 80); // Standard terminal size

    // Create parser that will update the buffer
    let mut parser = AnsiParser::new(&mut buffer);

    // Run a command and capture its output
    let output = Command::new("cat")
        .arg("-e")
        .arg("/Users/mano/Downloads/enwik8.pmd") // Or any other file
        .output()
        .expect("Failed to execute command");

    // Process each byte through the parser
    println!("Bytes: {}", output.stdout.len());
    let now = std::time::Instant::now();
    for byte in output.stdout {
        parser.parse_byte(byte);
    }
    println!("Elapsed time: {:?}", now.elapsed());

    for row in buffer.buffer.chunks(buffer.cols) {
        for cell in row {
            print!("{:?}", cell.ascii_code as char);
        }
        println!();
    }
}
