//
//  TerminalBuffer.swift
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
    var buffer: [[CharacterCell]] = [[]]
    var viewport: Viewport
    
    init(rows: Int, cols: Int) {
        self.viewport = Viewport(topRow: 0, rows: rows, cols: cols)
    }
    
    public func appendChar(_ char: Character) {
        if char == "\r\n" {
            self.buffer.append([])
            return
        }
        
        let charCell = CharacterCell(character: char, foregroundColor: .white, backgroundColor: .clear, isBold: false, isUnderlined: false)
        self.buffer[self.buffer.count - 1].append(charCell)
    }
    
    public func insertChar(_ char: Character, row: Int, col: Int) {
        guard row > 0 && row < self.buffer.count else { return }
        guard col > 0 && col < self.buffer[row].count else { return }
        
        let charCell = CharacterCell(character: char, foregroundColor: .white, backgroundColor: .clear, isBold: false, isUnderlined: false)
        self.buffer[row][col] = charCell
    }
    
    public func resizeViewport(rows: Int, cols: Int) {
        self.viewport.rows = rows
        self.viewport.cols = cols
    }
}
