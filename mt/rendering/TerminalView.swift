//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 12/11/24.
//

import SwiftUI
import MetalKit
import OSLog

class TerminalMTKView: MTKView {
    var pty: Pty?
    
    override var acceptsFirstResponder: Bool {
        true  // Allows this view to receive key events
    }
    
    override func keyDown(with event: NSEvent) {
        //        super.keyDown(with: event)
        
        guard let characters = event.characters else { return }
        switch event.keyCode {
        case 0x7E:
            pty?.sendSpecialKey(.arrowUp)
        case 0x7D:
            pty?.sendSpecialKey(.arrowDown)
        case 0x7B:
            pty?.sendSpecialKey(.arrowLeft)
        case 0x7C:
            pty?.sendSpecialKey(.arrowRight)
        default:
            pty?.sendInput(characters)
        }
        // Send the typed characters to the PTY
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
        
        let renderer = Renderer(device: device, buffer: buffer, pty: pty)
        mtkView.delegate = renderer
        coordinator.renderer = renderer
        
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


// MARK: - Metal Renderer

struct Vertex {
    var position:  SIMD2<Float>
    var texCoord:  SIMD2<Float>
    var fgColor:   SIMD4<Float>   // RGBA
    var bgColor:   SIMD4<Float>   // RGBA
}

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
    var pty: Pty?
    
    init(device: MTLDevice, buffer: Buffer, pty: Pty) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.fontAtlas = FontAtlas(device: self.device, size: CGSize(width: 4096, height: 4096), font: NSFont(name: "Monaco", size: 25)!)!
        self.buffer = buffer
        self.pty = pty
        
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
        
        // Position (attribute 0)
        vertexDescriptor.attributes[0].format      = .float2
        vertexDescriptor.attributes[0].offset      = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // TexCoords (attribute 1)
        vertexDescriptor.attributes[1].format      = .float2
        vertexDescriptor.attributes[1].offset      = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        // Foreground color (attribute 2)
        vertexDescriptor.attributes[2].format      = .float4
        vertexDescriptor.attributes[2].offset      = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        // Background color (attribute 3)
        vertexDescriptor.attributes[3].format      = .float4
        vertexDescriptor.attributes[3].offset      = MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[3].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        
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
    
    func generateQuad(for char: Character,
                      font: FontAtlas,
                      textureSize: CGSize,
                      screenSize: CGSize,
                      cursorX: Float,
                      cursorY: Float,
                      fgColor: RGBA,
                      bgColor: RGBA
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
        
        let clipX1 = (x1 / screenWidth) * 2.0 - 1.0
        let clipX2 = (x2 / screenWidth) * 2.0 - 1.0
        let clipY1 = (y1 / screenHeight) * 2.0 - 1.0
        let clipY2 = (y2 / screenHeight) * 2.0 - 1.0
        
        // Texture coordinates (flipping v if needed)
        let u1 = glyphX / Float(textureSize.width)
        let v1 = 1.0 - (glyphY / Float(textureSize.height))
        let u2 = (glyphX + glyphWidth) / Float(textureSize.width)
        let v2 = 1.0 - ((glyphY + glyphHeight) / Float(textureSize.height))
        
        // Build 6 vertices (2 triangles) with 12 floats each:
        // (pos.x, pos.y, tex.u, tex.v, fgRGBA(4 floats), bgRGBA(4 floats))
        
        // Triangle 1
        let quadData: [Float] = [
            // Vertex 1
            clipX1, clipY1, u1, v1, fgColor.rgba.x, fgColor.rgba.y, fgColor.rgba.z, fgColor.rgba.w, bgColor.rgba.x, bgColor.rgba.y, bgColor.rgba.z, bgColor.rgba.w,
            // Vertex 2
            clipX2, clipY1, u2, v1, fgColor.rgba.x, fgColor.rgba.y, fgColor.rgba.z, fgColor.rgba.w, bgColor.rgba.x, bgColor.rgba.y, bgColor.rgba.z, bgColor.rgba.w,
            // Vertex 3
            clipX1, clipY2, u1, v2, fgColor.rgba.x, fgColor.rgba.y, fgColor.rgba.z, fgColor.rgba.w, bgColor.rgba.x, bgColor.rgba.y, bgColor.rgba.z, bgColor.rgba.w,
            
            // Triangle 2
            clipX1, clipY2, u1, v2, fgColor.rgba.x, fgColor.rgba.y, fgColor.rgba.z, fgColor.rgba.w, bgColor.rgba.x, bgColor.rgba.y, bgColor.rgba.z, bgColor.rgba.w,
            clipX2, clipY1, u2, v1, fgColor.rgba.x, fgColor.rgba.y, fgColor.rgba.z, fgColor.rgba.w, bgColor.rgba.x, bgColor.rgba.y, bgColor.rgba.z, bgColor.rgba.w,
            clipX2, clipY2, u2, v2, fgColor.rgba.x, fgColor.rgba.y, fgColor.rgba.z, fgColor.rgba.w, bgColor.rgba.x, bgColor.rgba.y, bgColor.rgba.z, bgColor.rgba.w,
        ]
        
        return (quadData, glyphWidth)
    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = size
        let cols = Int(Int(size.width)/(fontAtlas.glyph(for: " ")?.size.width)!)
        let rows = Int(size.height/fontAtlas.lineHeight!)
        
        Logger().info("Resizing to \(rows)x\(cols)")
        buffer?.resize(rows: rows, cols: cols)
        pty?.resizePty(rows: UInt16(rows), cols: UInt16(cols))
        updateVerticesForBuffer()
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer,
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
        
        let textureSize = CGSize(width: fontAtlas.atlasTexture!.width,
                                 height: fontAtlas.atlasTexture!.height)
        let lineHeight: Float = Float(fontAtlas.lineHeight!)
        let totalHeight = Float(viewSize.height)
        
        var xPosition = Float(0.0)
        var yPosition = totalHeight
        
        var vertices: [Float] = []
        vertices.reserveCapacity(buffer.rows * buffer.cols * 12)
        for line in buffer.buffer {
            for char in line {
                if let (charVerts, xOffset) = generateQuad(for: char.character, font: fontAtlas, textureSize: textureSize, screenSize: viewSize, cursorX: xPosition, cursorY: yPosition, fgColor: char.foregroundColor, bgColor: char.backgroundColor) {
                    vertices += charVerts
                    xPosition += xOffset
                }
            }
            xPosition = 0.0
            yPosition -= lineHeight
        }
        
        if vertices.isEmpty { return }
        
        // Rebuild the vertex buffer
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: []
        )
    }
}
