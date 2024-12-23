// #[derive(Clone, Copy, Debug, Default)]
// pub struct CharacterCell {
//     pub ascii_code: u8,
//     pub foreground_color: [f32; 4], // RGBA
//     pub background_color: [f32; 4], // RGBA
//     pub is_bold: bool,
//     pub is_underlined: bool,
// }

// impl CharacterCell {
//     pub fn new() -> Self {
//         Self {
//             ascii_code: 32, // Space
//             foreground_color: [1.0, 1.0, 1.0, 1.0],
//             background_color: [0.0, 0.0, 0.0, 0.0],
//             is_bold: false,
//             is_underlined: false,
//         }
//     }
// }

// pub struct Buffer {
//     pub buffer: Vec<CharacterCell>,
//     buffer_start: usize, // Start of circular buffer

//     pub rows: usize,
//     pub cols: usize,

//     cursor_x: usize,
//     cursor_y: usize,

//     current_attributes: CharacterCell,
// }

// impl Buffer {
//     pub fn new(rows: usize, cols: usize) -> Self {
//         Self {
//             buffer: vec![CharacterCell::new(); rows * cols],
//             buffer_start: 0,
//             rows,
//             cols,
//             cursor_x: 0,
//             cursor_y: 0,
//             current_attributes: CharacterCell::new(),
//         }
//     }

//     pub fn get_cell(&self, row: usize, col: usize) -> CharacterCell {
//         let idx = self.index(row, col);
//         self.buffer[idx]
//     }

//     // Convert 2D coordinates to 1D index
//     #[inline(always)]
//     fn index(&self, row: usize, col: usize) -> usize {
//         let real_row = (self.buffer_start + row) % self.rows;
//         real_row * self.cols + col
//     }

//     // Scroll one line up
//     pub fn scroll_up(&mut self) {
//         self.buffer_start = (self.buffer_start + 1) % self.rows;
//         // Clear new line
//         let new_line_start = self.index(self.rows - 1, 0);
//         for col in 0..self.cols {
//             self.buffer[new_line_start + col] = CharacterCell::new();
//         }
//     }

//     // Cursor Movement
//     pub fn move_cursor_up(&mut self, n: usize) {
//         self.cursor_y = self.cursor_y.saturating_sub(n);
//     }

//     pub fn move_cursor_down(&mut self, n: usize) {
//         self.cursor_y = usize::min(self.cursor_y + n, self.rows - 1);
//     }

//     pub fn move_cursor_forward(&mut self, n: usize) {
//         self.cursor_x = usize::min(self.cursor_x + n, self.cols - 1);
//     }

//     pub fn move_cursor_backward(&mut self, n: usize) {
//         self.cursor_x = self.cursor_x.saturating_sub(n);
//     }

//     pub fn set_cursor_position(&mut self, x: usize, y: usize) {
//         self.cursor_x = usize::min(x, self.cols - 1);
//         self.cursor_y = usize::min(y, self.rows - 1);
//     }

//     // Erase Functions
//     pub fn erase_in_display(&mut self, mode: usize) {
//         match mode {
//             0 => self.erase_below(),
//             1 => self.erase_above(),
//             2 => {
//                 self.buffer = vec![CharacterCell::new(); self.rows * self.cols];
//                 self.set_cursor_position(0, 0);
//             }
//             _ => {}
//         }
//     }

//     pub fn erase_in_line(&mut self, mode: usize) {
//         match mode {
//             0 => self.erase_line_from_cursor(),
//             1 => self.erase_line_to_cursor(),
//             2 => self.erase_entire_line(),
//             _ => {}
//         }
//     }

//     // Apply Graphic Rendition
//     pub fn apply_graphic_rendition(&mut self, params: &[usize]) {
//         for &code in params {
//             match code {
//                 0 => self.reset_attributes(),
//                 1 => {
//                     self.current_attributes.is_bold = true;
//                 }
//                 4 => {
//                     self.current_attributes.is_underlined = true;
//                 }
//                 30..=37 => {
//                     self.current_attributes.foreground_color = self.ansi_color(code - 30);
//                 }
//                 40..=47 => {
//                     self.current_attributes.background_color = self.ansi_color(code - 40);
//                 }
//                 _ => {}
//             }
//         }
//     }

