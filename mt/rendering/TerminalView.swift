//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 10/14/24.
//

import Cocoa
import CoreText

class TerminalView: NSView {
    var buffer: TerminalBuffer
    var cursorPosition: (x: Int, y: Int)
    
    init(buffer: TerminalBuffer) {
        self.buffer = buffer
        self.cursorPosition = (x: 0, y: 0)
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let fontSize: CGFloat = 25
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let cellHeight = fontSize + 4 // Slight padding for line height
        let cellWidth = font.advancement(forGlyph: NSGlyph(CGGlyph(" ".utf16.first!))).width
        
        // Draw the cursor at the current cursor position
        drawCursor(at: cursorPosition, with: cellWidth, and: cellHeight, in: context)
        
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
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
    
    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        if modifiers.contains(.control) {
            if keyCode == 0 {  // Control + A
                handleControlA()
            }
        } else {
            switch keyCode {
            case 123:  // Left Arrow
                handleArrowKey(direction: .left)
            case 124:  // Right Arrow
                handleArrowKey(direction: .right)
            case 125:  // Down Arrow
                handleArrowKey(direction: .down)
            case 126:  // Up Arrow
                handleArrowKey(direction: .up)
            case 53:   // Escape
                handleEscapeKey()
            case 51:   // Delete (Backspace)
                handleBackspace()
            default:
                super.keyDown(with: event)  // Let default behavior handle it
            }
        }
    }
    
    override func insertText(_ insertString: Any) {
        if let text = insertString as? String {
            handleTextInput(text)  // Handle typed characters
        }
    }
    
    private func handleArrowKey(direction: ArrowDirection) {
        switch direction {
        case .up:
            self.cursorPosition.y -= 1
            
        case .down:
            self.cursorPosition.y += 1
            
        case .left:
            self.cursorPosition.x -= 1
            
        case .right:
            self.cursorPosition.x += 1
        }
        self.setNeedsDisplay(self.bounds)
    }
    
    private func handleControlA() {
        // Handle Control + A behavior
    }
    
    private func handleEscapeKey() {
        // Handle Escape key behavior
    }
    
    private func handleBackspace() {
        // Handle Backspace behavior
    }
    
    private func handleTextInput(_ text: String) {
        print("Received text: \(text)")
        buffer.insertText(char: text.last ?? "2")
        self.setNeedsDisplay(self.bounds)
    }
}

enum ArrowDirection {
    case left, right, up, down
}
