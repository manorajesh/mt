//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 12/11/24.
//

import SwiftUI
import MetalKit

struct TerminalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()!
        let mtkView = MTKView(frame: .zero, device: device)
        
        let renderer = Renderer(device: device)
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
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
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.fontAtlas = FontAtlas(device: self.device, size: CGSize(width: 4000, height: 4000), font: .monospacedSystemFont(ofSize: 400, weight: .regular ))!
        
        let desktopURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = desktopURL.appendingPathComponent("FontAtlas.png")
        saveFontAtlasToFile(fontAtlas: self.fontAtlas, fileURL: fileURL)
        
        super.init()
        
        setupPipeline()
        createSamplerState()
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
    
    func createSamplerState() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear      // Linear filtering for minification
        samplerDescriptor.magFilter = .linear      // Linear filtering for magnification
        samplerDescriptor.sAddressMode = .clampToEdge // Clamp addressing for S (U) axis
        samplerDescriptor.tAddressMode = .clampToEdge // Clamp addressing for T (V) axis
        
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    func setupVertices(for text: String, viewSize: CGSize) {
        let textureSize = CGSize(width: fontAtlas.atlasTexture!.width, height: fontAtlas.atlasTexture!.height)
        let vertices = generateVertices(for: text, font: fontAtlas, textureSize: textureSize, screenSize: viewSize)
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
    }
    
    func generateVertices(for text: String, font: FontAtlas, textureSize: CGSize, screenSize: CGSize) -> [Float] {
        var vertices: [Float] = []
        var cursorX: Float = 0.0  // Tracks the current X position for rendering
        
        for character in text {
            guard let glyph = font.glyph(for: character) else { continue }
            
            // Glyph size and position
            let glyphWidth = Float(glyph.size.width)
            let glyphHeight = Float(glyph.size.height)
            let glyphX = Float(glyph.position.x)
            let glyphY = Float(glyph.position.y)
            
            // Vertex positions (screen-space coordinates)
            let x1 = cursorX
            let y1 = Float(0.0)
            let x2 = cursorX + glyphWidth
            let y2 = glyphHeight
            
            // Normalize screen coordinates if necessary
            let screenWidth = Float(screenSize.width)
            let screenHeight = Float(screenSize.height)
            let pxToClipX = { (px: Float) in (px / screenWidth) * 2.0 - 1.0 }
            let pxToClipY = { (py: Float) in (py / screenHeight) * 2.0 - 1.0 }
            
            let clipX1 = pxToClipX(x1)
            let clipX2 = pxToClipX(x2)
            let clipY1 = pxToClipY(y1)
            let clipY2 = pxToClipY(y2)
            
            // Texture coordinates
            let u1 = glyphX / Float(textureSize.width)
            let v1 = 1.0 - (glyphY / Float(textureSize.height))
            let u2 = (glyphX + glyphWidth) / Float(textureSize.width)
            let v2 = 1.0 - ((glyphY + glyphHeight) / Float(textureSize.height))
            
            // Append vertices (triangle strip)
            vertices += [
                clipX1, clipY1, u1, v1,  // Bottom-left
                clipX2, clipY1, u2, v1,  // Bottom-right
                clipX1, clipY2, u1, v2,  // Top-left
                clipX2, clipY2, u2, v2   // Top-right
            ]
            
            // Advance cursor for the next character
            cursorX += glyphWidth
        }
        
        return vertices
    }
    
    
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupVertices(for: "abc", viewSize: size)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer
        else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(fontAtlas.atlasTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        let vertexCount = vertexBuffer.length / (4 * MemoryLayout<Float>.size) // 4 floats per vertex
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
}

class FontAtlas {
    var charSet = #" !#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"#
    var atlasTexture: MTLTexture?
    private var glyphs: [Character: Glyph] = [:]
    
    init?(device: MTLDevice, size: CGSize, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        let bitmapWidth = Int(size.width)
        let bitmapHeight = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        let context = CGContext(
            data: nil,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: 4 * bitmapWidth,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        
        // Wrap it in an NSGraphicsContext
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        
        // Push the new NSGraphicsContext
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        
        // Render each character into the context, tracking positions
        var currentX = 0
        var currentY = 0
        let yPadding = 5
        for character in charSet {
            let charString = String(character)
            let charSize = charString.size(withAttributes: attributes)
            
            if currentY + Int(charSize.height) + yPadding > bitmapHeight {
                print("Altas too small; skipping remaining chars")
                break
            }
            
            if currentX + Int(charSize.width) > bitmapWidth {
                currentY += Int(charSize.height) + yPadding
                currentX = 0
            }
            
            let drawRect = CGRect(x: CGFloat(currentX), y: CGFloat(currentY), width: charSize.width, height: charSize.height)
            charString.draw(in: drawRect, withAttributes: attributes)
            
            let glyph = Glyph(width: Int(charSize.width),
                              height: Int(charSize.height),
                              x: currentX,
                              y: currentY)
            glyphs[character] = glyph
            
            currentX += Int(charSize.width)
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = bitmapWidth
        textureDescriptor.height = bitmapHeight
        textureDescriptor.usage = [.shaderRead]
        
        let texture = device.makeTexture(descriptor: textureDescriptor)
        let region = MTLRegionMake2D(0, 0, bitmapWidth, bitmapHeight)
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        
        texture?.replace(region: region,
                         mipmapLevel: 0,
                         withBytes: bytes,
                         bytesPerRow: 4 * bitmapWidth)
        
        atlasTexture = texture
    }
    
    
    func glyph(for character: Character) -> Glyph? {
        return glyphs[character]  // Return the glyph for the specified character
    }
    
    class Glyph {
        var size: (width: Int, height: Int)
        var position: (x: Int, y: Int)
        
        init(width: Int, height: Int, x: Int, y: Int) {
            size = (width, height)
            position = (x, y)
        }
    }
}

func saveFontAtlasToFile(fontAtlas: FontAtlas, fileURL: URL) {
    guard let texture = fontAtlas.atlasTexture else { return }
    
    let width = texture.width
    let height = texture.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let byteCount = bytesPerRow * height
    
    var pixelData = [UInt8](repeating: 0, count: byteCount)
    let region = MTLRegionMake2D(0, 0, width, height)
    
    texture.getBytes(&pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let dataProvider = CGDataProvider(data: NSData(bytes: pixelData, length: byteCount)) else { return }
    guard let cgImage = CGImage(width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bitsPerPixel: 32,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: dataProvider,
                                decode: nil,
                                shouldInterpolate: false,
                                intent: .defaultIntent) else { return }
    
    let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    guard let tiffData = image.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return }
    
    do {
        try pngData.write(to: fileURL)
        print("FontAtlas saved to \(fileURL.path)")
    } catch {
        print("Failed to save FontAtlas: \(error)")
    }
}
