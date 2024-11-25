//
//  ContentView.swift
//  mt
//
//  Created by Mano Rajesh on 10/14/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MetalTextView(text: "A")
                        .background(Color.black)
                        .frame(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    }
}

#Preview {
    ContentView()
}
