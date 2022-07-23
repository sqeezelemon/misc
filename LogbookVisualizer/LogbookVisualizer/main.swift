// LogbookVisualizer
// ↳ main.swift
//
// Created by:
// Alexander Nikitin - @sqeezelemon

import Foundation
import Accelerate
import simd
import CoreGraphics
import Cocoa

// MARK: Settings
// Settings for the visualization

// Canvas settings
let height:   Float = 1800 * 2
let width:    Float = 3600 * 2
let hpadding: Float = 100  * 2
let wpadding: Float = 100  * 2
let multiplier: Float = 1  * 2

// Inputs
let airportsUrl: URL = URL(fileURLWithPath: "/files/airports.json")
let routesUrl:   URL = URL(fileURLWithPath: "/files/routes.csv")
let outputUrl:   URL = URL(fileURLWithPath: "/files/LBViz-\(UUID()).png")

// Colors
let minHex: Int = 0xF0F3BD
let maxHex: Int = 0x00B4CB
let bgColor: CGColor = .black //.fromHex(hex: 0x191919)

// MARK: Airport Loading
// Loading of airport data

// 1. Read the data

var airportDict = [String : SIMD2<Float>]()
do {
    struct Airport: Codable {
        var lat, lon: Float
    }
    let data = try Data(contentsOf: airportsUrl, options: .alwaysMapped) // Mapping for memory efficiency
    let tempDict: [String : Airport] = try JSONDecoder().decode([String : Airport].self, from: data)
    airportDict = tempDict.mapValues { value in
        return .init(x: value.lon, y: value.lat)
    }
} catch {
    print("AIRPORT LOADER ERROR")
    print(error)
    exit(1)
}

// 2. Transform data for current context
// By how much the coordinate space is stretched
let hmult = height / 180
let wmult = width / 360
// Offset
let hmove = hpadding + height/2
let wmove = wpadding + width/2
// Actual transformations
for (key, _) in airportDict {
    airportDict[key]! *= .init(wmult, hmult)
    airportDict[key]! += .init(wmove, hmove)
    
}

// MARK: Route Loading
// Loads all the routes

struct WeightedRoute {
    var dep, arr: String
    var weight: Float
}

var routes = [WeightedRoute]()

do {
    let data = try Data(contentsOf: routesUrl, options: .alwaysMapped) // Mapping for memory efficiency
    var lines = String(data: data, encoding: .utf8)!.components(separatedBy: "\n")
    lines.removeFirst()
    for line in lines {
        let comps = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
        guard comps.count > 2,
              let wfloat = Float(comps[2])
        else { continue }
        routes.append(WeightedRoute.init(dep: comps[0], arr: comps[1], weight: wfloat))
    }
} catch {
    print("ROUTE LOADER ERROR")
    print(error)
    exit(1)
}

// MARK: Airport weighting

var aptWeights: [String : Float] = [:]
for route in routes {
    aptWeights[route.dep] = (aptWeights[route.dep] ?? 0) + route.weight
    aptWeights[route.arr] = (aptWeights[route.arr] ?? 0) + route.weight
}

// MARK: Drawing

// 0. Utilities

let minAptw: Float = aptWeights.min { $0.value < $1.value }!.value
let maxAptw: Float = aptWeights.max { $0.value < $1.value }!.value
let difAptw: Float = maxAptw - minAptw

// RGB arrays
let minComps: [CGFloat] = [CGFloat((minHex & 0xFF0000)>>16)/255,
                           CGFloat((minHex & 0xFF00)>>8)/255,
                           CGFloat(minHex & 0xFF)/255]
let maxComps: [CGFloat] = [CGFloat((maxHex & 0xFF0000)>>16)/255,
                           CGFloat((maxHex & 0xFF00)>>8)/255,
                           CGFloat(maxHex & 0xFF)/255]
let difComps: [CGFloat] = [maxComps[0]-minComps[0],
                           maxComps[1]-minComps[1],
                           maxComps[2]-minComps[2]]

