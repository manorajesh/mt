import Cocoa

struct CharacterCell {
    var character: Character
    var foregroundColor: NSColor
    var backgroundColor: NSColor
    var isBold: Bool
    var isUnderlined: Bool
    
    init(character: Character = " ",
         foregroundColor: NSColor = .white,
         backgroundColor: NSColor = .clear,
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
    var cursorPosition: (x: Int, y: Int) = (0, 0)
    
    // Current attributes
    private var currentAttributes: CharacterCell = CharacterCell()
    
    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.buffer = Array(repeating: Array(repeating: CharacterCell(), count: cols), count: rows)
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
        buffer.removeFirst()
        buffer.append(Array(repeating: CharacterCell(), count: cols))
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
        guard cursorPosition.y >= 0 && cursorPosition.y < rows,
              cursorPosition.x >= 0 && cursorPosition.x < cols else { return }
        
        var cell = currentAttributes
        cell.character = char
        buffer[cursorPosition.y][cursorPosition.x] = cell
        
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
            buffer[cursorPosition.y][cursorPosition.x] = CharacterCell()
        } else if cursorPosition.y > 0 {
            cursorPosition.y -= 1
            cursorPosition.x = cols - 1
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
        currentAttributes = CharacterCell()
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
        // Clear current line from cursor
        for x in cursorPosition.x..<cols {
            buffer[cursorPosition.y][x] = CharacterCell()
        }
        
        // Clear all lines below
        for y in (cursorPosition.y + 1)..<rows {
            buffer[y] = Array(repeating: CharacterCell(), count: cols)
        }
    }
    
    private func eraseAbove() {
        // Clear current line up to cursor
        for x in 0...cursorPosition.x {
            buffer[cursorPosition.y][x] = CharacterCell()
        }
        
        // Clear all lines above
        for y in 0..<cursorPosition.y {
            buffer[y] = Array(repeating: CharacterCell(), count: cols)
        }
    }
    
    private func eraseLineFromCursor() {
        for x in cursorPosition.x..<cols {
            buffer[cursorPosition.y][x] = CharacterCell()
        }
    }
    
    private func eraseLineToCursor() {
        for x in 0...cursorPosition.x {
            buffer[cursorPosition.y][x] = CharacterCell()
        }
    }
    
    private func eraseEntireLine() {
        buffer[cursorPosition.y] = Array(repeating: CharacterCell(), count: cols)
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
        cursorPosition.x = min(cursorPosition.x, newCols - 1)
        cursorPosition.y = min(cursorPosition.y, newRows - 1)
    }
}
