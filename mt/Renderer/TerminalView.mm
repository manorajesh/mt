//
//  TerminalView.mm
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import "TerminalView.h"
#import "../../mtCore/mtCore.h"
#import <os/lock.h>
#import <simd/simd.h>
#import <CoreText/CoreText.h>
#import <algorithm>
#import <cstring>
#import <atomic>
#import <vector>
#import <string>

using namespace simd;

namespace {

constexpr size_t kMaxLogBytes = 1 << 20;
constexpr uint8_t kSpace = ' ';

struct CellInstanceCPU {
    uint16_t col;
    uint16_t row;
    uint8_t  glyph;
    uint8_t  flags;
};

struct UniformsCPU {
    float2 viewportPx;
    float2 cellPx;
    float2 atlasPx;
    uint32_t atlasCols;
    uint32_t firstChar;
    float2 pad;
};

} // namespace

@interface TerminalView () {
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLTexture> _atlas;
    
    id<MTLBuffer> _instanceBuffer;
    NSUInteger _instanceCapacityBytes;
    
    float _cellWidth;
    float _cellHeight;
    
    size_t _cols;
    size_t _rows;
    
    size_t _atlasCols;
    size_t _atlasRows;
    size_t _atlasW;
    size_t _atlasH;
    
    std::vector<uint8_t> _cells;
    size_t _cursorCol;
    size_t _cursorRow;
    std::string _log;
    
    os_unfair_lock _lock;
    std::atomic_bool _drawQueued;
    bool _dirty;
}
@end

@implementation TerminalView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect device:MTLCreateSystemDefaultDevice()];
    if (self) [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        self.device = MTLCreateSystemDefaultDevice();
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _lock = OS_UNFAIR_LOCK_INIT;
    _drawQueued.store(false);
    _dirty = true;
    
    self.delegate = self;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.clearColor = MTLClearColorMake(0.03, 0.05, 0.07, 1.0);
    
    if (!self.device) {
        NSLog(@"Metal not available");
        return;
    }
    
    _commandQueue = [self.device newCommandQueue];
    [self buildPipeline];
    [self buildAtlas];
    [self resizeGridForDrawableSize:self.drawableSize.width > 0 ? self.drawableSize : self.bounds.size];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    if (!self.core) return;
    NSString *chars = event.characters;
    NSData *data = [chars dataUsingEncoding:NSUTF8StringEncoding];
    self.core->send((const char *)data.bytes, data.length);
}

- (void)appendOutput:(const char *)data length:(size_t)len {
    if (!data || len == 0) return;
    
    os_unfair_lock_lock(&_lock);
    
    if (_log.size() + len > kMaxLogBytes) {
        size_t overflow = _log.size() + len - kMaxLogBytes;
        _log.erase(0, overflow);
    }
    
    for (size_t i = 0; i < len; ++i) {
        _log.push_back(data[i]);
        [self processByteLocked:static_cast<uint8_t>(data[i])];
    }
    
    _dirty = true;
    os_unfair_lock_unlock(&_lock);
    
    [self enqueueDraw];
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    [self resizeGridForDrawableSize:size];
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_pipeline || !self.currentDrawable) {
        _drawQueued.store(false);
        return;
    }
    
    std::vector<uint8_t> cellsCopy;
    os_unfair_lock_lock(&_lock);
    if (!_dirty) {
        os_unfair_lock_unlock(&_lock);
        _drawQueued.store(false);
        return;
    }
    cellsCopy = _cells;
    _dirty = false;
    os_unfair_lock_unlock(&_lock);
    
    NSUInteger instanceCount = [self encodeInstancesFromCells:cellsCopy drawableSize:view.drawableSize];
    
    MTLRenderPassDescriptor *desc = view.currentRenderPassDescriptor;
    if (!desc) {
        _drawQueued.store(false);
        return;
    }
    
    id<MTLCommandBuffer> cb = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:desc];
    [enc setRenderPipelineState:_pipeline];
    
    if (_atlas && _instanceBuffer && instanceCount > 0) {
        [enc setVertexBuffer:_instanceBuffer offset:sizeof(UniformsCPU) atIndex:0]; // instances
        [enc setVertexBuffer:_instanceBuffer offset:0 atIndex:1];                   // uniforms
        [enc setFragmentTexture:_atlas atIndex:0];
        
        // 6 vertices (quad), N instances
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:instanceCount];
    }
    
    [enc endEncoding];
    [cb presentDrawable:view.currentDrawable];
    
    __weak std::atomic_bool *flag = &_drawQueued;
    [cb addCompletedHandler:^(__unused id<MTLCommandBuffer> buffer) { flag->store(false); }];
    
    [cb commit];
}