func aptColor(w: Float) -> CGColor {
    let pos: CGFloat = pow(CGFloat((w - minAptw)/difAptw), 0.2)
    let color = CGColor(
        red:   minComps[0] + difComps[0]*pos,
        green: minComps[1] + difComps[1]*pos,
        blue:  minComps[2] + difComps[2]*pos,
        alpha: 1)
    return color
}

// 1. Initialize CGContext
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(data: nil, width: Int(width)+Int(wpadding)*2, height: Int(height)+Int(hpadding)*2, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
    print("CGContext creation error")
    exit(1)
}
context.setBlendMode(CGBlendMode.normal)
context.setAlpha(1)

// 2. Draw background
context.addRect(CGRect(x: 0, y: 0, width: context.width, height: context.height))
context.setFillColor(bgColor)
context.fillPath()

// 3. Drawing routes
context.setAlpha(0.2)
for route in routes {
    guard let dep = airportDict[route.dep],
          let arr = airportDict[route.arr]
    else {
        print("\(route.dep) ✈︎ \(route.arr) - DEP or ARR invalid")
        continue
    }
    var trip = arr - dep
    
    let angle: Float = 0.698132 // ~40 degrees in Radians
    let baseWidth: Float = 1
    let width: Float = baseWidth * exp(10*route.weight) * multiplier
    
    // Modify length so that the projection of the anchor vector would be
    // right in the middle of the DEP->ARR vector
    trip *= sqrtf(tan(angle)*tan(angle) + cos(angle)*cos(angle))/2
    var anchor = SIMD2<Float>( trip.x * cos(angle) - trip.y * sin(angle) ,
                               trip.x * sin(angle) + trip.y * cos(angle) )
    anchor += dep
    
    // Drawing
    context.move(to: CGPoint(dep))
    context.setLineWidth(CGFloat(width))
    context.addQuadCurve(to: CGPoint(arr), control: CGPoint(anchor))
    
    // For simple fills
    // context.setStrokeColor(color)
    // context.strokePath()
    
    // Complex gradient fill
    context.replacePathWithStrokedPath()
    context.clip()
    guard let gradient = CGGradient(colorsSpace: nil, colors: [aptColor(w: aptWeights[route.dep]!), aptColor(w: aptWeights[route.arr]!)] as CFArray, locations: [0,1])
    else { continue }
    context.drawLinearGradient(gradient, start: CGPoint(dep), end: CGPoint(arr), options: .drawsBeforeStartLocation)
    context.resetClip()
}

// 4. Drawing airports

context.setBlendMode(CGBlendMode.normal)
context.setAlpha(0.8)
context.setLineWidth(0.2*CGFloat(multiplier))
context.setStrokeColor(bgColor)

let aptRenderQueue: [String] = aptWeights.keys.sorted {
    aptWeights[$0]! > aptWeights[$1]!
}

for icao in aptRenderQueue {
    let weight = aptWeights[icao]!
    guard let apt = airportDict[icao]
    else {
        print("\(icao) - Airport not found")
        continue
    }
    
    let baseRadius: CGFloat = 2
    let maxRadius:  CGFloat = 30
    let radius: CGFloat = (baseRadius + maxRadius * pow(CGFloat((weight - minAptw)/difAptw), 1.5)) * CGFloat(multiplier)
    let color: CGColor = aptColor(w: weight)
    
    let rect = CGRect(x: CGFloat(apt.x)-radius, y: CGFloat(apt.y)-radius, width: radius*2, height: radius*2)
    context.addEllipse(in: rect)
    context.setFillColor(color)
    context.fillPath()
    
    context.addEllipse(in: rect)
    context.strokePath()
}

// MARK: Rendering

guard let cgImg = context.makeImage() else {
    print("Error creating an image")
    exit(1)
}
let bitmapRep = NSBitmapImageRep(cgImage: cgImg)
guard let imgData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Error rendering into data")
    exit(1)
}
try imgData.write(to: outputUrl)

// MARK: Misc stuff
