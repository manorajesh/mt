//
//  TerminalView.mm
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import "TerminalView.h"

#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

#import "../../mtCore/pty.h"
#import "../../mtCore/parser.hpp"
#import "../../mtCore/render_backend.hpp"

using namespace simd;

#pragma mark - Metal structs (must match .metal)

typedef struct {
    vector_float2 viewportPx;
    vector_float2 cellPx;        // screen cell size
    vector_float2 atlasPx;       // full atlas size
    vector_float2 atlasCellPx;   // SINGLE GLYPH CELL SIZE (NEW)
    uint32_t atlasCols;
    uint32_t firstChar;
} UniformsCPU;

@interface TerminalView () <MTKViewDelegate> {
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLTexture> _atlas;
    
    id<MTLBuffer> _uniformBuffer;
    
    // One instance buffer per row (fixed capacity)
    NSMutableArray<id<MTLBuffer>> *_rowBuffers;
    NSMutableArray<NSNumber*> *_rowCounts;
    
    float _cellW;
    float _cellH;
    
    uint16_t _cols;
    uint16_t _rows;
    
#ifdef __cplusplus
    RenderBackend *_backend;      // owned externally (terminal core)
    uint64_t _lastSeq;
#endif
}
@end

@implementation TerminalView

#pragma mark - Init / setup

- (instancetype)initWithFrame:(NSRect)frame {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) return nil;
    if ((self = [super initWithFrame:frame device:dev])) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.delegate = self;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.clearColor = MTLClearColorMake(0.03, 0.05, 0.07, 1.0);
    
    _queue = [self.device newCommandQueue];
    _rowBuffers = [NSMutableArray array];
    _rowCounts  = [NSMutableArray array];
    
    [self buildPipeline];
    [self buildAtlas];
}

- (BOOL)acceptsFirstResponder { return YES; }

#pragma mark - Backend wiring (C++)

#ifdef __cplusplus
- (void)attachRenderBackend:(RenderBackend *)backend {
    _backend = backend;
    _cols = backend->cols();
    _rows = backend->rows();
    
    // _cellW and _cellH are already set by buildAtlas() - don't override!
    
    [_rowBuffers removeAllObjects];
    [_rowCounts removeAllObjects];
    
    for (uint16_t r = 0; r < _rows; ++r) {
        id<MTLBuffer> buf =
        [self.device newBufferWithLength:_cols * sizeof(CellInstanceCPU)
                                 options:MTLResourceStorageModeShared];
        [_rowBuffers addObject:buf];
        [_rowCounts addObject:@0];
    }
    
    _uniformBuffer =
    [self.device newBufferWithLength:sizeof(UniformsCPU)
                             options:MTLResourceStorageModeShared];
    
    _lastSeq = 0;
}
#endif

#pragma mark - Input

- (void)keyDown:(NSEvent *)event {
    if (!self.pty) return;
    NSData *d = [event.characters dataUsingEncoding:NSUTF8StringEncoding];
    self.pty->send((const char *)d.bytes, d.length);
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // grid resize handled by terminal core → RenderBackend::configure()
}

- (void)drawInMTKView:(MTKView *)view {
#ifdef __cplusplus
    if (!_backend) return;
    
    auto frame = _backend->acquireLatest();
    if (frame.seq == 0 || frame.seq == _lastSeq) return;
    _lastSeq = frame.seq;
    
    // Upload dirty rows only
    for (uint16_t r = 0; r < frame.rows; ++r) {
        if (!frame.dirty->test(r)) continue;
        
        id<MTLBuffer> buf = _rowBuffers[r];
        memcpy(buf.contents,
               frame.rowPtr(r),
               frame.rowCount(r) * sizeof(CellInstanceCPU));
        _rowCounts[r] = @(frame.rowCount(r));
    }
    
    UniformsCPU *u = (UniformsCPU *)_uniformBuffer.contents;
    u->viewportPx = {(float)view.drawableSize.width,
        (float)view.drawableSize.height};
    u->cellPx       = {_cellW, _cellH};
    u->atlasPx      = {(float)_atlas.width, (float)_atlas.height};
    u->atlasCellPx  = {_cellW, _cellH};   // MUST MATCH atlas build
    u->atlasCols    = 16;
    u->firstChar    = 32;
    
    MTLRenderPassDescriptor *rp = view.currentRenderPassDescriptor;
    if (!rp) return;
    
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc =
    [cb renderCommandEncoderWithDescriptor:rp];
    
    [enc setRenderPipelineState:_pipeline];
    [enc setVertexBuffer:_uniformBuffer offset:0 atIndex:1];
    [enc setFragmentTexture:_atlas atIndex:0];
    
    // Draw per row (bounded, cheap)
    for (uint16_t r = 0; r < frame.rows; ++r) {
        NSUInteger count = _rowCounts[r].unsignedIntegerValue;
        if (count == 0) continue;
        
        [enc setVertexBuffer:_rowBuffers[r] offset:0 atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:count];
    }
    
    [enc endEncoding];
    [cb presentDrawable:view.currentDrawable];
    [cb commit];
#endif
}

