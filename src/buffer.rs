pub struct Buffer {
    pub buffer: Vec<u8>,
    pub top_row: usize, // Current top visible row in the viewport

    pub rows: usize,
    pub cols: usize,

    cursor_x: usize,
    cursor_y: usize,

    current_attributes: u8,
}

impl Buffer {
    pub fn new(rows: usize, cols: usize) -> Self {
        Self {
            buffer: vec![0; rows * cols],
            top_row: 0,
            rows,
            cols,
            cursor_x: 0,
            cursor_y: 0,
            current_attributes: 32,
        }
    }

    /// Return the character at (row, col) in the *visible* region.
    /// Maps `row` to `top_row + row` in the buffer.
    pub fn get_cell(&self, row: usize, col: usize) -> u8 {
        let real_row = self.top_row + row;
        let real_index = real_row.saturating_mul(self.cols) + col;

        if real_index < self.buffer.len() {
            self.buffer[real_index]
        } else {
            // Out-of-bounds => blank cell.
            32
        }
    }

    /// Compute a 1D index for the *current* cursor position in the buffer.
    /// That position is `top_row + cursor_y` from the top of the entire buffer.
    fn index(&self, row: usize, col: usize) -> usize {
        let real_row = self.top_row + row;
        real_row.saturating_mul(self.cols) + col
    }

    // Scroll the visible window “up” one line (if possible).
    pub fn scroll_view_up(&mut self) {
        // Only scroll up if there's more buffer data below the window.
        // Example check: top_row + rows < total number of lines in buffer
        // (i.e. we haven't scrolled all the way to the bottom).
        let total_rows_in_buffer = self.buffer.len() / self.cols;
        if self.top_row + self.rows < total_rows_in_buffer {
            self.top_row += 1;
        }
    }

    // Scroll the visible window “down” one line (if possible).
    pub fn scroll_view_down(&mut self) {
        if self.top_row > 0 {
            self.top_row -= 1;
        }
    }

    // Writes a single character at the current cursor, then advances cursor_x.
    pub fn append_char(&mut self, byte: u8) {
        // let mut cell = self.current_attributes;
        // cell.ascii_code = byte;

        // Ensure the buffer is large enough for current_index().
        let idx = self.index(self.cursor_y, self.cursor_x);
        self.buffer[idx] = byte;

        // Move cursor forward in the visible region.
        self.cursor_x += 1;
        // if self.cursor_x >= self.cols {
        //     self.cursor_x = 0;
        //     self.cursor_y += 1;

        //     // If we go off the bottom of the “window,” insert a new line (scrollback).
        //     if self.cursor_y >= self.rows {
        //         self.add_line_feed();
        //     }
        // }
    }

    pub fn append_bytes(&mut self, bytes: &[u8]) {
        if bytes.contains(&b'\n') {
            for &byte in bytes {
                if byte == b'\r' {
                    self.add_carriage_return();
                } else if byte == b'\n' {
                    self.add_new_line();
                } else {
                    self.append_char(byte);
                }
            }
        } else {
            let idx = self.index(self.cursor_y, self.cursor_x);
            self.buffer[idx..idx + bytes.len()].copy_from_slice(bytes);
            self.cursor_x += bytes.len();
        }
    }

    // Cursor movement methods (unchanged)
    pub fn move_cursor_up(&mut self, n: usize) {
        self.cursor_y = self.cursor_y.saturating_sub(n);
    }

    pub fn move_cursor_down(&mut self, n: usize) {
        self.cursor_y = usize::min(self.cursor_y + n, self.rows - 1);
    }

    pub fn move_cursor_forward(&mut self, n: usize) {
        self.cursor_x = usize::min(self.cursor_x + n, self.cols - 1);
    }

    pub fn move_cursor_backward(&mut self, n: usize) {
        self.cursor_x = self.cursor_x.saturating_sub(n);
    }

    pub fn set_cursor_position(&mut self, x: usize, y: usize) {
        self.cursor_x = usize::min(x, self.cols - 1);
        self.cursor_y = usize::min(y, self.rows - 1);
    }

    // Erase Functions
    pub fn erase_in_display(&mut self, mode: usize) {
        match mode {
            0 => self.erase_below(),
            1 => self.erase_above(),
            2 => {
                self.buffer = vec![32; self.rows * self.cols];
                self.set_cursor_position(0, 0);
            }
            _ => {}
        }
    }

