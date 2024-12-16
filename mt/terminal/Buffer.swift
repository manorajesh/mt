//
//  Buffer.swift
//  mt
//
//  Created by Mano Rajesh on 10/15/24.
//

import Cocoa

struct Viewport {
    var topRow: Int
    var rows: Int
    var cols: Int
}

class Buffer {
    var viewportBuffer: [NSMutableAttributedString]
    var scrollbackBuffer: [NSMutableAttributedString]
    var viewport: Viewport
    var cursorPosition: (x: Int, y: Int) = (0, 0)
    
    // Set to keep track of dirty rows
    private var dirtyRows: Set<Int> = []
    
    // Text attributes
    var currentForegroundColor: NSColor = .white
    var currentBackgroundColor: NSColor = .clear
    var isBold: Bool = false
    var isUnderlined: Bool = false
    
    init(rows: Int, cols: Int) {
        self.viewport = Viewport(topRow: 0, rows: rows, cols: cols)
        // Initialize the viewport buffer with empty lines
        self.viewportBuffer = Array(repeating: NSMutableAttributedString(), count: rows)
        // Initialize the scrollback buffer
        self.scrollbackBuffer = []
    }
    
    // MARK: - Cursor Movement
    
    // Move cursor up by n positions
    func moveCursorUp(_ n: Int) {
        cursorPosition.y = max(cursorPosition.y - n, 0)
    }
    
    // Move cursor down by n positions
    func moveCursorDown(_ n: Int) {
        cursorPosition.y = min(cursorPosition.y + n, viewport.rows - 1)
    }
    
    // Move cursor forward by n positions
    func moveCursorForward(_ n: Int) {
        cursorPosition.x = min(cursorPosition.x + n, viewport.cols - 1)
    }
    
    // Move cursor backward by n positions
    func moveCursorBackward(_ n: Int) {
        cursorPosition.x = max(cursorPosition.x - n, 0)
    }
    
    // Set cursor position
    func setCursorPosition(x: Int, y: Int) {
        cursorPosition.x = min(max(x, 0), viewport.cols - 1)
        cursorPosition.y = min(max(y, 0), viewport.rows - 1)
    }
    
    // MARK: - Erase Functions
    
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
            viewportBuffer = Array(repeating: NSMutableAttributedString(), count: viewport.rows)
            scrollbackBuffer.removeAll()
            setCursorPosition(x: 0, y: 0)
            // Mark all rows as dirty
            for row in 0..<viewport.rows {
                dirtyRows.insert(row)
            }
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
    
