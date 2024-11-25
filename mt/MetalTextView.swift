//
//  MetalTextView.swift
//  mt
//
//  Created by Mano Rajesh on 11/16/24.
//

import SwiftUI
import MetalKit
import SDFont

struct MetalTextView: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        mtkView.device = device
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        
        // Initialize renderer
        context.coordinator.renderer = MetalTextRenderer(mtkView: mtkView)
        mtkView.delegate = context.coordinator.renderer
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update the text by recreating the vertex buffer
//        context.coordinator.renderer?.createVertexBuffer(for: text)
        nsView.setNeedsDisplay(nsView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var renderer: MetalTextRenderer?
    }
}
