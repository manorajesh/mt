use crate::buffer::TextBuffer;
use std::sync::{Arc, Mutex};

pub struct AnsiParser {
    state: ParserState,
    param_buffer: Vec<u8>,
    params: Vec<usize>,
    intermediate_bytes: Vec<u8>,
    final_byte: u8,
    osc_bytes: Vec<u8>,
    buffer: Arc<Mutex<TextBuffer>>,
}

#[derive(Debug, PartialEq)]
enum ParserState {
    Normal,
    Escape,
    Csi,
    Osc,
    SosPmApc,
}

impl AnsiParser {
    pub fn new(buffer: Arc<Mutex<TextBuffer>>) -> Self {
        Self {
            state: ParserState::Normal,
            param_buffer: Vec::new(),
            params: Vec::new(),
            intermediate_bytes: Vec::new(),
            final_byte: 0,
            osc_bytes: Vec::new(),
            buffer,
        }
    }

    pub fn parse_byte(&mut self, byte: u8) {
        let mut buffer = self.buffer.lock().unwrap();
        match self.state {
            ParserState::Normal => {
                match byte {
                    0x1b => {
                        // ESC
                        self.state = ParserState::Escape;
                    }
                    0x08 => {
                        // BS
                        buffer.handle_backspace();
                    }
                    0x0a => {
                        // LF
                        buffer.add_new_line();
                    }
                    0x0d => {
                        // CR
                        buffer.add_carriage_return();
                    }
                    0x09 => {
                        // TAB
                        buffer.advance_cursor_to_next_tab_stop();
                    }
                    _ => {
                        buffer.append_char(byte);
                    }
                }
            }
            ParserState::Escape => {
                match byte {
                    0x5b => {
                        // [
                        self.state = ParserState::Csi;
                        self.params.clear();
                        self.param_buffer.clear();
                        self.intermediate_bytes.clear();
                    }
                    0x5d => {
                        // ]
                        self.state = ParserState::Osc;
                        self.osc_bytes.clear();
                    }
                    0x50 | 0x5f | 0x5e | 0x58 => {
                        // P, _, ^, X
                        self.state = ParserState::SosPmApc;
                    }
                    0x28 | 0x29 => {
                        // (, )
                        self.state = ParserState::Normal;
                    }
                    _ => {
                        self.state = ParserState::Normal;
                    }
                }
            }
            ParserState::Csi => {
                match byte {
                    0x30..=0x39 => {
                        // 0-9
                        self.param_buffer.push(byte);
                    }
                    0x3b => {
                        // ;
                        if let Some(param) = self.parse_number(&self.param_buffer) {
                            self.params.push(param);
                        }
                        self.param_buffer.clear();
                    }
                    0x20..=0x2f => {
                        // Intermediate bytes
                        self.intermediate_bytes.push(byte);
                    }
                    0x40..=0x7e => {
                        // Final byte
                        if !self.param_buffer.is_empty() {
                            if let Some(param) = self.parse_number(&self.param_buffer) {
                                self.params.push(param);
                            }
                            self.param_buffer.clear();
                        }
                        self.final_byte = byte;
                        drop(buffer);
                        self.handle_csi_sequence();
                        self.state = ParserState::Normal;
                    }
                    _ => {}
                }
            }
            ParserState::Osc => {
                if byte == 0x07
                    || (byte == 0x1b
                        && !self.osc_bytes.is_empty()
                        && self.osc_bytes.last() == Some(&0x5c))
                {
                    self.state = ParserState::Normal;
                    self.osc_bytes.clear();
                } else {
                    self.osc_bytes.push(byte);
                }
            }
            ParserState::SosPmApc => {
                if byte == 0x07
                    || (byte == 0x1b
                        && !self.osc_bytes.is_empty()
                        && self.osc_bytes.last() == Some(&0x5c))
                {
                    self.state = ParserState::Normal;
                }
            }
        }
    }

    fn parse_number(&self, bytes: &[u8]) -> Option<usize> {
        let s = std::str::from_utf8(bytes).ok()?;
        s.parse::<usize>().ok()
    }

