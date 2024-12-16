//
//  FontAtlas.swift
//  mt
//
//  Created by Mano Rajesh on 12/15/24.
//

import Foundation
import MetalKit

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
