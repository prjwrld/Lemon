import CoreGraphics
import Foundation

/// A colour that can be saved and passed to background work.
nonisolated struct RGBA: Codable, Sendable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1
    static let black = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 1, g: 1, b: 1)
    static let lemon = RGBA(r: 1, g: 0.86, b: 0.12)
    static let red = RGBA(r: 1, g: 0.23, b: 0.19)
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// The 22 photo adjustments. Every value runs from −1 to 1 (0 = unchanged), except
/// exposure (−3…3 EV) and the ones that only go up (noise reduction, blur, vignette, grain: 0…1).
nonisolated struct PhotoAdjustments: Codable, Sendable, Equatable {
    // Light
    var exposure = 0.0, brightness = 0.0, contrast = 0.0, highlights = 0.0
    var shadows = 0.0, whites = 0.0, blacks = 0.0, gamma = 0.0
    // Color
    var temperature = 0.0, tint = 0.0, saturation = 0.0, vibrance = 0.0, hue = 0.0
    // Detail
    var clarity = 0.0, texture = 0.0, sharpness = 0.0, noiseReduction = 0.0, blur = 0.0
    // Effects
    var dehaze = 0.0, fade = 0.0, vignette = 0.0, grain = 0.0

    var isUnchanged: Bool { self == PhotoAdjustments() }
}

/// One drawing on a picture. Points are 0…1 across the picture, from the top-left.
nonisolated struct AnnotationMark: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable, CaseIterable { case pen, highlighter, arrow, rectangle, ellipse, text }
    var id = UUID()
    var kind: Kind
    var points: [CGPoint]
    var color: RGBA
    /// Line width as a share of the picture's width.
    var lineWidth: Double = 0.006
    var text = ""
}

nonisolated enum BackgroundChoice: Codable, Sendable, Equatable {
    case transparent
    case color(RGBA)
    case blur
}

nonisolated enum RedactStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case black, pixelate, blur
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

nonisolated struct CollageLayout: Codable, Sendable, Equatable {
    var columns = 2
    /// Gap between pictures as a share of the collage width.
    var spacing = 0.015
    var background = RGBA.white
    /// Fill each cell (cropping) instead of fitting the whole picture.
    var fill = true
}

/// One page in the PDF organiser: which original page, turned by how much.
nonisolated struct PageEdit: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var sourceIndex: Int
    var rotation = 0   // degrees, multiples of 90
}

nonisolated struct MetadataEdit: Codable, Sendable, Equatable {
    var removeAll = false
    var removeLocation = false
    var title: String?
    var author: String?
    var copyright: String?
    var comment: String?
}

nonisolated struct TimeRange: Codable, Sendable, Equatable, Hashable {
    var start: Double
    var end: Double
    var length: Double { max(0, end - start) }
}

/// What an editor hands to the work, or `.none` for tools without an editor.
nonisolated enum ToolOptions: Sendable {
    case none
    case crop(CGRect)                         // 0…1, top-left origin
    case photo(PhotoAdjustments)
    case annotate([AnnotationMark])
    case background(BackgroundChoice)
    case redact([CGRect], RedactStyle)        // 0…1 rectangles
    case collage(CollageLayout)
    case trim(TimeRange)
    case speed(Double)
    case snapshots(Int)
    case split([Double])                      // cut points in seconds
    case bleep([TimeRange])
    case pages([PageEdit])
    case metadata(MetadataEdit)
}
