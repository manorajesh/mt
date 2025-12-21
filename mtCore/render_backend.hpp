//
//  render_backend.hpp
//  mt
//
//  Created by Mano Rajesh on 12/21/25.
//

#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>
#include <atomic>
#include <algorithm>

struct RenderCell {
    // Keep this tiny. Expand later (attrs/colors/width flags).
    uint32_t codepoint; // ASCII/Unicode codepoint (or glyph index if you want)
    uint32_t attr;      // packed attributes (fg/bg/bold/etc.) - optional
};

// Matches what your shader instance wants (adapt as needed).
// Keep it POD and tightly packed.
#pragma pack(push, 1)
struct CellInstanceCPU {
    uint16_t col;
    uint16_t row;
    uint32_t glyph;  // codepoint or glyph index
    uint32_t attr;   // packed
};
#pragma pack(pop)

struct DirtyRows {
    // Bitset rows; words = (rows+63)/64
    std::vector<uint64_t> bits;
    void resize(size_t rows) { bits.assign((rows + 63) / 64, 0); }
    void clear() { std::fill(bits.begin(), bits.end(), 0); }
    void set(size_t row) { bits[row >> 6] |= (1ull << (row & 63)); }
    bool test(size_t row) const { return (bits[row >> 6] >> (row & 63)) & 1ull; }
    bool any() const {
        for (uint64_t w : bits) if (w) return true;
        return false;
    }
};

class RenderBackend {
public:
    struct Config {
        uint16_t cols = 80;
        uint16_t rows = 24;
    };
    
    struct FrameView {
        uint64_t seq = 0;
        uint16_t cols = 0;
        uint16_t rows = 0;
        
        // Row i instances live at rowPtr(i) with rowCount(i) elements.
        const DirtyRows* dirty = nullptr;
        
        const CellInstanceCPU* rowPtr(uint16_t row) const;
        uint32_t rowCount(uint16_t row) const;
        
    private:
        friend class RenderBackend;
        const CellInstanceCPU* _instances = nullptr;
        const uint32_t* _rowOffsets = nullptr;
        const uint32_t* _rowCounts  = nullptr;
    };
    
    RenderBackend();
    ~RenderBackend() = default;
    
    RenderBackend(const RenderBackend&) = delete;
    RenderBackend& operator=(const RenderBackend&) = delete;
    
    // Call on resize. Allocates fixed storage: rows * cols instances per frame (2 frames).
    void configure(Config cfg);
    
    uint16_t cols() const { return _cfg.cols; }
    uint16_t rows() const { return _cfg.rows; }
    
    // ---- Parser thread API ----
    
    // Begin writing into back frame; clears dirty bitset.
    void beginUpdate();
    
    // Rebuild one row from a contiguous array of RenderCell (length = cols).
    // Marks row dirty in the back frame.
    // Fast: single scan, writes compacted instances into fixed row segment.
    void updateRow(uint16_t row, const RenderCell* cells);
    
    // If you already have dirty bitset+min/max ranges, call this per row and optionally
    // only scan [col0,col1). This saves work when tiny edits happen.
    void updateRowRange(uint16_t row, const RenderCell* cells, uint16_t col0, uint16_t col1);
    
    // Publish back frame -> front for renderer; returns new seq.
    uint64_t publish();
    
    // ---- Render thread API ----
    
    // Acquire latest published frame (cheap). If seq unchanged, nothing new.
    FrameView acquireLatest();
    
private:
    struct Frame {
        uint64_t seq = 0;
        DirtyRows dirty;
        
        // Fixed layout:
        // row i uses instances[ i*cols .. i*cols + cols ) as capacity
        std::vector<CellInstanceCPU> instances;
        
        // counts per row; offsets are i*cols (precomputed) but we keep offsets array for convenience
        std::vector<uint32_t> rowOffsets;
        std::vector<uint32_t> rowCounts;
        
        void alloc(uint16_t cols, uint16_t rows);
        void clearDirtyAndCounts();
    };
    
    Config _cfg{};
    
    Frame _frames[2];
    uint32_t _backIdx = 0;
    
    // Published index/seq (renderer reads)
    std::atomic<uint32_t> _publishedIdx{0};
    std::atomic<uint64_t> _publishedSeq{0};
    
    // Next seq to publish (parser thread only)
    uint64_t _nextSeq = 1;
};
