//
//  RGBA.swift
//  mt
//
//  Created by Mano Rajesh on 12/17/24.
//

import Foundation
import simd

struct RGBA {
    let rgba: SIMD4<Float>
    
    // Predefined color constants
    static let black   = RGBA(r: 0, g: 0, b: 0, a: 1)
    static let white   = RGBA(r: 1, g: 1, b: 1, a: 1)
    static let red     = RGBA(r: 1, g: 0, b: 0, a: 1)
    static let green   = RGBA(r: 0, g: 1, b: 0, a: 1)
    static let blue    = RGBA(r: 0, g: 0, b: 1, a: 1)
    static let yellow  = RGBA(r: 1, g: 1, b: 0, a: 1)
    static let magenta = RGBA(r: 1, g: 0, b: 1, a: 1)
    static let cyan    = RGBA(r: 0, g: 1, b: 1, a: 1)
    static let clear   = RGBA(r: 0, g: 0, b: 0, a: 0)
    
    // Custom initializer
    init(r: Float, g: Float, b: Float, a: Float) {
        self.rgba = SIMD4(r, g, b, a)
    }
}