//     // Append Character
//     pub fn append_char(&mut self, byte: u8) {
//         // if self.cursor_y >= self.rows || self.cursor_x >= self.cols {
//         //     return;
//         // }

//         let mut cell = self.current_attributes;
//         cell.ascii_code = byte;
//         let idx = self.index(self.cursor_y, self.cursor_x);
//         self.buffer[idx] = cell;

//         self.cursor_x += 1;
//         // if self.cursor_x >= self.cols {
//         //     self.cursor_x = 0;
//         //     self.cursor_y += 1;

//         //     if self.cursor_y >= self.rows {
//         //         self.scroll_up();
//         //         self.cursor_y = self.rows - 1;
//         //     }
//         // }
//     }

//     // Append Bytes
//     pub fn append_bytes(&mut self, bytes: &[u8]) {
//         let mut start = 0;
//         while start < bytes.len() {
//             // Space left in the current row
//             let space_in_row = self.cols.saturating_sub(self.cursor_x);

//             // Number of bytes we can place in the current row
//             let chunk_size = usize::min(space_in_row, bytes.len() - start);

//             // Bulk copy
//             let idx_start = self.index(self.cursor_y, self.cursor_x);
//             let mut cell = self.current_attributes;
//             for (offset, &byte) in bytes[start..start + chunk_size].iter().enumerate() {
//                 if byte == b'\r' {
//                     self.add_carriage_return();
//                     self.cursor_x = 0;
//                     continue;
//                 } else if byte == b'\n' {
//                     self.add_new_line();
//                     continue;
//                 }

//                 cell.ascii_code = byte;
//                 self.buffer[idx_start + offset] = cell;
//             }

//             // Advance cursor
//             self.cursor_x += chunk_size;
//             start += chunk_size;
//         }
//     }

//     // Handle Backspace
//     pub fn handle_backspace(&mut self) {
//         self.cursor_x -= 1;
//         let idx = self.index(self.cursor_y, self.cursor_x);
//         self.buffer[idx] = CharacterCell::new();
//     }

//     // Carriage Return and Line Feed
//     pub fn add_carriage_return(&mut self) {
//         self.cursor_x = 0;
//     }

//     pub fn add_line_feed(&mut self) {
//         self.cursor_y += 1;
//         if self.cursor_y >= self.rows {
//             self.scroll_up();
//             self.cursor_y = self.rows - 1;
//         }
//     }

//     pub fn add_new_line(&mut self) {
//         self.add_carriage_return();
//         self.add_line_feed();
//     }

//     pub fn advance_cursor_to_next_tab_stop(&mut self) {
//         let tab_size = 8;
//         let next_tab_stop = (self.cursor_x / tab_size + 1) * tab_size;
//         self.cursor_x = usize::min(next_tab_stop, self.cols - 1);
//     }

//     pub fn reset_attributes(&mut self) {
//         self.current_attributes = CharacterCell::new();
//     }

//     fn ansi_color(&self, code: usize) -> [f32; 4] {
//         match code {
//             0 => [0.0, 0.0, 0.0, 1.0], // Black
//             1 => [1.0, 0.0, 0.0, 1.0], // Red
//             2 => [0.0, 1.0, 0.0, 1.0], // Green
//             3 => [1.0, 1.0, 0.0, 1.0], // Yellow
//             4 => [0.0, 0.0, 1.0, 1.0], // Blue
//             5 => [1.0, 0.0, 1.0, 1.0], // Magenta
//             6 => [0.0, 1.0, 1.0, 1.0], // Cyan
//             7 => [1.0, 1.0, 1.0, 1.0], // White
//             _ => [1.0, 1.0, 1.0, 1.0],
//         }
//     }

