//
//  Buffer.swift
//  mt
//
//  Created by Mano Rajesh on 10/15/24.
//

import Cocoa

class Buffer {
    // 2D buffer: one line per row
    var buffer: [NSMutableAttributedString]
    
    // Terminal dimensions
    var rows: Int
    var cols: Int
    
    // Cursor position (x, y)
    var cursorPosition: (x: Int, y: Int) = (0, 0)
    
    // Text attributes
    var currentForegroundColor: NSColor = .white
    var currentBackgroundColor: NSColor = .clear
    var isBold: Bool = false
    var isUnderlined: Bool = false
    
    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        // Initialize buffer with empty lines
        self.buffer = Array(repeating: NSMutableAttributedString(), count: rows)
    }
    
    // MARK: - Cursor Movement
    
    func moveCursorUp(_ n: Int) {
        cursorPosition.y = max(cursorPosition.y - n, 0)
    }
    
    func moveCursorDown(_ n: Int) {
        cursorPosition.y = min(cursorPosition.y + n, rows - 1)
    }
    
    func moveCursorForward(_ n: Int) {
        cursorPosition.x = min(cursorPosition.x + n, cols - 1)
    }
    
    func moveCursorBackward(_ n: Int) {
        cursorPosition.x = max(cursorPosition.x - n, 0)
    }
    
    func setCursorPosition(x: Int, y: Int) {
        cursorPosition.x = min(max(x, 0), cols - 1)
        cursorPosition.y = min(max(y, 0), rows - 1)
    }
    
    func scrollUp() {
        // Remove the top row
        if !buffer.isEmpty {
            buffer.removeFirst()
        }
        // Append an empty line at the bottom
        buffer.append(NSMutableAttributedString())
        
        // Clamp cursor to the last row
        cursorPosition.y = rows - 1
    }
    
    // MARK: - Erase Functions
    
    func eraseInDisplay(mode: Int) {
        switch mode {
        case 0: // Cursor to end of screen
            eraseBelow()
        case 1: // Beginning of screen to cursor
            eraseAbove()
        case 2: // Entire screen
            buffer = Array(repeating: NSMutableAttributedString(), count: rows)
            setCursorPosition(x: 0, y: 0)
        default:
            break
        }
    }
    
    func eraseInLine(mode: Int) {
        switch mode {
        case 0: // Cursor to end of line
            eraseLineFromCursor()
        case 1: // Start of line to cursor
            eraseLineToCursor()
        case 2: // Entire line
            eraseEntireLine()
        default:
            break
        }
    }
    
    // MARK: - Graphic Rendition
    
    func applyGraphicRendition(_ params: [Int]) {
        for code in params {
            switch code {
            case 0:
                resetAttributes()
            case 1:
                isBold = true
            case 4:
                isUnderlined = true
            case 30...37:
                currentForegroundColor = ansiColor(code - 30)
            case 40...47:
                currentBackgroundColor = ansiColor(code - 40)
            default:
                break
            }
        }
    }
    
    // MARK: - Character Handling
    
    func appendChar(_ char: Character) {
        let currentRow = cursorPosition.y
        guard currentRow >= 0 && currentRow < rows else { return }
        
        let line = buffer[currentRow]
        
        // Pad with spaces if needed
        if cursorPosition.x > line.length {
            let spaces = String(repeating: " ", count: cursorPosition.x - line.length)
            line.append(NSAttributedString(string: spaces))
        }
        
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: currentForegroundColor,
            .backgroundColor: currentBackgroundColor,
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: isBold ? .bold : .regular)
        ]
        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        
        if cursorPosition.x < line.length {
            line.replaceCharacters(
                in: NSRange(location: cursorPosition.x, length: 1),
                with: NSAttributedString(string: String(char), attributes: attributes)
            )
        } else {
            line.append(NSAttributedString(string: String(char), attributes: attributes))
        }
        
        cursorPosition.x += 1
        if cursorPosition.x >= cols {
            cursorPosition.x = 0
            cursorPosition.y += 1
            if cursorPosition.y >= rows {
                scrollUp()
            }
        }
    }
    
    func handleBackspace() {
        if cursorPosition.x > 0 {
            cursorPosition.x -= 1
        } else if cursorPosition.y > 0 {
            cursorPosition.y -= 1
            cursorPosition.x = cols - 1
        }
        
        let currentRow = cursorPosition.y
        guard currentRow >= 0 && currentRow < rows else { return }
        
        let line = buffer[currentRow]
        if line.length > cursorPosition.x {
            line.deleteCharacters(in: NSRange(location: cursorPosition.x, length: 1))
        }
    }
    
    func addCarriageReturn() {
        cursorPosition.x = 0
    }
    
    func addLineFeed() {
        cursorPosition.y += 1
        if cursorPosition.y >= rows {
            scrollUp()
        }
    }
    
    func addNewLine() {
        addCarriageReturn()
        addLineFeed()
    }
    
    func advanceCursorToNextTabStop() {
        let tabSize = 8
        let nextTabStop = ((cursorPosition.x / tabSize) + 1) * tabSize
        cursorPosition.x = min(nextTabStop, cols - 1)
    }
    
    func resetAttributes() {
        currentForegroundColor = .white
        currentBackgroundColor = .clear
        isBold = false
        isUnderlined = false
    }
    
    private func ansiColor(_ code: Int) -> NSColor {
        switch code {
        case 0: return .black
        case 1: return .red
        case 2: return .green
        case 3: return .yellow
        case 4: return .blue
        case 5: return .magenta
        case 6: return .cyan
        case 7: return .white
        default: return .white
        }
    }
    
    // MARK: - Erase Implementations
    
    private func eraseBelow() {
        let y = cursorPosition.y
        let x = cursorPosition.x
        
        // Erase current line from cursor to end
        if y >= 0 && y < buffer.count {
            let line = buffer[y]
            if line.length > x {
                line.deleteCharacters(in: NSRange(location: x, length: line.length - x))
            }
        }
        
        // Erase all lines below
        for row in (y + 1)..<buffer.count {
            buffer[row] = NSMutableAttributedString()
        }
    }
    
    private func eraseAbove() {
        let y = cursorPosition.y
        let x = cursorPosition.x
        
        // Erase current line from start to cursor
        if y >= 0 && y < buffer.count {
            let line = buffer[y]
            if x >= 0 {
                let length = min(x + 1, line.length)
                line.deleteCharacters(in: NSRange(location: 0, length: length))
            }
        }
        
        // Erase all lines above
        for row in 0..<y {
            buffer[row] = NSMutableAttributedString()
        }
    }
    
    private func eraseLineFromCursor() {
        let y = cursorPosition.y
        let x = cursorPosition.x
        
        if y >= 0 && y < buffer.count {
            let line = buffer[y]
            if line.length > x {
                line.deleteCharacters(in: NSRange(location: x, length: line.length - x))
            }
        }
    }
    
    private func eraseLineToCursor() {
        let y = cursorPosition.y
        let x = cursorPosition.x
        
        if y >= 0 && y < buffer.count {
            let line = buffer[y]
            if x >= 0 {
                let length = min(x + 1, line.length)
                line.deleteCharacters(in: NSRange(location: 0, length: length))
            }
        }
    }
    
    private func eraseEntireLine() {
        let y = cursorPosition.y
        if y >= 0 && y < buffer.count {
            buffer[y] = NSMutableAttributedString()
        }
    }
    
    // MARK: - Resizing
    
    func resize(rows newRows: Int, cols newCols: Int) {
        self.rows = newRows
        self.cols = newCols
        
        // Adjust buffer size
        if newRows > buffer.count {
            let additional = newRows - buffer.count
            buffer.append(contentsOf: Array(repeating: NSMutableAttributedString(), count: additional))
        } else if newRows < buffer.count {
            buffer.removeLast(buffer.count - newRows)
        }
        
        // Ensure cursor is in-bounds
        cursorPosition.x = min(cursorPosition.x, newCols - 1)
        cursorPosition.y = min(cursorPosition.y, newRows - 1)
    }
}
