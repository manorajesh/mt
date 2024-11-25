//
//  MetalTextRenderer.swift
//  mt
//
//  Created by Mano Rajesh on 11/16/24.
//

import Metal
import MetalKit
import SwiftUI
import simd
import SDFont

// Vertex structure matching the shader's VertexIn
struct Vertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
}

class MetalTextRenderer: NSObject, MTKViewDelegate {
    // Metal objects
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var sdfTexture: MTLTexture!
    private var sampler: MTLSamplerState!
    
    // SDFont generator and helper
    private var sdGenerator: SDFontGenerator!
    private var helper: SDFontRuntimeHelper!
    
    // Vertex data
    private var vertexBuffer: MTLBuffer!
    private var bounds: [SDFontRuntimeHelper.GlyphBound] = []
    
    // Projection matrix
    private var projectionMatrix: simd_float4x4 = simd_float4x4()
    
    // Font size and text
    private var fontSize: Float = 64.0
    private var text: String = "Hello, SDFont with Metal!"
    
    init(mtkView: MTKView) {
        super.init()
        self.device = mtkView.device
        self.commandQueue = device.makeCommandQueue()
        setupSDFont()
        loadShaders()
        loadSampler()
        loadSDFTexture()
        setupHelper()
        performTypesetting(width: CGFloat(mtkView.drawableSize.width), height: CGFloat(mtkView.drawableSize.height))
        createVertexBuffer(from: bounds)
        updateProjection(width: Float(mtkView.drawableSize.width),
                        height: Float(mtkView.drawableSize.height))
    }
    
    // Setup SDFontGenerator
    private func setupSDFont() {
        sdGenerator = SDFontGenerator(
            device: device,
            fontName: "Helvetica-Bold",
            outputTextureSideLen: 2048,
            spreadFactor: 0.2,
            upSamplingFactor: 2,
            glyphNumCutoff: 256,
            verbose: true,
            usePosixPath: false
        )
        
        // Optionally write to PNG and JSON
        // sdGenerator.writeToPNGFile(fileName: "Helvetica-Bold", path: "./")
        // sdGenerator.writeMetricsToJSONFile(fileName: "Helvetica-Bold", path: "./")
    }
    
    // Setup SDFontRuntimeHelper
    private func setupHelper() {
        helper = SDFontRuntimeHelper(generator: sdGenerator, fontSize: Int(fontSize), verbose: true)
    }
    
    // Perform typesetting
    private func performTypesetting(width: CGFloat, height: CGFloat) {
        bounds = helper.typeset(
            frameRect: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            textPlain: text,
            lineAlignment: .left
        )
    }
    
    // Load and compile shaders
    private func loadShaders() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default library.")
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
            fatalError("Failed to find vertex shader.")
        }
        
        guard let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Failed to find fragment shader.")
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            fatalError("Failed to create pipeline state: \(error.localizedDescription)")
        }
    }
    
    // Load SDF texture atlas
    private func loadSDFTexture() {
        guard let texture = sdGenerator.generateMTLTexture() else {
            fatalError("Failed to generate SDF texture.")
        }
        sdfTexture = texture
    }

    
    // Create a sampler state
    private func loadSampler() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    // Create vertex buffer from GlyphBound
    private func createVertexBuffer(from bounds: [SDFontRuntimeHelper.GlyphBound]) {
        guard let sdfWidth = sdfTexture?.width,
              let sdfHeight = sdfTexture?.height else {
            fatalError("SDF texture is not loaded.")
        }
        
        var vertices: [Vertex] = []
        var cursorX: Float = 0.0
        let cursorY: Float = 0.0
        
        for glyphBound in bounds {
            let frame = glyphBound.frameBound
            let texture = glyphBound.textureBound
            
            // Skip degenerate glyphs
            if frame.width <= 0 || frame.height <= 0 {
                continue
            }
            
            // Define quad vertices in screen space
            let topLeft = SIMD2<Float>(cursorX + Float(frame.minX), cursorY + Float(frame.maxY))
            let topRight = SIMD2<Float>(cursorX + Float(frame.maxX), cursorY + Float(frame.maxY))
            let bottomRight = SIMD2<Float>(cursorX + Float(frame.maxX), cursorY + Float(frame.minY))
            let bottomLeft = SIMD2<Float>(cursorX + Float(frame.minX), cursorY + Float(frame.minY))
            
            // Normalize texture coordinates
            let texTL = SIMD2<Float>(
                Float(texture.origin.x) / Float(sdfWidth),
                Float(texture.origin.y + texture.height) / Float(sdfHeight)
            )
            let texTR = SIMD2<Float>(
                (Float(texture.origin.x + texture.width)) / Float(sdfWidth),
                Float(texture.origin.y + texture.height) / Float(sdfHeight)
            )
            let texBR = SIMD2<Float>(
                (Float(texture.origin.x + texture.width)) / Float(sdfWidth),
                Float(texture.origin.y) / Float(sdfHeight)
            )
            let texBL = SIMD2<Float>(
                Float(texture.origin.x) / Float(sdfWidth),
                Float(texture.origin.y) / Float(sdfHeight)
            )
            
            // Two triangles per quad
            vertices.append(Vertex(position: topLeft, texCoord: texTL))
            vertices.append(Vertex(position: bottomLeft, texCoord: texBL))
            vertices.append(Vertex(position: topRight, texCoord: texTR))
            
            vertices.append(Vertex(position: topRight, texCoord: texTR))
            vertices.append(Vertex(position: bottomLeft, texCoord: texBL))
            vertices.append(Vertex(position: bottomRight, texCoord: texBR))
            
            // Advance cursor based on glyph width
            cursorX += Float(frame.width)
        }
        
        // Create buffer
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Vertex>.size,
                                         options: [])
    }

    
    // Update projection matrix based on view size
    func updateProjection(width: Float, height: Float) {
        projectionMatrix = float4x4(orthoLeft: 0,
                                     orthoRight: width,
                                     orthoBottom: 0,
                                     orthoTop: height,
                                     nearZ: -1,
                                     farZ: 1)
    }
    
    // MARK: - MTKViewDelegate Methods
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateProjection(width: Float(size.width),
                        height: Float(size.height))
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        // Set pipeline state and resources
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Set uniforms
        renderEncoder.setVertexBytes(&projectionMatrix,
                                     length: MemoryLayout<float4x4>.size,
                                     index: 1)
        
        // Set texture and sampler
        renderEncoder.setFragmentTexture(sdfTexture, index: 0)
        renderEncoder.setFragmentSamplerState(sampler, index: 0)
        
        // Calculate vertex count based on bounds
        let vertexCount = bounds.count * 6 // 6 vertices per glyph
        
        // Draw call
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        
        // Finalize encoding
        renderEncoder.endEncoding()
        
        // Present drawable
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// Helper for orthographic projection matrix
extension float4x4 {
    init(orthoLeft left: Float, orthoRight right: Float,
         orthoBottom bottom: Float, orthoTop top: Float,
         nearZ: Float, farZ: Float) {
        let rl = 1 / (right - left)
        let tb = 1 / (top - bottom)
        let fn = 1 / (farZ - nearZ)
        
        self.init(rows: [
            SIMD4<Float>(2 * rl, 0, 0, 0),
            SIMD4<Float>(0, 2 * tb, 0, 0),
            SIMD4<Float>(0, 0, -2 * fn, 0),
            SIMD4<Float>((-right - left) * rl, (-top - bottom) * tb, (-farZ - nearZ) * fn, 1)
        ])
    }
}