#pragma mark - Rendering setup

- (void)buildPipeline {
    NSError *error = nil;
    id<MTLLibrary> lib = [self.device newDefaultLibrary];
    if (!lib) {
        NSLog(@"Failed to load default Metal library");
        return;
    }
    
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [lib newFunctionWithName:@"vertex_main"];
    desc.fragmentFunction = [lib newFunctionWithName:@"fragment_main"];
    desc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    _pipeline = [self.device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!_pipeline || error) {
        NSLog(@"Pipeline creation failed: %@", error);
    }
}

- (void)buildAtlas {
    CTFontRef font = CTFontCreateWithName(CFSTR("Menlo"), 28.0, nullptr);
    if (!font) {
        NSLog(@"Failed to create font");
        return;
    }
    
    float minX = 0, minY = 0, maxX = 0, maxY = 0;
    CGSize advanceSize = {};
    {
        UniChar ch = 'M';
        CGGlyph glyph;
        CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1);
        CGSize adv{};
        CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &glyph, &adv, 1);
        advanceSize = adv;
    }
    
    for (uint8_t c = 32; c < 127; ++c) {
        UniChar ch = c;
        CGGlyph glyph;
        CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1);
        CGRect bounds = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal, &glyph, nullptr, 1);
        minX = std::min(minX, (float)CGRectGetMinX(bounds));
        minY = std::min(minY, (float)CGRectGetMinY(bounds));
        maxX = std::max(maxX, (float)CGRectGetMaxX(bounds));
        maxY = std::max(maxY, (float)CGRectGetMaxY(bounds));
    }
    
    const float pad = 1.0f;
    float cellWF = (advanceSize.width > 0 ? advanceSize.width : (maxX - minX)) + pad * 2;
    float cellHF = (maxY - minY) + pad * 2;
    size_t cellW = (size_t)ceilf(cellWF);
    size_t cellH = (size_t)ceilf(cellHF);
    
    _cellWidth  = (float)cellW;
    _cellHeight = (float)cellH;
    
    _atlasCols = 16;
    _atlasRows = 8;
    _atlasW = cellW * _atlasCols;
    _atlasH = cellH * _atlasRows;
    
    std::vector<uint8_t> atlas(_atlasW * _atlasH * 4, 0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    
    for (uint8_t c = 32; c < 127; ++c) {
        UniChar ch = c;
        CGGlyph glyph;
        CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1);
        
        std::vector<uint8_t> cellBuf(cellW * cellH * 4, 0);
        CGContextRef ctx = CGBitmapContextCreate(cellBuf.data(), cellW, cellH, 8, cellW * 4, cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Little);
        if (!ctx) continue;
        
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
        CGContextSetShouldAntialias(ctx, true);
        CGContextSetAllowsAntialiasing(ctx, true);
        
        // If your glyphs are mirrored/rotated, fix CGContext transforms here.
        // (Leave as-is for now; your current pipeline expects this.)
        CGPoint origin = {pad - minX, pad - minY};
        CTFontDrawGlyphs(font, &glyph, &origin, 1, ctx);
        CGContextFlush(ctx);
        
        size_t cellX = (c - 32) % _atlasCols;
        size_t cellY = (c - 32) / _atlasCols;
        size_t dstX = cellX * cellW;
        size_t dstY = cellY * cellH;
        
        for (size_t y = 0; y < cellH; ++y) {
            uint8_t *dst = atlas.data() + ((dstY + y) * _atlasW + dstX) * 4;
            const uint8_t *src = cellBuf.data() + y * cellW * 4;
            memcpy(dst, src, cellW * 4);
        }
        
        CGContextRelease(ctx);
    }
    
    CGColorSpaceRelease(cs);
    CFRelease(font);
    
    MTLTextureDescriptor *td =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                       width:_atlasW
                                                      height:_atlasH
                                                   mipmapped:NO];
    td.storageMode = MTLStorageModeShared;
    td.usage = MTLTextureUsageShaderRead;
    
    _atlas = [self.device newTextureWithDescriptor:td];
    if (_atlas) {
        MTLRegion r = MTLRegionMake2D(0, 0, _atlasW, _atlasH);
        [_atlas replaceRegion:r mipmapLevel:0 withBytes:atlas.data() bytesPerRow:_atlasW * 4];
    }
    
    if (_cellWidth <= 0)  _cellWidth = 8.0f;
    if (_cellHeight <= 0) _cellHeight = 16.0f;
}

#pragma mark - Grid

