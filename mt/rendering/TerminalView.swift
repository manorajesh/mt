//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 12/11/24.
//

import SwiftUI
import MetalKit

class TerminalMTKView: MTKView {
    var pty: Pty?
    
    override var acceptsFirstResponder: Bool {
        true  // Allows this view to receive key events
    }
    
    override func keyDown(with event: NSEvent) {
        //        super.keyDown(with: event)
        
        guard let characters = event.characters else { return }
        // Send the typed characters to the PTY
        pty?.sendInput(characters)
    }
    
    // Handle special keys, arrow keys, etc.
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        // If needed, handle key-up logic.
    }
}


struct TerminalView: NSViewRepresentable {
    @StateObject private var coordinator = Coordinator()
    
    func makeNSView(context: Context) -> MTKView {
        let buffer = Buffer(rows: 100, cols: 800)
        let pty = Pty(buffer: buffer, view: self, rows: 100, cols: 800)
        
        let device = MTLCreateSystemDefaultDevice()!
        let mtkView = TerminalMTKView(frame: .zero, device: device)
        
        // Configure view for smooth rendering
        mtkView.preferredFramesPerSecond = 60
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        
        // Enable triple buffering
        //        mtkView.maximumDrawableCount = 3
        
        let renderer = Renderer(device: device, buffer: buffer)
        mtkView.delegate = renderer
        coordinator.renderer = renderer   // <--- Store renderer in our coordinator
        
        // Assign the pty reference so keyDown can forward input
        mtkView.pty = pty
        
        // Optionally, request focus so we can receive keyboard input
        mtkView.becomeFirstResponder()
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
    
    /// Called whenever PTY has new output
    func refresh() {
        // Update the renderer with the new buffer state
        coordinator.renderer?.updateVerticesForBuffer()
        
        // Force the MTKView to redraw immediately
        // If the MTKView has enableSetNeedsDisplay = true, you can do:
        // (coordinator.renderer?.view as? MTKView)?.setNeedsDisplay((coordinator.renderer?.view?.bounds)!)
        // Or if you have a reference to the MTKView:
        // nsView.draw()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: ObservableObject {
        var renderer: Renderer?
    }
}


struct Vertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
}

