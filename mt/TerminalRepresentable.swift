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
        let view = TerminalView()
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Update the view when needed (e.g., change text)
    }
}