#pragma mark - Metal setup

- (void)buildPipeline {
    id<MTLLibrary> lib = [self.device newDefaultLibrary];
    
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction   = [lib newFunctionWithName:@"terminal_vertex"];
    d.fragmentFunction = [lib newFunctionWithName:@"terminal_fragment"];
    d.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    
    d.colorAttachments[0].blendingEnabled = YES;
    d.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    d.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *err = nil;
    _pipeline = [self.device newRenderPipelineStateWithDescriptor:d error:&err];
    NSAssert(_pipeline, @"Pipeline error %@", err);
}

#pragma mark - Font atlas (unchanged, but isolated)

- (void)buildAtlas {
    static constexpr uint32_t kFirstChar = 32;
    static constexpr uint32_t kCharCount = 95;   // 32..126
    static constexpr uint32_t kAtlasCols = 16;
    static constexpr uint32_t kAtlasRows = 6;
    
    CTFontRef font = CTFontCreateWithName(CFSTR("Menlo"), 28.0, nullptr);
    NSAssert(font, @"Failed to create font");
    
    // ---- Measure glyph bounds ----
    float minX = 0, minY = 0, maxX = 0, maxY = 0;
    CGSize advance = {};
    
    {
        UniChar ch = 'M';
        CGGlyph g;
        CTFontGetGlyphsForCharacters(font, &ch, &g, 1);
        CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &g, &advance, 1);
    }
    
    for (uint8_t c = kFirstChar; c < kFirstChar + kCharCount; ++c) {
        UniChar ch = c;
        CGGlyph g;
        CTFontGetGlyphsForCharacters(font, &ch, &g, 1);
        CGRect b = CTFontGetBoundingRectsForGlyphs(
                                                   font, kCTFontOrientationHorizontal, &g, nullptr, 1);
        
        minX = std::min(minX, (float)CGRectGetMinX(b));
        minY = std::min(minY, (float)CGRectGetMinY(b));
        maxX = std::max(maxX, (float)CGRectGetMaxX(b));
        maxY = std::max(maxY, (float)CGRectGetMaxY(b));
    }
    
    constexpr float pad = 1.0f;
    
    _cellW = ceilf((advance.width > 0 ? advance.width : (maxX - minX)) + pad * 2);
    _cellH = ceilf((maxY - minY) + pad * 2);
    
    const size_t atlasW = (size_t)(_cellW * kAtlasCols);
    const size_t atlasH = (size_t)(_cellH * kAtlasRows);
    
    std::vector<uint8_t> pixels(atlasW * atlasH * 4, 0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    
    // ---- Render glyphs ----
    for (uint32_t i = 0; i < kCharCount; ++i) {
        UniChar ch = (UniChar)(kFirstChar + i);
        CGGlyph g;
        CTFontGetGlyphsForCharacters(font, &ch, &g, 1);
        
        std::vector<uint8_t> cellBuf((size_t)(_cellW * _cellH * 4), 0);
        
        CGContextRef ctx = CGBitmapContextCreate(
                                                 cellBuf.data(),
                                                 (size_t)_cellW,
                                                 (size_t)_cellH,
                                                 8,
                                                 (size_t)_cellW * 4,
                                                 cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Little);
        
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
        CGContextSetShouldAntialias(ctx, true);
        
        CGPoint origin = { pad - minX, pad - minY };
        CTFontDrawGlyphs(font, &g, &origin, 1, ctx);
        CGContextRelease(ctx);
        
        const size_t gx = i % kAtlasCols;
        const size_t gy = i / kAtlasCols;
        
        for (size_t y = 0; y < (size_t)_cellH; ++y) {
            uint8_t* dst = pixels.data() +
            ((gy * (size_t)_cellH + y) * atlasW + gx * (size_t)_cellW) * 4;
            const uint8_t* src = cellBuf.data() + y * (size_t)_cellW * 4;
            memcpy(dst, src, (size_t)_cellW * 4);
        }
    }
    
    CGColorSpaceRelease(cs);
    CFRelease(font);
    
    // ---- Upload texture ----
    MTLTextureDescriptor* td =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                       width:atlasW
                                                      height:atlasH
                                                   mipmapped:NO];
    td.storageMode = MTLStorageModeShared;
    td.usage = MTLTextureUsageShaderRead;
    
    _atlas = [self.device newTextureWithDescriptor:td];
    NSAssert(_atlas, @"Failed to create atlas texture");
    
    [_atlas replaceRegion:MTLRegionMake2D(0, 0, atlasW, atlasH)
              mipmapLevel:0
                withBytes:pixels.data()
              bytesPerRow:atlasW * 4];
}

@end
