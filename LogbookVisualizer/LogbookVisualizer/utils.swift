// LogbookVisualizer
// ↳ utils.swift
//
// Created by:
// Alexander Nikitin - @sqeezelemon

import Foundation
import CoreGraphics

extension CGPoint {
    init (_ vec: SIMD2<Float>) {
        self.init()
        self.x = CGFloat(vec.x)
        self.y = CGFloat(vec.y)
    }
}

extension CGColor {
    // Intended to be used with hex literals like 0xFFFFFF
    static func fromHex(hex: Int, alpha: CGFloat = 1) -> CGColor {
        return .init(red:   CGFloat((hex & 0xFF0000) >> 16) / 255,
                     green: CGFloat((hex & 0xFF00) >> 8) / 255,
                     blue:  CGFloat( hex & 0xFF) / 255,
                     alpha: alpha)
    }
}
