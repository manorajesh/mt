//
//  Buffer.swift
//  mt
//
//  Created by Mano Rajesh on 10/15/24.
//

struct CharacterCell {
    var asciiCode: UInt8
    var foregroundColor: SIMD4<Float> // RGBA
    var backgroundColor: SIMD4<Float> // RGBA
    var isBold: Bool
    var isUnderlined: Bool
    
    init(asciiCode: UInt8 = 32, // ASCII for space
         foregroundColor: SIMD4<Float> = Colors.white,
         backgroundColor: SIMD4<Float> = Colors.clear,
         isBold: Bool = false,
         isUnderlined: Bool = false) {
        self.asciiCode = asciiCode
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isUnderlined = isUnderlined
    }
}

class Buffer {
    // 1D buffer with circular indexing
    var buffer: [CharacterCell]
    private var bufferStart: Int = 0  // Start of circular buffer
    
    // Terminal dimensions
    var rows: Int
    var cols: Int
    
    var cursorX: Int = 0
    var cursorY: Int = 0
    
    private var currentAttributes: CharacterCell = CharacterCell()
    
    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.buffer = Array(repeating: CharacterCell(), count: rows * cols)
    }
    
    // Convert 2D coordinates to 1D index
    func index(row: Int, col: Int) -> Int {
        let realRow = (bufferStart + row) % rows
        return (realRow * cols + col)
    }
    
    // Access with subscript
    subscript(row: Int, col: Int) -> CharacterCell {
        get {
            buffer[index(row: row, col: col)]
        }
        set {
            buffer[index(row: row, col: col)] = newValue
        }
    }
    
    // Scroll one line
    func scrollUp() {
        bufferStart = (bufferStart + 1) % rows
        // Clear new line
        let newLineStart = index(row: rows - 1, col: 0)
        var col = 0
        while col < cols {
            buffer[newLineStart + col] = CharacterCell()
            col += 1
        }
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
    
    // MARK: - Erase Functions
    
    func eraseInDisplay(mode: Int) {
        switch mode {
        case 0: // Cursor to end of screen
            eraseBelow()
        case 1: // Beginning of screen to cursor
            eraseAbove()
        case 2: // Entire screen
            buffer = Array(repeating: CharacterCell(), count: rows * cols)
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
    
    func appendChar(_ byte: UInt8) {
        // Ensure in-bounds cursor
        guard cursorY >= 0 && cursorY < rows, cursorX >= 0 && cursorX < cols else { return }
        
        // Write character to buffer
        var cell = currentAttributes
        cell.asciiCode = byte
        buffer[index(row: cursorY, col: cursorX)] = cell
        
        // Move cursor forward
        cursorX += 1
        if cursorX >= cols {
            cursorX = 0
            cursorY += 1
            
            // Scroll up if the cursor moves past the last row
            if cursorY >= rows {
                scrollUp()
                cursorY = rows - 1
            }
        }
    }

    
    func handleBackspace() {
        if cursorX > 0 {
            cursorX -= 1
            buffer[index(row: cursorY, col: cursorX)] = CharacterCell()
        } else if cursorY > 0 {
            cursorY -= 1
            cursorX = cols - 1
            buffer[index(row: cursorY, col: cursorX)] = CharacterCell()
        }
    }
    
    func addCarriageReturn() {
        cursorX = 0
    }
    
    func addLineFeed() {
        cursorY += 1
        if cursorY >= rows {
            scrollUp()
            cursorY = rows - 1
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
    
    private func ansiColor(_ code: Int) -> SIMD4<Float> {
        switch code {
        case 0: return Colors.black
        case 1: return Colors.red
        case 2: return Colors.green
        case 3: return Colors.yellow
        case 4: return Colors.blue
        case 5: return Colors.magenta
        case 6: return Colors.cyan
        case 7: return Colors.white
        default: return Colors.white
        }
    }
    
    // MARK: - Erase Implementations
    
    private func eraseBelow() {
        // Clear current line from cursor
        for col in cursorX..<cols {
            buffer[index(row: cursorY, col: col)] = CharacterCell()
        }
        // Clear all lines below
        for row in (cursorY + 1)..<rows {
            for col in 0..<cols {
                buffer[index(row: row, col: col)] = CharacterCell()
            }
        }
    }
    
    private func eraseAbove() {
        // Clear current line up to cursor
        for col in 0...cursorX {
            buffer[index(row: cursorY, col: col)] = CharacterCell()
        }
        // Clear all lines above
        for row in 0..<cursorY {
            for col in 0..<cols {
                buffer[index(row: row, col: col)] = CharacterCell()
            }
        }
    }
    
    private func eraseLineFromCursor() {
        for col in cursorX..<cols {
            buffer[index(row: cursorY, col: col)] = CharacterCell()
        }
    }
    
    private func eraseLineToCursor() {
        for col in 0...cursorX {
            buffer[index(row: cursorY, col: col)] = CharacterCell()
        }
    }

    
    private func eraseEntireLine() {
        for col in 0..<cols {
            buffer[index(row: cursorY, col: col)] = CharacterCell()
        }
    }

    
    // MARK: - Resizing
    
    func resize(rows newRows: Int, cols newCols: Int) {
        var newBuffer = Array(repeating: CharacterCell(), count: newRows * newCols)
        
        for row in 0..<min(rows, newRows) {
            for col in 0..<min(cols, newCols) {
                newBuffer[row * newCols + col] = self[row, col]
            }
        }
        
        buffer = newBuffer
        rows = newRows
        cols = newCols
        bufferStart = 0
        cursorX = min(cursorX, newCols - 1)
        cursorY = min(cursorY, newRows - 1)
    }

}
