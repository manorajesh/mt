//
//  TerminalRepresentable.swift
//  mt
//
//  Created by Mano Rajesh on 10/14/24.
//

import SwiftUI
import Cocoa

struct TerminalRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalView {
        let buffer = Buffer(rows: 24, cols: 80)
        let terminalView = TerminalView(buffer: buffer)
        let pty = Pty(buffer: buffer, view: terminalView, rows: 24, cols: 80)
        
        terminalView.setPty(pty)
        
        return terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
//        nsView.setNeedsDisplay(context.bounds)
    }
}
