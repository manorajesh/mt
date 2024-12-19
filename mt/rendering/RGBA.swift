//
//  RGBA.swift
//  mt
//
//  Created by Mano Rajesh on 12/17/24.
//

import simd

// Define color constants using SIMD4<Float>
struct Colors {
    static let black   = SIMD4<Float>(0, 0, 0, 1)
    static let white   = SIMD4<Float>(1, 1, 1, 1)
    static let red     = SIMD4<Float>(1, 0, 0, 1)
    static let green   = SIMD4<Float>(0, 1, 0, 1)
    static let blue    = SIMD4<Float>(0, 0, 1, 1)
    static let yellow  = SIMD4<Float>(1, 1, 0, 1)
    static let magenta = SIMD4<Float>(1, 0, 1, 1)
    static let cyan    = SIMD4<Float>(0, 1, 1, 1)
    static let clear   = SIMD4<Float>(0, 0, 0, 0)
}