// MARK: - Metal Renderer
class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var fontAtlas: FontAtlas
    var vertexBuffer: MTLBuffer?
    var pipelineState: MTLRenderPipelineState?
    var samplerState: MTLSamplerState?
    var cachedVertices: [Float] = []
    var viewSize: CGSize?
    
    var buffer: Buffer?
    
    init(device: MTLDevice, buffer: Buffer) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.fontAtlas = FontAtlas(device: self.device, size: CGSize(width: 4096, height: 4096), font: NSFont(name: "Monaco", size: 30)!)!
        self.buffer = buffer
        
        super.init()
        
        setupPipeline()
        setupSamplerState()
    }
    
    func setupPipeline() {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Attribute 0: Position
        vertexDescriptor.attributes[0].format = .float2  // 2 floats for position (x, y)
        vertexDescriptor.attributes[0].offset = 0        // Position starts at the beginning of the vertex
        vertexDescriptor.attributes[0].bufferIndex = 0  // Tied to vertex buffer 0
        
        // Attribute 1: Texture Coordinates
        vertexDescriptor.attributes[1].format = .float2  // 2 floats for texture coordinates (u, v)
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride  // Offset after position
        vertexDescriptor.attributes[1].bufferIndex = 0  // Same buffer as position
        
        // Layout for Buffer 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride  // Stride of the entire vertex
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    func setupSamplerState() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear      // Linear filtering for minification
        samplerDescriptor.magFilter = .linear      // Linear filtering for magnification
        samplerDescriptor.sAddressMode = .clampToEdge // Clamp addressing for S (U) axis
        samplerDescriptor.tAddressMode = .clampToEdge // Clamp addressing for T (V) axis
        
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    func setupVertices(for text: String, viewSize: CGSize) {
        let textureSize = CGSize(width: fontAtlas.atlasTexture!.width, height: fontAtlas.atlasTexture!.height)
        let vertices = generateVertices(for: text, font: fontAtlas, textureSize: textureSize, screenSize: viewSize, cursorY: Float(viewSize.height))
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
    }
    
    func generateVertices(for text: String,
                          font: FontAtlas,
                          textureSize: CGSize,
                          screenSize: CGSize,
                          cursorY: Float
    ) -> [Float] {
        var vertices: [Float] = []
        var cursorX: Float = 0.0
        
        for character in text {
            if let (charVerts, xOffset) = generateQuad(for: character, font: fontAtlas, textureSize: textureSize, screenSize: screenSize, cursorX: cursorX, cursorY: cursorY) {
                vertices += charVerts
                // Advance cursorX for the next character
                cursorX += xOffset
            }
        }
        
        return vertices
    }
    
    func generateQuad(for char: Character,
                      font: FontAtlas,
                      textureSize: CGSize,
                      screenSize: CGSize,
                      cursorX: Float,
                      cursorY: Float
    ) -> ([Float], Float)? {
        guard let glyph = font.glyph(for: char) else { return nil }
        
        let glyphWidth  = Float(glyph.size.width)
        let glyphHeight = Float(glyph.size.height)
        let glyphX = Float(glyph.position.x)
        let glyphY = Float(glyph.position.y)
        
        // The quad’s top-left is (cursorX, cursorY).
        // The quad’s bottom-left is (cursorX, cursorY - glyphHeight).
        let x1 = cursorX
        let x2 = cursorX + glyphWidth
        let y2 = cursorY             // top
        let y1 = cursorY - glyphHeight  // bottom
        
        // Convert to clip space
        let screenWidth  = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)
        let pxToClipX = { (px: Float) in (px / screenWidth) * 2.0 - 1.0 }
        let pxToClipY = { (py: Float) in (py / screenHeight) * 2.0 - 1.0 }
        
        let clipX1 = pxToClipX(x1)
        let clipX2 = pxToClipX(x2)
        let clipY1 = pxToClipY(y1)
        let clipY2 = pxToClipY(y2)
        
        // Texture coordinates (flipping v if needed)
        let u1 = glyphX / Float(textureSize.width)
        let v1 = 1.0 - (glyphY / Float(textureSize.height))
        let u2 = (glyphX + glyphWidth) / Float(textureSize.width)
        let v2 = 1.0 - ((glyphY + glyphHeight) / Float(textureSize.height))
        
        // Use triangle list (6 verts per character)
        return ([
            // Triangle 1
            clipX1, clipY1, u1, v1,
            clipX2, clipY1, u2, v1,
            clipX1, clipY2, u1, v2,
            
            // Triangle 2
            clipX1, clipY2, u1, v2,
            clipX2, clipY1, u2, v1,
            clipX2, clipY2, u2, v2
        ], glyphWidth)
    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = size
        setupVertices(for: "Hello World", viewSize: size)
        let cols = Int(Int(size.width)/(fontAtlas.glyph(for: " ")?.size.width)!)
        let rows = Int(size.height/fontAtlas.lineHeight!)
        print("\(rows)x\(cols)")
        buffer?.resize(rows: rows, cols: cols)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer,  // ensure not nil
              vertexBuffer.length > 0 else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(fontAtlas.atlasTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Each vertex = 4 floats, so:
        let vertexCount = vertexBuffer.length / (MemoryLayout<Float>.size * 4)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // Method to update vertices for dirty rows
    func updateVerticesForBuffer() {
        guard let buffer = buffer, let viewSize = viewSize else { return }
        
        let dirtyRows = buffer.buffer
        guard !dirtyRows.isEmpty else { return }
        
        let textureSize = CGSize(width: fontAtlas.atlasTexture!.width,
                                 height: fontAtlas.atlasTexture!.height)
        let lineHeight: Float = Float(fontAtlas.lineHeight!)
        let totalHeight = Float(viewSize.height)
        
        var xPosition = Float(0.0)
        var yPosition = totalHeight
        var vertices: [Float] = []
        for line in dirtyRows {
            for char in line {
                if let (charVerts, xOffset) = generateQuad(for: char.character, font: fontAtlas, textureSize: textureSize, screenSize: viewSize, cursorX: xPosition, cursorY: yPosition) {
                    vertices += charVerts
                    xPosition += xOffset
                }
            }
            xPosition = 0.0
            yPosition -= lineHeight
        }
        
        // Rebuild the vertex buffer
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: []
        )
    }
}
