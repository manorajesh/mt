//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 10/14/24.
//

import Cocoa
import CoreText

class TerminalView: NSView {
    // Text content and layout state
    var attributedString: NSAttributedString = {
            // Create an attributed string with a color
            let text = "Hello Sadge!"
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,  // Change the color here
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
            ]
            return NSAttributedString(string: text, attributes: attributes)
        }()
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Create CTLine from attributed string
        let line = CTLineCreateWithAttributedString(attributedString)
        
        // Set the text position
        context.textPosition = CGPoint(x: 10, y: bounds.height - 20)
        
        // Draw the line
        CTLineDraw(line, context)
    }
}
