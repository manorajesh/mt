//
//  AnsiParser.swift
//  mt
//
//  Created by Mano Rajesh on 10/17/24.
//

import Foundation

// MARK: - Parser States

enum ParserState {
    case ground
    case escape
    case csiEntry
    case csiParameter
    case csiIntermediate
}

// MARK: - ANSI Escape Code Parser

class AnsiParser {
    // Current state of the parser
    private var state: ParserState = .ground
    
    // Parameters collected during parsing
    private var parameters: [Int] = []
    private var intermediates: [Character] = []
    private var finalChar: Character?
    
    // Reference to the terminal buffer and cursor
    private var buffer: Buffer
    
    init(buffer: Buffer) {
        self.buffer = buffer
    }
    
    // Parse a single character
    func parse(character: Character) {
        print(character.debugDescription)
        switch state {
        case .ground:
            handleGroundState(character)
        case .escape:
            handleEscapeState(character)
        case .csiEntry:
            handleCsiEntryState(character)
        case .csiParameter:
            handleCsiParameterState(character)
        case .csiIntermediate:
            handleCsiIntermediateState(character)
        }
    }
    
    // Reset the parser to the ground state
    private func resetParser() {
        state = .ground
        parameters.removeAll()
        intermediates.removeAll()
        finalChar = nil
    }
}

// MARK: - State Handlers

extension AnsiParser {
    // Handle characters in the ground state
    private func handleGroundState(_ character: Character) {
        if character == "\u{1B}" { // ESC
            state = .escape
        } else if character == "\u{07}" { // Bell character
            // Handle bell (e.g., play a sound)
        } else if character == "\n" {
//            buffer.addLineFeed()
            buffer.addNewLine()
        } else if character == "\r" {
            buffer.addCarriageReturn()
        } else if character == "\t" {
            // Handle tab character (advance cursor position)
            buffer.advanceCursorToNextTabStop()
        } else if character.isASCII {
            // Printable ASCII characters
            buffer.appendChar(character)
        } else {
            // Ignore other characters
        }
    }
    
    // Handle characters after an ESC character
    private func handleEscapeState(_ character: Character) {
        if character == "[" {
            state = .csiEntry
        } else {
            // Handle other escape sequences or ignore
            state = .ground
        }
    }
    
    // Handle CSI entry state
    private func handleCsiEntryState(_ character: Character) {
        if character.isNumber {
            parameters.append(Int(String(character)) ?? 0)
            state = .csiParameter
        } else if character == ";" {
            // Parameter separator
            parameters.append(0)
            state = .csiParameter
        } else if character >= " " && character <= "/" {
            intermediates.append(character)
            state = .csiIntermediate
        } else if character >= "@" && character <= "~" {
            finalChar = character
            dispatchCSI()
            resetParser()
        } else {
            state = .ground
        }
    }
    
    // Handle CSI parameter state
    private func handleCsiParameterState(_ character: Character) {
        if character.isNumber {
            if parameters.isEmpty {
                parameters.append(0)
            }
            let lastIndex = parameters.count - 1
            parameters[lastIndex] = parameters[lastIndex] * 10 + (Int(String(character)) ?? 0)
        } else if character == ";" {
            parameters.append(0)
        } else if character >= " " && character <= "/" {
            intermediates.append(character)
            state = .csiIntermediate
        } else if character >= "@" && character <= "~" {
            finalChar = character
            dispatchCSI()
            resetParser()
        } else {
            state = .ground
        }
    }
    
    // Handle CSI intermediate state
    private func handleCsiIntermediateState(_ character: Character) {
        if character >= " " && character <= "/" {
            intermediates.append(character)
        } else if character >= "@" && character <= "~" {
            finalChar = character
            dispatchCSI()
            resetParser()
        } else {
            state = .ground
        }
    }
}

// MARK: - CSI Sequence Dispatcher

extension AnsiParser {
    // Dispatch CSI sequences based on the final character
    private func dispatchCSI() {
        guard let finalChar = finalChar else { return }
        
        switch finalChar {
        case "A":
            // Cursor Up
            let n = parameters.first ?? 1
            buffer.moveCursorUp(n)
        case "B":
            // Cursor Down
            let n = parameters.first ?? 1
            buffer.moveCursorDown(n)
        case "C":
            // Cursor Forward
            let n = parameters.first ?? 1
            buffer.moveCursorForward(n)
        case "D":
            // Cursor Backward
            let n = parameters.first ?? 1
            buffer.moveCursorBackward(n)
        case "H", "f":
            // Cursor Position
            let row = (parameters.count > 0) ? parameters[0] - 1 : 0
            let col = (parameters.count > 1) ? parameters[1] - 1 : 0
            buffer.setCursorPosition(x: col, y: row)
        case "J":
            // Erase in Display
            let mode = parameters.first ?? 0
            buffer.eraseInDisplay(mode: mode)
        case "K":
            // Erase in Line
            let mode = parameters.first ?? 0
            buffer.eraseInLine(mode: mode)
        case "m":
            // Select Graphic Rendition (SGR)
            buffer.applyGraphicRendition(parameters)
        default:
            // Handle other CSI sequences if needed
            break
        }
    }
}