    pub fn erase_in_line(&mut self, mode: usize) {
        match mode {
            0 => self.erase_line_from_cursor(),
            1 => self.erase_line_to_cursor(),
            2 => self.erase_entire_line(),
            _ => {}
        }
    }

    // Apply Graphic Rendition
    pub fn apply_graphic_rendition(&mut self, params: &[usize]) {
        // for &code in params {
        //     match code {
        //         0 => self.reset_attributes(),
        //         1 => {
        //             self.current_attributes.is_bold = true;
        //         }
        //         4 => {
        //             self.current_attributes.is_underlined = true;
        //         }
        //         30..=37 => {
        //             self.current_attributes.foreground_color = self.ansi_color(code - 30);
        //         }
        //         40..=47 => {
        //             self.current_attributes.background_color = self.ansi_color(code - 40);
        //         }
        //         _ => {}
        //     }
        // }
    }

    // Append Bytes
    // pub fn append_bytes(&mut self, bytes: &[u8]) {
    //     let mut start = 0;
    //     while start < bytes.len() {
    //         // Space left in the current row
    //         let space_in_row = self.cols.saturating_sub(self.cursor_x);

    //         // Number of bytes we can place in the current row
    //         let chunk_size = usize::min(space_in_row, bytes.len() - start);

    //         // Bulk copy
    //         let idx_start = self.index(self.cursor_y, self.cursor_x);
    //         let mut cell = self.current_attributes;
    //         for (offset, &byte) in bytes[start..start + chunk_size].iter().enumerate() {
    //             if byte == b'\r' {
    //                 self.add_carriage_return();
    //                 self.cursor_x = 0;
    //                 continue;
    //             } else if byte == b'\n' {
    //                 self.add_new_line();
    //                 continue;
    //             }

    //             cell.ascii_code = byte;
    //             self.buffer[idx_start + offset] = cell;
    //         }

    //         // Advance cursor
    //         self.cursor_x += chunk_size;
    //         start += chunk_size;
    //     }
    // }

    // Handle Backspace
    pub fn handle_backspace(&mut self) {
        self.cursor_x -= 1;
        let idx = self.index(self.cursor_y, self.cursor_x);
        self.buffer[idx] = 32;
    }

    // Carriage Return and Line Feed
    pub fn add_carriage_return(&mut self) {
        self.cursor_x = 0;
    }

    pub fn add_line_feed(&mut self) {
        // Extend buffer by one blank line (cols wide).
        self.buffer.extend_from_slice(&vec![32; self.cols]);

        // Shift the window’s top row one down in the buffer.
        self.top_row += 1;

        // Keep the cursor pinned to the bottom row of the visible region.
        // (Typical terminal behavior.)
        self.cursor_y = self.rows - 1;
    }

    pub fn add_new_line(&mut self) {
        self.add_carriage_return();
        self.add_line_feed();
    }

    pub fn advance_cursor_to_next_tab_stop(&mut self) {
        let tab_size = 8;
        let next_tab_stop = (self.cursor_x / tab_size + 1) * tab_size;
        self.cursor_x = usize::min(next_tab_stop, self.cols - 1);
    }

    pub fn reset_attributes(&mut self) {
        self.current_attributes = 32;
    }

    fn ansi_color(&self, code: usize) -> [f32; 4] {
        match code {
            0 => [0.0, 0.0, 0.0, 1.0], // Black
            1 => [1.0, 0.0, 0.0, 1.0], // Red
            2 => [0.0, 1.0, 0.0, 1.0], // Green
            3 => [1.0, 1.0, 0.0, 1.0], // Yellow
            4 => [0.0, 0.0, 1.0, 1.0], // Blue
            5 => [1.0, 0.0, 1.0, 1.0], // Magenta
            6 => [0.0, 1.0, 1.0, 1.0], // Cyan
            7 => [1.0, 1.0, 1.0, 1.0], // White
            _ => [1.0, 1.0, 1.0, 1.0],
        }
    }

