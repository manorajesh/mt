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

class TerminalBuffer {
    var buffer: [[CharacterCell]]  // Array of rows, each containing an array of CharacterCells
    var columns: Int
    var rows: Int
    var currentPosition = (0, 0)
    let charSet: [Character] = Array("1234567890abcdefghijklmnopqrstuvwxyz")  // Convert to array of Characters
    
    init(columns: Int, rows: Int) {
//        self.buffer = Array(repeating: Array(repeating: CharacterCell(character: "\0",
//                                                                      foregroundColor: .white,
//                                                                      backgroundColor: .clear,
//                                                                      isBold: false,
//                                                                      isUnderlined: false), count: columns), count: rows)

        var idx = 0
        self.buffer = Array()
        for i in 0..<rows {
            self.buffer.append(Array())
            for _ in 0..<columns {
                let char = charSet[idx % charSet.count]  // Access character directly by index
                self.buffer[i].append(CharacterCell(character: char,
                                                    foregroundColor: .white,
                                                    backgroundColor: .clear,
                                                    isBold: false,
                                                    isUnderlined: false))
                idx += 1
            }
        }
        self.rows = rows
        self.columns = columns
    }
    
    public func insertText(char: Character) {
//        if self.buffer.last!.count == self.columns {
//            self.buffer.append(Array())
//        }
        self.buffer[self.currentPosition.0][self.currentPosition.1] = CharacterCell(character: char, foregroundColor: .white, backgroundColor: .clear, isBold: false, isUnderlined: false)
        
        self.currentPosition.1 += 1
        if self.currentPosition.1 >= columns {
            self.currentPosition.1 = 0
            self.currentPosition.0 += 1
        }
    }
}