    // MARK: - Graphic Rendition
    
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
                // Handle other SGR codes if necessary
                break
            }
        }
    }
    
    // MARK: - Character Handling
    
    // Append character at current cursor position
    func appendChar(_ char: Character) {
        let currentRow = cursorPosition.y
        
        // Ensure the cursor is within the viewport buffer
        guard currentRow >= 0 && currentRow < viewport.rows else {
            return
        }
        
        // Initialize line if needed
        let line = viewportBuffer[currentRow]
        
        // Fill the line with spaces if cursor.x is beyond current length
        if cursorPosition.x > line.length {
            let spaces = String(repeating: " ", count: cursorPosition.x - line.length)
            line.append(NSAttributedString(string: spaces))
        }
        
        // Create attributes for the character
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: currentForegroundColor,
            .backgroundColor: currentBackgroundColor,
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: isBold ? .bold : .regular)
        ]
        
        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        
        // Replace character at cursor position if necessary
        if cursorPosition.x < line.length {
            line.replaceCharacters(in: NSRange(location: cursorPosition.x, length: 1), with: NSAttributedString(string: String(char), attributes: attributes))
        } else {
            line.append(NSAttributedString(string: String(char), attributes: attributes))
        }
        
        // Mark the current row as dirty
        dirtyRows.insert(currentRow)
        
        // Move the cursor to the right after inserting the character
        cursorPosition.x += 1
        if cursorPosition.x >= viewport.cols {
            cursorPosition.x = 0
            cursorPosition.y += 1
            if cursorPosition.y >= viewport.rows {
                scrollUp()
            }
        }
    }
    
    // Handle backspace
    func handleBackspace() {
        if cursorPosition.x > 0 {
            cursorPosition.x -= 1
        } else if cursorPosition.y > 0 {
            cursorPosition.y -= 1
            cursorPosition.x = viewport.cols - 1
        }
        
        let currentRow = cursorPosition.y
        if currentRow < 0 || currentRow >= viewportBuffer.count {
            return
        }
        
        let line = viewportBuffer[currentRow]
        if line.length > cursorPosition.x {
            line.deleteCharacters(in: NSRange(location: cursorPosition.x, length: 1))
            // Mark the current row as dirty
            dirtyRows.insert(currentRow)
        }
    }
    
    // Add carriage return
    func addCarriageReturn() {
        cursorPosition.x = 0
    }
    
    // Add line feed
    func addLineFeed() {
        cursorPosition.y += 1
        if cursorPosition.y >= viewport.rows {
            scrollUp()
        }
    }
    
    // Add new line
    func addNewLine() {
        addCarriageReturn()
        addLineFeed()
    }
    
    // Advance cursor to the next tab stop (assuming tab stops every 8 columns)
    func advanceCursorToNextTabStop() {
        let tabSize = 8
        let nextTabStop = ((cursorPosition.x / tabSize) + 1) * tabSize
        cursorPosition.x = min(nextTabStop, viewport.cols - 1)
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
    
    // MARK: - Erase Implementations
    
    // Erase from cursor to end of screen
    private func eraseBelow() {
        let currentRow = cursorPosition.y
        let currentCol = cursorPosition.x
        
        // Erase current line from cursor to end
        if currentRow >= 0 && currentRow < viewportBuffer.count {
            let line = viewportBuffer[currentRow]
            if line.length > currentCol {
                line.deleteCharacters(in: NSRange(location: currentCol, length: line.length - currentCol))
                // Mark the current row as dirty
                dirtyRows.insert(currentRow)
            }
        }
        
        // Erase all lines below the current row
        for y in (currentRow + 1)..<viewportBuffer.count {
            viewportBuffer[y] = NSMutableAttributedString()
            // Mark these rows as dirty
            dirtyRows.insert(y)
        }
    }
    
    // Erase from cursor to beginning of screen
    private func eraseAbove() {
        let currentRow = cursorPosition.y
        let currentCol = cursorPosition.x
        
        // Erase current line from beginning to cursor
        if currentRow >= 0 && currentRow < viewportBuffer.count {
            let line = viewportBuffer[currentRow]
            if currentCol >= 0 {
                let length = min(currentCol + 1, line.length)
                line.deleteCharacters(in: NSRange(location: 0, length: length))
                // Mark the current row as dirty
                dirtyRows.insert(currentRow)
            }
        }
        
        // Erase all lines above the current row
        for y in 0..<currentRow {
            viewportBuffer[y] = NSMutableAttributedString()
            // Mark these rows as dirty
            dirtyRows.insert(y)
        }
    }
    
    // Erase from cursor to end of line
    private func eraseLineFromCursor() {
        let currentRow = cursorPosition.y
        let currentCol = cursorPosition.x
        
        if currentRow >= 0 && currentRow < viewportBuffer.count {
            let line = viewportBuffer[currentRow]
            if line.length > currentCol {
                line.deleteCharacters(in: NSRange(location: currentCol, length: line.length - currentCol))
                // Mark the current row as dirty
                dirtyRows.insert(currentRow)
            }
        }
    }
    
    // Erase from beginning of line to cursor
    private func eraseLineToCursor() {
        let currentRow = cursorPosition.y
        let currentCol = cursorPosition.x
        
        if currentRow >= 0 && currentRow < viewportBuffer.count {
            let line = viewportBuffer[currentRow]
            if currentCol >= 0 {
                let length = min(currentCol + 1, line.length)
                line.deleteCharacters(in: NSRange(location: 0, length: length))
                // Mark the current row as dirty
                dirtyRows.insert(currentRow)
            }
        }
    }
    
    // Erase entire line
    private func eraseEntireLine() {
        let currentRow = cursorPosition.y
        
        if currentRow >= 0 && currentRow < viewportBuffer.count {
            viewportBuffer[currentRow] = NSMutableAttributedString()
            // Mark the current row as dirty
            dirtyRows.insert(currentRow)
        }
    }
    
    // MARK: - Viewport Management
    
    // Resize the viewport dimensions
    public func resizeViewport(rows: Int, cols: Int) {
        self.viewport.rows = rows
        self.viewport.cols = cols
        
        // Adjust viewport buffer size
        if rows > viewportBuffer.count {
            let additionalRows = rows - viewportBuffer.count
            viewportBuffer.append(contentsOf: Array(repeating: NSMutableAttributedString(), count: additionalRows))
        } else if rows < viewportBuffer.count {
            let removedLines = viewportBuffer[rows...]
            scrollbackBuffer.insert(contentsOf: removedLines, at: 0)
            viewportBuffer = Array(viewportBuffer[0..<rows])
        }
        
        // Ensure cursor is within new viewport
        cursorPosition.x = min(cursorPosition.x, cols - 1)
        cursorPosition.y = min(cursorPosition.y, rows - 1)
        
        // Mark all rows as dirty since the viewport changed
        for row in 0..<viewport.rows {
            dirtyRows.insert(row)
        }
    }
    
    // Scroll the buffer up by one row
    public func scrollUp() {
        // Move the first line of the viewport buffer to the scrollback buffer
        if let firstLine = viewportBuffer.first {
            scrollbackBuffer.append(firstLine)
            viewportBuffer.removeFirst()
            viewportBuffer.append(NSMutableAttributedString())
            // Adjust dirty rows
            //            dirtyRows = Set(dirtyRows.map { $0 - 1 })
            //            dirtyRows.insert(viewport.rows - 1)
            for index in 0..<viewport.rows {
                dirtyRows.insert(index)
            }
        }
        cursorPosition.y = max(cursorPosition.y - 1, viewport.rows - 1)
    }
    
    // MARK: - Dirty Rows Handling
    
    // Get the list of dirty rows and clear the set
    public func getDirtyRows() -> [Int] {
        let rows = Array(dirtyRows)
        dirtyRows.removeAll()
        return rows.sorted()
    }

    // Get dirty rows with content and clear the dirty set
    public func getDirtyRowsWithContent() -> [(row: Int, content: NSMutableAttributedString)] {
        let dirtyRowsArray = Array(dirtyRows)
        dirtyRows.removeAll()
        return dirtyRowsArray.map { ($0, viewportBuffer[$0]) }
    }
}
