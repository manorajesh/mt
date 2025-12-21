//
//  terminal_model.cpp
//  mt
//
//  Created by Mano Rajesh on 12/21/25.
//

#include "terminal_model.hpp"
#include <algorithm>
#include <cstring>

static constexpr uint32_t kSpace = ' ';

TerminalModel::TerminalModel(uint16_t cols,
                             uint16_t rows,
                             RenderBackend& backend)
: _cols(cols), _rows(rows), _backend(backend) {
    _grid.resize((size_t)cols * rows);
    _dirty.resize(rows, 1);
    
    for (auto& c : _grid) {
        c.codepoint = kSpace;
        c.attr = 0;
    }
    
    flushDirtyRows();
}

void TerminalModel::resize(uint16_t cols, uint16_t rows) {
    _cols = cols;
    _rows = rows;
    
    _grid.assign((size_t)cols * rows, {kSpace, 0});
    _dirty.assign(rows, 1);
    
    _curCol = 0;
    _curRow = 0;
    
    _backend.configure({cols, rows});
    flushDirtyRows();
}

void TerminalModel::markRowDirty(uint16_t r) {
    if (r < _rows) _dirty[r] = 1;
}

void TerminalModel::flushDirtyRows() {
    _backend.beginUpdate();
    for (uint16_t r = 0; r < _rows; ++r) {
        if (_dirty[r]) {
            _backend.updateRow(r, &_grid[idx(r, 0)]);
            _dirty[r] = 0;
        }
    }
}

void TerminalModel::putBytes(const uint8_t* bytes, size_t len) {
    for (size_t i = 0; i < len; ++i) {
        uint8_t b = bytes[i];
        if (b < 32 || b >= 127) b = '?';
        
        size_t p = idx(_curRow, _curCol);
        _grid[p].codepoint = b;
        markRowDirty(_curRow);
        
        if (++_curCol >= _cols) {
            _curCol = 0;
            if (++_curRow >= _rows) scrollUp();
        }
    }
    flushDirtyRows();
}

void TerminalModel::carriageReturn() {
    _curCol = 0;
}

void TerminalModel::lineFeed() {
    _curCol = 0;
    if (++_curRow >= _rows) scrollUp();
}

void TerminalModel::backspace() {
    if (_curCol > 0) _curCol--;
}

void TerminalModel::tab() {
    _curCol = std::min<uint16_t>((_curCol + 8) & ~7, _cols - 1);
}

void TerminalModel::cursorUp(int n) {
    _curRow = (uint16_t)std::max(0, _curRow - n);
}

void TerminalModel::cursorDown(int n) {
    _curRow = (uint16_t)std::min<int>(_rows - 1, _curRow + n);
}

void TerminalModel::cursorForward(int n) {
    _curCol = (uint16_t)std::min<int>(_cols - 1, _curCol + n);
}

void TerminalModel::cursorBack(int n) {
    _curCol = (uint16_t)std::max(0, _curCol - n);
}

void TerminalModel::cursorPosition(int row1, int col1) {
    _curRow = (uint16_t)std::clamp(row1 - 1, 0, (int)_rows - 1);
    _curCol = (uint16_t)std::clamp(col1 - 1, 0, (int)_cols - 1);
}

void TerminalModel::eraseInLine(int mode) {
    uint16_t r = _curRow;
    
    uint16_t start = 0;
    uint16_t end = _cols;
    
    if (mode == 0) start = _curCol;
    else if (mode == 1) end = _curCol + 1;
    
    for (uint16_t c = start; c < end; ++c) {
        _grid[idx(r, c)].codepoint = kSpace;
    }
    markRowDirty(r);
    flushDirtyRows();
}

void TerminalModel::eraseInDisplay(int mode) {
    if (mode == 2) {
        for (auto& c : _grid) c.codepoint = kSpace;
        std::fill(_dirty.begin(), _dirty.end(), 1);
        flushDirtyRows();
    }
}

void TerminalModel::scrollUp() {
    memmove(_grid.data(),
            _grid.data() + _cols,
            sizeof(RenderCell) * (_rows - 1) * _cols);
    
    std::fill(&_grid[idx(_rows - 1, 0)],
              &_grid[idx(_rows, 0)],
              RenderCell{kSpace, 0});
    
    std::fill(_dirty.begin(), _dirty.end(), 1);
    _curRow = _rows - 1;
    _curCol = 0;
}