    fn handle_csi_sequence(&mut self) {
        let mut buffer = self.buffer.lock().unwrap();
        match self.final_byte {
            0x41 => {
                // A - Cursor Up
                let n = *self.params.first().unwrap_or(&1);
                buffer.move_cursor_up(n);
            }
            0x42 => {
                // B - Cursor Down
                let n = *self.params.first().unwrap_or(&1);
                buffer.move_cursor_down(n);
            }
            0x43 => {
                // C - Cursor Forward
                let n = *self.params.first().unwrap_or(&1);
                buffer.move_cursor_forward(n);
            }
            0x44 => {
                // D - Cursor Backward
                let n = *self.params.first().unwrap_or(&1);
                buffer.move_cursor_backward(n);
            }
            0x48 | 0x66 => {
                // H, f - Cursor Position
                let row = self
                    .params
                    .first()
                    .map_or(0, |&x| if x > 0 { x - 1 } else { 0 });
                let col = self
                    .params
                    .get(1)
                    .map_or(0, |&x| if x > 0 { x - 1 } else { 0 });
                buffer.set_cursor_position(col, row);
            }
            0x4a => {
                // J - Erase Display
                let n = *self.params.first().unwrap_or(&0);
                buffer.erase_in_display(n);
            }
            0x4b => {
                // K - Erase Line
                let n = *self.params.first().unwrap_or(&0);
                buffer.erase_in_line(n);
            }
            0x6d => {
                // m - SGR Select Graphic Rendition
                buffer.apply_graphic_rendition(&self.params);
            }
            _ => {
                tracing::info!(
                    "Unhandled CSI sequence: {:?} {:?}",
                    self.params,
                    self.final_byte as char
                );
            }
        }
    }
}

pub struct AnsiSimdParser {
    inner_parser: AnsiParser,
}

impl AnsiSimdParser {
    pub fn new(buffer: Arc<Mutex<TextBuffer>>) -> Self {
        Self {
            inner_parser: AnsiParser::new(buffer),
        }
    }

    pub fn parse(&mut self, data: &[u8]) {
        let mut i = 0;
        while i < data.len() {
            // If the parser is in Normal state, try skipping a full chunk
            if self.inner_parser.state == ParserState::Normal && i + 16 <= data.len() {
                let chunk_end = (i + 16).min(data.len());
                let chunk: [u8; 16] = data[i..chunk_end].try_into().unwrap();

                if unsafe { !chunk_has_control_chars(chunk) } {
                    let mut buf = self.inner_parser.buffer.lock().unwrap();
                    buf.append_bytes(&chunk);
                    i += chunk.len();
                    continue;
                }
            }

            // Otherwise, parse the current byte normally
            self.inner_parser.parse_byte(data[i]);
            i += 1;
        }
    }
}

#[cfg(target_arch = "aarch64")]
#[target_feature(enable = "neon")]
unsafe fn chunk_has_control_chars(chunk: [u8; 16]) -> bool {
    use std::arch::aarch64::*;

    // Load the 16 bytes into a Neon register
    let data = vld1q_u8(chunk.as_ptr());

    // Create masks for each control character
    let esc_mask = vceqq_u8(data, vdupq_n_u8(0x1b)); // ESC
    let lf_mask = vceqq_u8(data, vdupq_n_u8(0x0a)); // Line Feed
    let bs_mask = vceqq_u8(data, vdupq_n_u8(0x08)); // Backspace
    let tab_mask = vceqq_u8(data, vdupq_n_u8(0x09)); // Tab
    let cr_mask = vceqq_u8(data, vdupq_n_u8(0x0d)); // Carriage Return

    // Combine all masks with OR operations
    let combined_mask = vorrq_u8(
        vorrq_u8(vorrq_u8(esc_mask, lf_mask), vorrq_u8(bs_mask, tab_mask)),
        cr_mask,
    );

    // Split and sum
    let lower = vget_low_u8(combined_mask);
    let upper = vget_high_u8(combined_mask);

    vaddv_u8(lower) + vaddv_u8(upper) != 0
}