//     // Erase Implementations
//     fn erase_below(&mut self) {
//         // Clear current line from cursor
//         for col in self.cursor_x..self.cols {
//             let idx = self.index(self.cursor_y, col);
//             self.buffer[idx] = CharacterCell::new();
//         }
//         // Clear all lines below
//         for row in self.cursor_y + 1..self.rows {
//             for col in 0..self.cols {
//                 let idx = self.index(row, col);
//                 self.buffer[idx] = CharacterCell::new();
//             }
//         }
//     }

//     fn erase_above(&mut self) {
//         // Clear current line up to cursor
//         for col in 0..=self.cursor_x {
//             let idx = self.index(self.cursor_y, col);
//             self.buffer[idx] = CharacterCell::new();
//         }
//         // Clear all lines above
//         for row in 0..self.cursor_y {
//             for col in 0..self.cols {
//                 let idx = self.index(row, col);
//                 self.buffer[idx] = CharacterCell::new();
//             }
//         }
//     }

//     fn erase_line_from_cursor(&mut self) {
//         for col in self.cursor_x..self.cols {
//             let idx = self.index(self.cursor_y, col);
//             self.buffer[idx] = CharacterCell::new();
//         }
//     }

//     fn erase_line_to_cursor(&mut self) {
//         for col in 0..=self.cursor_x {
//             let idx = self.index(self.cursor_y, col);
//             self.buffer[idx] = CharacterCell::new();
//         }
//     }

//     fn erase_entire_line(&mut self) {
//         for col in 0..self.cols {
//             let idx = self.index(self.cursor_y, col);
//             self.buffer[idx] = CharacterCell::new();
//         }
//     }

//     // Resizing the buffer
//     pub fn resize(&mut self, new_rows: usize, new_cols: usize) {
//         let mut new_buffer = vec![CharacterCell::new(); new_rows * new_cols];

//         for row in 0..usize::min(self.rows, new_rows) {
//             for col in 0..usize::min(self.cols, new_cols) {
//                 let old_index = self.index(row, col);
//                 let new_index = row * new_cols + col;
//                 new_buffer[new_index] = self.buffer[old_index];
//             }
//         }

//         self.buffer = new_buffer;
//         self.rows = new_rows;
//         self.cols = new_cols;
//         self.buffer_start = 0;
//         self.cursor_x = usize::min(self.cursor_x, new_cols - 1);
//         self.cursor_y = usize::min(self.cursor_y, new_rows - 1);
//     }
// }

#[derive(Debug)]
pub struct TextBuffer {
    /// Rows of indices into the text_fields array
    pub rows: Vec<Row>,
    /// Continous list of cells (text)
    pub text_fields: Vec<Cell>,
    /// Grapheme Lookaside Table (ascii for now)
    lookaside_table: LookasideTable,
    /// x-position of cursor
    pub cursor_x: usize,

    pub num_cols: usize,
    pub num_rows: usize,
}

/// The index of the text_field at which the row starts
#[derive(Clone, Copy, Debug)]
pub struct Row {
    pub idx: u16, // 65,536 rows
}

#[derive(Clone, Copy, Debug)]
pub struct Cell {
    // style_idx: usize,
    pub grapheme_idx: usize,
}

#[derive(Debug)]
struct LookasideTable {
    data: Vec<u8>,
}

impl LookasideTable {
    fn new() -> Self {
        Self {
            data: (0..128u8).collect(),
        }
    }
}

impl TextBuffer {
    pub fn new(num_rows: usize, num_cols: usize) -> Self {
        let mut rows = Vec::with_capacity(num_rows);
        rows.push(Row { idx: 0 });

        Self {
            rows,
            text_fields: Vec::with_capacity(num_rows * num_cols),
            num_cols,
            num_rows,
            cursor_x: 0,
            lookaside_table: LookasideTable::new(),
        }
    }