- (void)resizeGridForDrawableSize:(CGSize)size {
    if (_cellWidth <= 0 || _cellHeight <= 0) return;
    
    size_t newCols = std::max<size_t>(1, (size_t)floor(size.width / _cellWidth));
    size_t newRows = std::max<size_t>(1, (size_t)floor(size.height / _cellHeight));
    
    os_unfair_lock_lock(&_lock);
    bool changed = (newCols != _cols) || (newRows != _rows) || _cells.empty();
    if (!changed) {
        os_unfair_lock_unlock(&_lock);
        return;
    }
    
    _cols = newCols;
    _rows = newRows;
    _cells.assign(_cols * _rows, kSpace);
    _cursorCol = 0;
    _cursorRow = 0;
    
    std::string replay = _log;
    for (uint8_t ch : replay) {
        [self processByteLocked:ch];
    }
    
    _dirty = true;
    os_unfair_lock_unlock(&_lock);
    
    [self enqueueDraw];
}

- (void)scrollLocked {
    if (_rows == 0 || _cols == 0) return;
    
    if (_rows > 1) {
        size_t rowBytes = _cols;
        std::memmove(_cells.data(), _cells.data() + rowBytes, (_rows - 1) * rowBytes);
        std::fill(_cells.end() - rowBytes, _cells.end(), kSpace);
    }
    _cursorRow = _rows ? _rows - 1 : 0;
    _cursorCol = 0;
}

- (void)processByteLocked:(uint8_t)ch {
    if (_cols == 0 || _rows == 0) return;
    
    switch (ch) {
        case '\r': _cursorCol = 0; return;
        case '\n':
            _cursorCol = 0;
            if (++_cursorRow >= _rows) [self scrollLocked];
            return;
        case '\b':
            if (_cursorCol > 0) --_cursorCol;
            return;
        default: break;
    }
    
    if (ch < 32 || ch >= 127) ch = '?';
    
    size_t idx = _cursorRow * _cols + _cursorCol;
    if (idx < _cells.size()) _cells[idx] = ch;
    
    if (++_cursorCol >= _cols) {
        _cursorCol = 0;
        if (++_cursorRow >= _rows) [self scrollLocked];
    }
}

- (void)enqueueDraw {
    bool expected = false;
    if (_drawQueued.compare_exchange_strong(expected, true)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self draw];
        });
    }
}

#pragma mark - Instance encoding

- (NSUInteger)encodeInstancesFromCells:(const std::vector<uint8_t> &)cells drawableSize:(CGSize)size {
    if (_cols == 0 || _rows == 0) return 0;
    
    const float w = (size.width  > 0 ? size.width  : self.bounds.size.width);
    const float h = (size.height > 0 ? size.height : self.bounds.size.height);
    
    // Count non-space glyphs (huge win vs drawing every cell)
    size_t count = 0;
    for (uint8_t ch : cells) {
        if (ch >= 32 && ch < 127 && ch != ' ') ++count;
    }
    if (count == 0) return 0;
    
    // We store uniforms at the front of the same buffer for simplicity:
    // [UniformsCPU][CellInstanceCPU...]
    NSUInteger neededBytes = (NSUInteger)sizeof(UniformsCPU) + (NSUInteger)(count * sizeof(CellInstanceCPU));
    if (!_instanceBuffer || neededBytes > _instanceCapacityBytes) {
        _instanceCapacityBytes = neededBytes * 2 + 4096;
        _instanceBuffer = [self.device newBufferWithLength:_instanceCapacityBytes options:MTLResourceStorageModeShared];
    }
    
    uint8_t *base = (uint8_t *)_instanceBuffer.contents;
    auto *u = (UniformsCPU *)base;
    auto *inst = (CellInstanceCPU *)(base + sizeof(UniformsCPU));
    
    u->viewportPx = {w, h};
    u->cellPx = {_cellWidth, _cellHeight};
    u->atlasPx = {(float)_atlasW, (float)_atlasH};
    u->atlasCols = (uint32_t)_atlasCols;
    u->firstChar = 32;
    u->pad = {0, 0};
    
    // Fill instances
    size_t written = 0;
    for (size_t i = 0; i < cells.size(); ++i) {
        uint8_t ch = cells[i];
        if (ch < 32 || ch >= 127 || ch == ' ') continue;
        
        size_t col = i % _cols;
        size_t row = i / _cols;
        
        inst[written].col = (uint16_t)col;
        inst[written].row = (uint16_t)row;
        inst[written].glyph = ch;
        inst[written].flags = 0;
        ++written;
    }
    
    // Bind uniforms separately via buffer(1) using an offset into the same buffer.
    // We'll do that by setting the same buffer twice with different offsets.
    // (Metal allows this.)
    return (NSUInteger)written;
}

@end
