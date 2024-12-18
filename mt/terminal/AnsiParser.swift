//
//  AnsiParser.swift
//  mt
//
//  Created by Mano Rajesh on 10/17/24.
//

import Foundation
import OSLog

class AnsiParser {
    enum ParserState {
        case normal
        case escape
        case csi
        case osc
        case sosPmApc
    }
    
    private var state: ParserState = .normal
    private var paramBuffer = ""
    private var params: [Int] = []
    private var intermediateChars = ""
    private var finalChar: Character?
    private var oscString = ""
    
    private var buffer: Buffer
    
    init(buffer: Buffer) {
        self.buffer = buffer
    }
    
    func parse(byte: UInt8) {
        let char = Character(UnicodeScalar(byte))
        switch state {
        case .normal:
            if char == "\u{1B}" {
                state = .escape
            } else if byte == 0x08 {
                buffer.handleBackspace()
            } else if char == "\n" {
                buffer.addNewLine()
            } else if char == "\r" {
                buffer.addCarriageReturn()
            } else if char == "\t" {
                buffer.advanceCursorToNextTabStop()
            } else {
                buffer.appendChar(char)
            }
        case .escape:
            if char == "[" {
                state = .csi
                params = []
                paramBuffer = ""
                intermediateChars = ""
            } else if char == "]" {
                state = .osc
                oscString = ""
            } else if char == "P" || char == "_" || char == "^" || char == "X" {
                state = .sosPmApc
                // Start of Device Control String, Operating System Command, etc.
            } else if char == "(" || char == ")" {
                // Character set selection, skip for now
                state = .normal
            } else {
                // Other escape sequences can be handled here
                state = .normal
            }
        case .csi:
            if char.isNumber {
                paramBuffer.append(char)
            } else if char == ";" {
                params.append(Int(paramBuffer) ?? 0)
                paramBuffer = ""
            } else if (char >= "\u{20}" && char <= "\u{2F}") {
                intermediateChars.append(char)
            } else if (char >= "\u{40}" && char <= "\u{7E}") {
                // Final character of CSI sequence
                if !paramBuffer.isEmpty {
                    params.append(Int(paramBuffer) ?? 0)
                    paramBuffer = ""
                }
                finalChar = char
                handleCsiSequence(params: params, command: finalChar!)
                state = .normal
            }
        case .osc:
            if char == "\u{07}" || (char == "\u{1B}" && oscString.last == "\\") {
                // End of OSC sequence (BEL or ST)
                // Handle OSC sequence if necessary
                state = .normal
                oscString = ""
            } else {
                oscString.append(char)
            }
        case .sosPmApc:
            if char == "\u{07}" || (char == "\u{1B}" && oscString.last == "\\") {
                // End of string sequence
                state = .normal
                // Handle SOS/PM/APC sequence if necessary
            } else {
                // Collect characters
            }
        }
    }
    
    private func handleCsiSequence(params: [Int], command: Character) {
        switch command {
        case "A":
            // Cursor Up
            let n = params.first ?? 1
            buffer.moveCursorUp(n)
        case "B":
            // Cursor Down
            let n = params.first ?? 1
            buffer.moveCursorDown(n)
        case "C":
            // Cursor Forward
            let n = params.first ?? 1
            buffer.moveCursorForward(n)
        case "D":
            // Cursor Backward
            let n = params.first ?? 1
            buffer.moveCursorBackward(n)
        case "H", "f":
            // Cursor Position
            let row = (params.first.map { $0 - 1 } ?? 0)
            let col = (params.dropFirst().first.map { $0 - 1 } ?? 0)
            buffer.setCursorPosition(x: col, y: row)
        case "J":
            // Erase Display
            let n = params.first ?? 0
            buffer.eraseInDisplay(mode: n)
        case "K":
            // Erase Line
            let n = params.first ?? 0
            buffer.eraseInLine(mode: n)
        case "m":
            // SGR - Select Graphic Rendition
            buffer.applyGraphicRendition(params)
        default:
            // Handle other CSI sequences if necessary
            Logger().info("Unhandled CSI Sequence: \(command)")
            break
        }
    }
}