    pub fn append_char(&mut self, c: u8) {
        let grapheme_idx = self.lookaside_table.data[c as usize] as usize;
        let current_row_idx = self.rows.last().expect("No rows").idx as usize;
        while self.text_fields.len() <= current_row_idx + self.cursor_x {
            self.text_fields.push(Cell {
                grapheme_idx: 0,
            });
        }

        self.text_fields[current_row_idx + self.cursor_x] = Cell {
            grapheme_idx,
        };
        self.cursor_x += 1;
    }

    pub fn append_bytes(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.append_char(byte);
        }
    }

    pub fn get_row(&self, row: Row) -> &[Cell] {
        let start = row.idx as usize;
        let end = self.rows
            .get((row.idx as usize) + 1)
            .map(|r| r.idx as usize)
            .unwrap_or(self.text_fields.len());
        &self.text_fields[start..end]
    }

    pub fn get_char(&self, cell: Cell) -> char {
        self.lookaside_table.data[cell.grapheme_idx as usize] as char
    }

    pub fn newline(&mut self) {
        self.rows.push(Row {
            idx: self.text_fields.len() as u16,
        });
    }

    pub fn backspace(&mut self) {
        self.text_fields.pop();
    }

    pub fn carriage_return(&mut self) {
        self.cursor_x = 0;
    }

    pub fn advance_cursor_to_next_tab_stop(&mut self) {
        let tab_size = 8;
        for _ in 0..tab_size {
            self.append_char(b' ');
        }
    }

    pub fn move_cursor_up(&mut self, n: usize) {
        // for _ in 0..n {
        //     self.rows.pop();
        // }
    }

    pub fn move_cursor_down(&mut self, n: usize) {
        // for _ in 0..n {
        //     self.newline();
        // }
    }

    pub fn move_cursor_forward(&mut self, n: usize) {
        // for _ in 0..n {
        //     self.append_char(b' ');
        // }
    }

    pub fn move_cursor_backward(&mut self, n: usize) {
        // for _ in 0..n {
        //     self.text_fields.pop();
        // }
    }

    pub fn set_cursor_position(&mut self, x: usize, y: usize) {
        // let row = self.rows.get(y).expect("Invalid row");
        // let start = row.idx as usize;
        // let end = self.rows
        //     .get((row.idx as usize) + 1)
        //     .map(|r| r.idx as usize)
        //     .unwrap_or(self.text_fields.len());
        // let len = end - start;
        // let new_len = start + x;
        // if new_len > len {
        //     for _ in 0..new_len - len {
        //         self.append_char(b' ');
        //     }
        // }
    }

    pub fn erase_below(&mut self) {
        // let row = self.rows.last().expect("No rows");
        // let start = row.idx as usize;
        // self.text_fields.truncate(start);
    }

    pub fn erase_above(&mut self) {
        // let row = self.rows.last().expect("No rows");
        // let start = row.idx as usize;
        // self.text_fields.drain(0..start);
    }

    pub fn erase_in_display(&mut self, mode: usize) {
        // match mode {
        //     0 => self.erase_below(),
        //     1 => self.erase_above(),
        //     2 => {
        //         self.text_fields.clear();
        //         self.rows.clear();
        //     }
        //     _ => {}
        // }
    }

    pub fn erase_in_line(&mut self, mode: usize) {
        // match mode {
        //     0 => self.erase_line_from_cursor(),
        //     1 => self.erase_line_to_cursor(),
        //     2 => self.erase_entire_line(),
        //     _ => {}
        // }
    }

    pub fn apply_graphic_rendition(&mut self, params: &[usize]) {
        for &code in params {
            match code {
                // 0 => self.reset_attributes(),
                1 => {
                    // self.current_attributes.is_bold = true;
                }
                4 => {
                    // self.current_attributes.is_underlined = true;
                }
                30..=37 => {
                    // self.current_attributes.foreground_color = self.ansi_color(code - 30);
                }
                40..=47 => {
                    // self.current_attributes.background_color = self.ansi_color(code - 40);
                }
                _ => {}
            }
        }
    }
}