    // Erase Implementations
    fn erase_below(&mut self) {
        // Clear current line from cursor
        for col in self.cursor_x..self.cols {
            let idx = self.index(self.cursor_y, col);
            self.buffer[idx] = 32;
        }
        // Clear all lines below
        for row in self.cursor_y + 1..self.rows {
            for col in 0..self.cols {
                let idx = self.index(row, col);
                self.buffer[idx] = 32;
            }
        }
    }

    fn erase_above(&mut self) {
        // Clear current line up to cursor
        for col in 0..=self.cursor_x {
            let idx = self.index(self.cursor_y, col);
            self.buffer[idx] = 32;
        }
        // Clear all lines above
        for row in 0..self.cursor_y {
            for col in 0..self.cols {
                let idx = self.index(row, col);
                self.buffer[idx] = 32;
            }
        }
    }

    fn erase_line_from_cursor(&mut self) {
        for col in self.cursor_x..self.cols {
            let idx = self.index(self.cursor_y, col);
            self.buffer[idx] = 32;
        }
    }

    fn erase_line_to_cursor(&mut self) {
        for col in 0..=self.cursor_x {
            let idx = self.index(self.cursor_y, col);
            self.buffer[idx] = 32;
        }
    }

    fn erase_entire_line(&mut self) {
        for col in 0..self.cols {
            let idx = self.index(self.cursor_y, col);
            self.buffer[idx] = 32;
        }
    }

    // Resizing the buffer
    pub fn resize(&mut self, new_rows: usize, new_cols: usize) {
        let mut new_buffer = vec![32; new_rows * new_cols];

        for row in 0..usize::min(self.rows, new_rows) {
            for col in 0..usize::min(self.cols, new_cols) {
                let old_index = self.index(row, col);
                let new_index = row * new_cols + col;
                new_buffer[new_index] = self.buffer[old_index];
            }
        }

        self.buffer = new_buffer;
        self.rows = new_rows;
        self.cols = new_cols;
        self.top_row = 0;
        self.cursor_x = usize::min(self.cursor_x, new_cols - 1);
        self.cursor_y = usize::min(self.cursor_y, new_rows - 1);
    }
}

// #[derive(Debug)]
// pub struct TextBuffer {
//     /// Rows of indices into the text_fields array
//     pub rows: Vec<Row>,
//     /// Continous list of cells (text)
//     pub text_fields: Vec<Cell>,
//     /// Grapheme Lookaside Table (ascii for now)
//     lookaside_table: LookasideTable,

//     cursor_row: usize,
//     cursor_col: usize,

//     pub num_cols: usize,
//     pub num_rows: usize,
// }

// /// The index of the text_field at which the row starts
// #[derive(Clone, Copy, Debug)]
// pub struct Row {
//     pub idx: u16, // 65,536 rows
// }

// #[derive(Clone, Copy, Debug)]
// pub struct Cell {
//     // style_idx: usize,
//     pub grapheme_idx: usize,
// }

// #[derive(Debug)]
// struct LookasideTable {
//     data: Vec<u8>,
// }

// impl LookasideTable {
//     fn new() -> Self {
//         Self {
//             data: (0..128u8).collect(),
//         }
//     }
// }

// impl TextBuffer {
//     pub fn new(num_rows: usize, num_cols: usize) -> Self {
//         let mut rows = Vec::with_capacity(num_rows);
//         rows.push(Row { idx: 0 });

//         Self {
//             rows,
//             text_fields: Vec::with_capacity(num_rows * num_cols),
//             num_cols,
//             num_rows,
//             cursor_row: 0,
//             cursor_col: 0,
//             lookaside_table: LookasideTable::new(),
//         }
//     }

//     pub fn append_char(&mut self, c: u8) {
//         let grapheme_idx = self.lookaside_table.data[c as usize] as usize;
//         let flat_index = (self.rows[self.cursor_row].idx as usize) + self.cursor_col;
//         if flat_index < self.text_fields.len() {
//             self.text_fields[flat_index] = Cell { grapheme_idx };
//         } else {
//             self.text_fields.push(Cell { grapheme_idx });
//         }
//         self.cursor_col += 1;
//         if self.cursor_col >= self.num_cols {
//             self.cursor_col = 0;
//             self.cursor_row += 1;
//             if self.cursor_row >= self.num_rows {
//                 self.cursor_row = 0;
//             }
//             self.rows.push(Row {
//                 idx: self.text_fields.len() as u16,
//             });
//             tracing::info!("New row: {:?}", self.rows.last());
//         }
//     }

