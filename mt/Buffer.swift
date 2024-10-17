//
//  Buffer.swift
//  mt
//
//  Created by Mano Rajesh on 10/15/24.
//

import Cocoa

struct CharacterCell {
    var character: Character
    var foregroundColor: NSColor
    var backgroundColor: NSColor
    var isBold: Bool
    var isUnderlined: Bool
}

struct Viewport {
    var topRow: Int
    var rows: Int
    var cols: Int
}

class Buffer {
    var buffer: [Int: [CharacterCell]] = [:]
    var viewport: Viewport
    var cursorPosition: (x: Int, y: Int) = (0, 0)
    var defaultCell: CharacterCell = CharacterCell(
        character: "\0",
        foregroundColor: .white,
        backgroundColor: .clear,
        isBold: false,
        isUnderlined: false
    )
    
    // Text attributes
    var currentForegroundColor: NSColor = .white
    var currentBackgroundColor: NSColor = .clear
    var isBold: Bool = false
    var isUnderlined: Bool = false
    
    init(rows: Int, cols: Int) {
        self.viewport = Viewport(topRow: 0, rows: rows, cols: cols)
    }
    
    // Move cursor up by n positions
    func moveCursorUp(_ n: Int) {
        cursorPosition.y = max(cursorPosition.y - n, 0)
    }
    
    // Move cursor down by n positions
    func moveCursorDown(_ n: Int) {
        cursorPosition.y += n
    }
    
    // Move cursor forward by n positions
    func moveCursorForward(_ n: Int) {
        cursorPosition.x += n
    }
    
    // Move cursor backward by n positions
    func moveCursorBackward(_ n: Int) {
        cursorPosition.x = max(cursorPosition.x - n, 0)
    }
    
    // Set cursor position
    func setCursorPosition(x: Int, y: Int) {
        cursorPosition.x = x
        cursorPosition.y = y
    }
    
    // Erase in display
    func eraseInDisplay(mode: Int) {
        switch mode {
        case 0:
            // Clear from cursor to end of screen
            eraseBelow()
        case 1:
            // Clear from cursor to beginning of screen
            eraseAbove()
        case 2:
            // Clear entire screen
            buffer.removeAll()
        default:
            break
        }
    }
    
    // Erase in line
    func eraseInLine(mode: Int) {
        switch mode {
        case 0:
            // Clear from cursor to end of line
            eraseLineFromCursor()
        case 1:
            // Clear from beginning of line to cursor
            eraseLineToCursor()
        case 2:
            // Clear entire line
            eraseEntireLine()
        default:
            break
        }
    }
    
    // Apply graphic rendition
    func applyGraphicRendition(_ params: [Int]) {
        for code in params {
            switch code {
            case 0:
                // Reset all attributes
                resetAttributes()
            case 1:
                isBold = true
            case 4:
                isUnderlined = true
            case 30...37:
                // Set foreground color
                currentForegroundColor = ansiColor(code - 30)
            case 40...47:
                // Set background color
                currentBackgroundColor = ansiColor(code - 40)
            default:
                // Handle other SGR codes
                break
            }
        }
    }
    
    // Append character at current cursor position
    func appendChar(_ char: Character) {
        // Ensure the buffer has enough size to handle the current cursor position
        ensureSize(forRow: cursorPosition.y, forColumn: cursorPosition.x)
        
        // Create character cell with current attributes
        let charCell = CharacterCell(
            character: char,
            foregroundColor: currentForegroundColor,
            backgroundColor: currentBackgroundColor,
            isBold: isBold,
            isUnderlined: isUnderlined
        )
        
        // Insert the character at the current cursor position
        buffer[cursorPosition.y]?[cursorPosition.x] = charCell
        
        // Move the cursor to the right after inserting the character
        cursorPosition.x += 1
    }
    
    func handleBackspace() {
        if cursorPosition.x > 0 {
            cursorPosition.x -= 1
        }
    }
    
    func addCarriageReturn() {
        cursorPosition.x = 0
    }
    
    func addLineFeed() {
        cursorPosition.y += 1
        buffer[cursorPosition.y] = []
        while cursorPosition.y >= viewport.topRow + viewport.rows {
            viewport.topRow += 1
        }
    }
    
    func addNewLine() {
        addCarriageReturn()
        addLineFeed()
    }
    
    // Advance cursor to the next tab stop (assuming tab stops every 8 columns)
    func advanceCursorToNextTabStop() {
        let tabSize = 8
        let nextTabStop = ((cursorPosition.x / tabSize) + 1) * tabSize
        cursorPosition.x = nextTabStop
    }
    
    // Reset text attributes to default
    func resetAttributes() {
        currentForegroundColor = .white
        currentBackgroundColor = .clear
        isBold = false
        isUnderlined = false
    }
    
    // Map ANSI color codes to NSColor
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
    
    // Ensure the buffer has enough columns in a specific row
    private func ensureSize(forRow row: Int, forColumn col: Int) {
        if buffer[row] == nil {
            buffer[row] = []
        }
        while buffer[row]!.count <= col {
            buffer[row]!.append(defaultCell)
        }
    }
    
    // Erase from cursor to end of screen
    private func eraseBelow() {
        // Erase current line from cursor to end
        eraseLineFromCursor()
        
        // Remove lines below cursor
        let currentRow = cursorPosition.y
        let rowsToRemove = buffer.keys.filter { $0 > currentRow }
        for row in rowsToRemove {
            buffer.removeValue(forKey: row)
        }
    }
    
    // Erase from cursor to beginning of screen
    private func eraseAbove() {
        // Erase current line from beginning to cursor
        eraseLineToCursor()
        
        // Remove lines above cursor
        let currentRow = cursorPosition.y
        let rowsToRemove = buffer.keys.filter { $0 < currentRow }
        for row in rowsToRemove {
            buffer.removeValue(forKey: row)
        }
    }
    
    // Erase from cursor to end of line
    private func eraseLineFromCursor() {
        ensureSize(forRow: cursorPosition.y, forColumn: cursorPosition.x)
        if var row = buffer[cursorPosition.y] {
            for i in cursorPosition.x..<row.count {
                row[i] = defaultCell
            }
            buffer[cursorPosition.y] = row
        }
    }
    
    // Erase from beginning of line to cursor
    private func eraseLineToCursor() {
        ensureSize(forRow: cursorPosition.y, forColumn: cursorPosition.x)
        if var row = buffer[cursorPosition.y] {
            for i in 0...cursorPosition.x {
                row[i] = defaultCell
            }
            buffer[cursorPosition.y] = row
        }
    }
    
    // Erase entire line
    private func eraseEntireLine() {
        ensureSize(forRow: cursorPosition.y, forColumn: viewport.cols - 1)
        buffer[cursorPosition.y] = Array(repeating: defaultCell, count: viewport.cols)
    }
    
    // Resize the viewport dimensions
    public func resizeViewport(rows: Int, cols: Int) {
        self.viewport.rows = rows
        self.viewport.cols = cols
    }
}
