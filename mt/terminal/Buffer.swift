//
//  Buffer.swift
//  mt
//
//  Created by Mano Rajesh on 10/15/24.
//

import Cocoa

struct CharacterCell {
    var character: Character
    var foregroundColor: RGBA
    var backgroundColor: RGBA
    var isBold: Bool
    var isUnderlined: Bool
    
    init(character: Character = " ",
         foregroundColor: RGBA = .white,
         backgroundColor: RGBA = .clear,
         isBold: Bool = false,
         isUnderlined: Bool = false) {
        self.character = character
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isUnderlined = isUnderlined
    }
}

class Buffer {
    // 2D buffer: [row][column]
    var buffer: [[CharacterCell]]
    
    // Terminal dimensions
    var rows: Int
    var cols: Int
    
    // Cursor position (x, y)
    var cursorX: Int = 0
    var cursorY: Int = 0
    
    // Current attributes
    private var currentAttributes: CharacterCell = CharacterCell()
    
    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.buffer = Array(repeating: Array(repeating: CharacterCell(), count: cols), count: rows)
    }
    
    // MARK: - Cursor Movement
    
    func moveCursorUp(_ n: Int) {
        cursorY = max(cursorY - n, 0)
    }
    
    func moveCursorDown(_ n: Int) {
        cursorY = min(cursorY + n, rows - 1)
    }
    
    func moveCursorForward(_ n: Int) {
        cursorX = min(cursorX + n, cols - 1)
    }
    
    func moveCursorBackward(_ n: Int) {
        cursorX = max(cursorX - n, 0)
    }
    
    func setCursorPosition(x: Int, y: Int) {
        cursorX = min(max(x, 0), cols - 1)
        cursorY = min(max(y, 0), rows - 1)
    }
    
    func scrollUp() {
        buffer.removeFirst()
        buffer.append(Array(repeating: CharacterCell(), count: cols))
        cursorY = rows - 1
    }
    
    // MARK: - Erase Functions
    
    func eraseInDisplay(mode: Int) {
        switch mode {
        case 0: // Cursor to end of screen
            eraseBelow()
        case 1: // Beginning of screen to cursor
            eraseAbove()
        case 2: // Entire screen
            buffer = Array(repeating: Array(repeating: CharacterCell(), count: cols), count: rows)
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
                currentAttributes = CharacterCell()
            case 1:
                currentAttributes.isBold = true
            case 4:
                currentAttributes.isUnderlined = true
            case 30...37:
                currentAttributes.foregroundColor = ansiColor(code - 30)
            case 40...47:
                currentAttributes.backgroundColor = ansiColor(code - 40)
            default:
                break
            }
        }
    }
    
    // MARK: - Character Handling
    
    func appendChar(_ char: Character) {
        // Cache cursor position locally
        var x = cursorX
        var y = cursorY
        let bufferRows = rows
        let bufferCols = cols
        
        // Ensure in-bounds
        guard y >= 0 && y < bufferRows, x >= 0 && x < bufferCols else { return }
        
        var cell = currentAttributes
        cell.character = char
        buffer[y][x] = cell
        
        // Update cursor position
        x += 1
        if x >= bufferCols {
            x = 0
            y += 1
            if y >= bufferRows {
                scrollUp()
                y = bufferRows - 1
            }
        }
        
        // Write back to cursorX and cursorY
        cursorX = x
        cursorY = y
    }
    
    func handleBackspace() {
        if cursorX > 0 {
            cursorX -= 1
            buffer[cursorY][cursorX] = CharacterCell()
        } else if cursorY > 0 {
            cursorY -= 1
            cursorX = cols - 1
        }
    }
    
    func addCarriageReturn() {
        cursorX = 0
    }
    
    func addLineFeed() {
        cursorY += 1
        if cursorY >= rows {
            scrollUp()
        }
    }
    
    func addNewLine() {
        addCarriageReturn()
        addLineFeed()
    }
    
    func advanceCursorToNextTabStop() {
        let tabSize = 8
        let nextTabStop = ((cursorX / tabSize) + 1) * tabSize
        cursorX = min(nextTabStop, cols - 1)
    }
    
    func resetAttributes() {
        currentAttributes = CharacterCell()
    }
    
    private func ansiColor(_ code: Int) -> RGBA {
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
        // Clear current line from cursor
        for x in cursorX..<cols {
            buffer[cursorY][x] = CharacterCell()
        }
        
        // Clear all lines below
        for y in (cursorY + 1)..<rows {
            buffer[y] = Array(repeating: CharacterCell(), count: cols)
        }
    }
    
    private func eraseAbove() {
        // Clear current line up to cursor
        for x in 0...cursorX {
            buffer[cursorY][x] = CharacterCell()
        }
        
        // Clear all lines above
        for y in 0..<cursorY {
            buffer[y] = Array(repeating: CharacterCell(), count: cols)
        }
    }
    
    private func eraseLineFromCursor() {
        for x in cursorX..<cols {
            buffer[cursorY][x] = CharacterCell()
        }
    }
    
    private func eraseLineToCursor() {
        for x in 0...cursorX {
            buffer[cursorY][x] = CharacterCell()
        }
    }
    
    private func eraseEntireLine() {
        buffer[cursorY] = Array(repeating: CharacterCell(), count: cols)
    }
    
    // MARK: - Resizing
    
    func resize(rows newRows: Int, cols newCols: Int) {
        var newBuffer = Array(repeating: Array(repeating: CharacterCell(), count: newCols), count: newRows)
        
        // Copy existing content that fits in the new dimensions
        for y in 0..<min(rows, newRows) {
            for x in 0..<min(cols, newCols) {
                newBuffer[y][x] = buffer[y][x]
            }
        }
        
        self.rows = newRows
        self.cols = newCols
        self.buffer = newBuffer
        
        // Ensure cursor is in-bounds
        cursorX = min(cursorX, newCols - 1)
        cursorY = min(cursorY, newRows - 1)
    }
}