//     pub fn append_bytes(&mut self, bytes: &[u8]) {
//         for &byte in bytes {
//             self.append_char(byte);
//         }
//     }

//     pub fn get_row(&self, row: Row) -> &[Cell] {
//         let start = row.idx as usize;
//         let end = self.rows
//             .get((row.idx as usize) + 1)
//             .map(|r| r.idx as usize)
//             .unwrap_or(self.text_fields.len());
//         &self.text_fields[start..end]
//     }

//     pub fn get_char(&self, cell: Cell) -> char {
//         self.lookaside_table.data[cell.grapheme_idx as usize] as char
//     }

//     pub fn newline(&mut self) {
//         self.cursor_row += 1;
//         self.cursor_col = 0;
//         self.rows.push(Row {
//             idx: self.text_fields.len() as u16,
//         });
//     }

//     pub fn backspace(&mut self) {
//         self.text_fields.pop();
//     }

//     pub fn carriage_return(&mut self) {
//         self.cursor_col = 0;
//     }

//     pub fn advance_cursor_to_next_tab_stop(&mut self) {
//         let tab_size = 8;
//         for _ in 0..tab_size {
//             self.append_char(b' ');
//         }
//     }

//     pub fn move_cursor_up(&mut self, n: usize) {
//         self.cursor_row = self.cursor_row.saturating_sub(n);
//     }

//     pub fn move_cursor_down(&mut self, n: usize) {
//         self.cursor_row += n;
//     }

//     pub fn move_cursor_forward(&mut self, n: usize) {
//         self.cursor_col += n;
//     }

//     pub fn move_cursor_backward(&mut self, n: usize) {
//         self.cursor_col = self.cursor_col.saturating_sub(n);
//     }

//     pub fn set_cursor_position(&mut self, x: usize, y: usize) {
//         self.cursor_col = x;
//         self.cursor_row = y;
//     }

//     pub fn erase_below(&mut self) {
//         let row = self.rows.last().expect("No rows");
//         let start = row.idx as usize;
//         self.text_fields.truncate(start);
//     }

//     pub fn erase_above(&mut self) {
//         let row = self.rows.last().expect("No rows");
//         let start = row.idx as usize;
//         self.text_fields.drain(0..start);
//     }

//     pub fn erase_in_display(&mut self, mode: usize) {
//         match mode {
//             0 => self.erase_below(),
//             1 => self.erase_above(),
//             2 => {
//                 self.text_fields.clear();
//                 self.rows.clear();
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

//     pub fn erase_line_from_cursor(&mut self) {
//         let row = self.rows.last().expect("No rows");
//         let start = row.idx as usize;
//         let end = self.rows
//             .get((row.idx as usize) + 1)
//             .map(|r| r.idx as usize)
//             .unwrap_or(self.text_fields.len());
//         self.text_fields.drain(start + self.cursor_col..end);
//     }

//     pub fn erase_line_to_cursor(&mut self) {
//         let row = self.rows.last().expect("No rows");
//         let start = row.idx as usize;
//         self.text_fields.drain(start..start + self.cursor_col);
//     }

//     pub fn erase_entire_line(&mut self) {
//         let row = self.rows.last().expect("No rows");
//         let start = row.idx as usize;
//         let end = self.rows
//             .get((row.idx as usize) + 1)
//             .map(|r| r.idx as usize)
//             .unwrap_or(self.text_fields.len());
//         self.text_fields.drain(start..end);
//     }

//     pub fn apply_graphic_rendition(&mut self, params: &[usize]) {
//         for &code in params {
//             match code {
//                 // 0 => self.reset_attributes(),
//                 1 => {
//                     // self.current_attributes.is_bold = true;
//                 }
//                 4 => {
//                     // self.current_attributes.is_underlined = true;
//                 }
//                 30..=37 => {
//                     // self.current_attributes.foreground_color = self.ansi_color(code - 30);
//                 }
//                 40..=47 => {
//                     // self.current_attributes.background_color = self.ansi_color(code - 40);
//                 }
//                 _ => {}
//             }
//         }
//     }
// }
