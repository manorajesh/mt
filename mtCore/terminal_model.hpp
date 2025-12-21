//
//  terminal_model.hpp
//  mt
//
//  Created by Mano Rajesh on 12/21/25.
//

#pragma once
#include "parser.hpp"
#include "render_backend.hpp"

#include <vector>
#include <cstdint>

class TerminalModel final : public TerminalOps {
public:
    TerminalModel(uint16_t cols, uint16_t rows, RenderBackend& backend);
    
    // ---- TerminalOps ----
    void putBytes(const uint8_t* bytes, size_t len) override;
    
    void bell() override {}
    void carriageReturn() override;
    void lineFeed() override;
    void backspace() override;
    void tab() override;
    
    void cursorUp(int n) override;
    void cursorDown(int n) override;
    void cursorForward(int n) override;
    void cursorBack(int n) override;
    void cursorPosition(int row1, int col1) override;
    
    void eraseInDisplay(int mode) override;
    void eraseInLine(int mode) override;
    
    void sgrReset() override {};
    void sgrBold(bool) override {}
    void sgrUnderline(bool) override {}
    void sgrInverse(bool) override {}
    void sgrFgIndex(int) override {}
    void sgrBgIndex(int) override {}
    
    // ---- resize ----
    void resize(uint16_t cols, uint16_t rows);
    
private:
    inline size_t idx(uint16_t r, uint16_t c) const {
        return (size_t)r * _cols + c;
    }
    
    void markRowDirty(uint16_t r);
    void flushDirtyRows();
    void scrollUp();
    
private:
    uint16_t _cols;
    uint16_t _rows;
    
    uint16_t _curCol = 0;
    uint16_t _curRow = 0;
    
    std::vector<RenderCell> _grid;
    std::vector<uint8_t> _dirty; // per row
    
    RenderBackend& _backend;
};
