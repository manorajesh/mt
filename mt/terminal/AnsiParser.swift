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
    private var paramBuffer = [UInt8]()
    private var params: [Int] = []
    private var intermediateBytes = [UInt8]()
    private var finalByte: UInt8 = 0
    private var oscBytes = [UInt8]()
    
    private let buffer: Buffer
    
    init(buffer: Buffer) {
        self.buffer = buffer
    }
    
    func parse(byte: UInt8) {
        switch state {
        case .normal:
            if byte == 0x1B { // ESC
                state = .escape
            } else if byte == 0x08 { // BS
                buffer.handleBackspace()
            } else if byte == 0x0A { // LF
                buffer.addNewLine()
            } else if byte == 0x0D { // CR
                buffer.addCarriageReturn()
            } else if byte == 0x09 { // TAB
                buffer.advanceCursorToNextTabStop()
            } else {
                buffer.appendChar(byte)
            }
            
        case .escape:
            if byte == 0x5B { // [
                state = .csi
                params = []
                paramBuffer.removeAll(keepingCapacity: true)
                intermediateBytes.removeAll(keepingCapacity: true)
            } else if byte == 0x5D { // ]
                state = .osc
                oscBytes.removeAll(keepingCapacity: true)
            } else if byte == 0x50 || byte == 0x5F || byte == 0x5E || byte == 0x58 { // P, _, ^, X
                state = .sosPmApc
            } else if byte == 0x28 || byte == 0x29 { // (, )
                state = .normal
            } else {
                state = .normal
            }
            
        case .csi:
            if byte >= 0x30 && byte <= 0x39 { // 0-9
                paramBuffer.append(byte)
            } else if byte == 0x3B { // ;
                if let param = parseNumber(from: paramBuffer) {
                    params.append(param)
                }
                paramBuffer.removeAll(keepingCapacity: true)
            } else if byte >= 0x20 && byte <= 0x2F {
                intermediateBytes.append(byte)
            } else if byte >= 0x40 && byte <= 0x7E {
                if !paramBuffer.isEmpty {
                    if let param = parseNumber(from: paramBuffer) {
                        params.append(param)
                    }
                    paramBuffer.removeAll(keepingCapacity: true)
                }
                finalByte = byte
                handleCsiSequence(params: params, command: finalByte)
                state = .normal
            }
            
        case .osc:
            if byte == 0x07 || (byte == 0x1B && !oscBytes.isEmpty && oscBytes.last == 0x5C) {
                state = .normal
                oscBytes.removeAll(keepingCapacity: true)
            } else {
                oscBytes.append(byte)
            }
            
        case .sosPmApc:
            if byte == 0x07 || (byte == 0x1B && !oscBytes.isEmpty && oscBytes.last == 0x5C) {
                state = .normal
            }
        }
    }
    
    private func parseNumber(from bytes: [UInt8]) -> Int? {
        var result = 0
        for byte in bytes {
            result = result * 10 + Int(byte - 0x30)
        }
        return result
    }
    
    private func handleCsiSequence(params: [Int], command: UInt8) {
        switch command {
        case 0x41: // A - Cursor Up
            let n = params.first ?? 1
            buffer.moveCursorUp(n)
            
        case 0x42: // B - Cursor Down
            let n = params.first ?? 1
            buffer.moveCursorDown(n)
            
        case 0x43: // C - Cursor Forward
            let n = params.first ?? 1
            buffer.moveCursorForward(n)
            
        case 0x44: // D - Cursor Backward
            let n = params.first ?? 1
            buffer.moveCursorBackward(n)
            
        case 0x48, 0x66: // H, f - Cursor Position
            let row = (params.first.map { $0 - 1 } ?? 0)
            let col = (params.dropFirst().first.map { $0 - 1 } ?? 0)
            buffer.setCursorPosition(x: col, y: row)
            
        case 0x4A: // J - Erase Display
            let n = params.first ?? 0
            buffer.eraseInDisplay(mode: n)
            
        case 0x4B: // K - Erase Line
            let n = params.first ?? 0
            buffer.eraseInLine(mode: n)
            
        case 0x6D: // m - SGR Select Graphic Rendition
            buffer.applyGraphicRendition(params)
            
        default:
            Logger().info("Unhandled CSI Sequence: \(command)")
        }
    }
}
