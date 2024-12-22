// src/ansi_parser.rs

use crate::buffer::Buffer;
use std::sync::{ Arc, Mutex };

pub struct AnsiParser {
    state: ParserState,
    param_buffer: Vec<u8>,
    params: Vec<usize>,
    intermediate_bytes: Vec<u8>,
    final_byte: u8,
    osc_bytes: Vec<u8>,
    buffer: Arc<Mutex<Buffer>>,
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
    pub fn new(buffer: Arc<Mutex<Buffer>>) -> Self {
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
                if
                    byte == 0x07 ||
                    (byte == 0x1b &&
                        !self.osc_bytes.is_empty() &&
                        self.osc_bytes.last() == Some(&0x5c))
                {
                    self.state = ParserState::Normal;
                    self.osc_bytes.clear();
                } else {
                    self.osc_bytes.push(byte);
                }
            }
            ParserState::SosPmApc => {
                if
                    byte == 0x07 ||
                    (byte == 0x1b &&
                        !self.osc_bytes.is_empty() &&
                        self.osc_bytes.last() == Some(&0x5c))
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
                let n = *self.params.get(0).unwrap_or(&1);
                buffer.move_cursor_up(n);
            }
            0x42 => {
                // B - Cursor Down
                let n = *self.params.get(0).unwrap_or(&1);
                buffer.move_cursor_down(n);
            }
            0x43 => {
                // C - Cursor Forward
                let n = *self.params.get(0).unwrap_or(&1);
                buffer.move_cursor_forward(n);
            }
            0x44 => {
                // D - Cursor Backward
                let n = *self.params.get(0).unwrap_or(&1);
                buffer.move_cursor_backward(n);
            }
            0x48 | 0x66 => {
                // H, f - Cursor Position
                let row = self.params.get(0).map_or(0, |&x| if x > 0 { x - 1 } else { 0 });
                let col = self.params.get(1).map_or(0, |&x| if x > 0 { x - 1 } else { 0 });
                buffer.set_cursor_position(col, row);
            }
            0x4a => {
                // J - Erase Display
                let n = *self.params.get(0).unwrap_or(&0);
                buffer.erase_in_display(n);
            }
            0x4b => {
                // K - Erase Line
                let n = *self.params.get(0).unwrap_or(&0);
                buffer.erase_in_line(n);
            }
            0x6d => {
                // m - SGR Select Graphic Rendition
                buffer.apply_graphic_rendition(&self.params);
            }
            _ => {
                // Unhandled CSI sequence
                // Optionally log or ignore
            }
        }
    }
}
