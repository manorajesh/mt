//
//  render_backend.cpp
//  mt
//
//  Created by Mano Rajesh on 12/21/25.
//

#include "render_backend.hpp"
#include <cstring>
#include <algorithm>

static inline bool isDrawable(const RenderCell& c) {
    // For your current atlas: drawable ASCII 32..126 and not space.
    // Adjust when you support full Unicode / combining / wide chars.
    return (c.codepoint >= 32 && c.codepoint < 127 && c.codepoint != (uint32_t)' ');
}

const CellInstanceCPU* RenderBackend::FrameView::rowPtr(uint16_t row) const {
    return _instances + _rowOffsets[row];
}
uint32_t RenderBackend::FrameView::rowCount(uint16_t row) const {
    return _rowCounts[row];
}

void RenderBackend::Frame::alloc(uint16_t cols, uint16_t rows) {
    dirty.resize(rows);
    
    const size_t total = (size_t)cols * (size_t)rows;
    instances.resize(total);
    
    rowOffsets.resize(rows);
    rowCounts.resize(rows);
    
    for (uint16_t r = 0; r < rows; ++r) {
        rowOffsets[r] = (uint32_t)((size_t)r * (size_t)cols);
        rowCounts[r] = 0;
    }
}

void RenderBackend::Frame::clearDirtyAndCounts() {
    dirty.clear();
    std::fill(rowCounts.begin(), rowCounts.end(), 0);
}

RenderBackend::RenderBackend() {}

void RenderBackend::configure(Config cfg) {
    _cfg = cfg;
    _frames[0].alloc(cfg.cols, cfg.rows);
    _frames[1].alloc(cfg.cols, cfg.rows);
    
    _frames[0].seq = 0;
    _frames[1].seq = 0;
    
    _backIdx = 0;
    _publishedIdx.store(0, std::memory_order_release);
    _publishedSeq.store(0, std::memory_order_release);
    _nextSeq = 1;
}

void RenderBackend::beginUpdate() {
    Frame& f = _frames[_backIdx];
    f.clearDirtyAndCounts();
}

void RenderBackend::updateRow(uint16_t row, const RenderCell* cells) {
    updateRowRange(row, cells, 0, _cfg.cols);
}

void RenderBackend::updateRowRange(uint16_t row, const RenderCell* cells, uint16_t col0, uint16_t col1) {
    Frame& f = _frames[_backIdx];
    
    // We rebuild the whole row segment even if a small range changed, because we compact.
    // For best perf with small edits, call updateRowRange but still rebuild the row; the
    // range just lets you early-detect “no drawable changes” later if you want.
    (void)col0; (void)col1;
    
    const uint32_t base = f.rowOffsets[row];
    CellInstanceCPU* out = f.instances.data() + base;
    
    uint32_t count = 0;
    const uint16_t cols = _cfg.cols;
    
    // Tight scan over the row; no allocations; writes into fixed capacity.
    for (uint16_t c = 0; c < cols; ++c) {
        const RenderCell& rc = cells[c];
        if (!isDrawable(rc)) continue;
        
        CellInstanceCPU inst;
        inst.col = c;
        inst.row = row;
        inst.glyph = rc.codepoint; // or map to glyph index
        inst.attr  = rc.attr;
        
        out[count++] = inst;
    }
    
    f.rowCounts[row] = count;
    f.dirty.set(row);
}

uint64_t RenderBackend::publish() {
    // Publish back frame as newest.
    Frame& f = _frames[_backIdx];
    f.seq = _nextSeq++;
    
    // Make frame writes visible before publishing index/seq.
    std::atomic_thread_fence(std::memory_order_release);
    
    _publishedIdx.store(_backIdx, std::memory_order_release);
    _publishedSeq.store(f.seq, std::memory_order_release);
    
    // Swap back buffer
    _backIdx ^= 1;
    return f.seq;
}

RenderBackend::FrameView RenderBackend::acquireLatest() {
    FrameView v;
    
    // Read seq first; if 0, nothing published yet.
    uint64_t seq = _publishedSeq.load(std::memory_order_acquire);
    if (seq == 0) return v;
    
    uint32_t idx = _publishedIdx.load(std::memory_order_acquire);
    const Frame& f = _frames[idx];
    
    v.seq = seq;
    v.cols = _cfg.cols;
    v.rows = _cfg.rows;
    v.dirty = &f.dirty;
    
    v._instances = f.instances.data();
    v._rowOffsets = f.rowOffsets.data();
    v._rowCounts  = f.rowCounts.data();
    return v;
}
