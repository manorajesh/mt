//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 10/14/24.
//

import Cocoa
import CoreText

class TerminalView: NSView {
    var buffer: Buffer
    var pty: Pty?
    //    var cursorPosition: (x: Int, y: Int)
    var fontSize: CGFloat = 16
    var font: NSFont
    var cellHeight: CGFloat
    var cellWidth: CGFloat
    
    init(buffer: Buffer) {
        self.buffer = buffer
        //        cursorPosition = (x: 0, y: 0)
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        cellHeight = fontSize + 4 // Slight padding for line height
        cellWidth = font.advancement(forGlyph: NSGlyph(CGGlyph(" ".utf16.first!))).width
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw the cursor at the current cursor position
//                drawCursor(at: cursorPosition, with: cellWidth, and: cellHeight, in: context)
        
        for (rowIndex, row) in buffer.buffer.enumerated() {
            for (colIndex, cell) in row.enumerated() {
                let attributedString = createAttributedString(for: cell, with: font)
                let xPosition = CGFloat(colIndex) * cellWidth
                let yPosition = CGFloat(rowIndex+1) * cellHeight
                
                context.textPosition = CGPoint(x: xPosition , y: bounds.height - yPosition)
                
                let line = CTLineCreateWithAttributedString(attributedString)
                CTLineDraw(line, context)
            }
        }
        
        context.restoreGState()
    }
    
    private func createAttributedString(for cell: CharacterCell, with font: NSFont) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: cell.foregroundColor,
            .backgroundColor: cell.backgroundColor
        ]
        
        return NSAttributedString(string: String(cell.character), attributes: attributes)
    }
    
    private func drawCursor(at position: (x: Int, y: Int), with cellWidth: CGFloat, and cellHeight: CGFloat, in context: CGContext) {
        let cursorRect = CGRect(x: CGFloat(position.x) * cellWidth,
                                y: bounds.height - CGFloat(position.y + 1) * cellHeight - 4,
                                width: cellWidth,
                                height: cellHeight)
        
        // Set cursor color
        NSColor.gray.setFill()
        context.fill(cursorRect)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        if modifiers.contains(.control) {
            switch keyCode {
            case 0x08:
                pty?.sendSpecialKey(.ctrlC)
            case 0x02:
                pty?.sendSpecialKey(.ctrlD)
            case 0x06:
                pty?.sendSpecialKey(.ctrlZ)
            default:
                super.keyDown(with: event)
            }
        } else {
            switch keyCode {
            case 0x24:
                pty?.sendSpecialKey(.enter)
            case 0x33:
                pty?.sendSpecialKey(.backspace)
            default:
                super.keyDown(with: event)
            }
        }
    }
    
    private func handleArrowKey(direction: ArrowDirection) {
        
    }
    
    override func insertText(_ insertString: Any) {
        if let text = insertString as? String {
            handleTextInput(text)  // Handle typed characters
        }
    }
    
    private func handleTextInput(_ text: String) {
        pty?.sendInput(text)
        self.setNeedsDisplay(self.bounds)
    }
    
    func setPty(_ pty: Pty) {
        self.pty = pty
    }
}

enum ArrowDirection {
    case left, right, up, down
}
