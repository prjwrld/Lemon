import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns the 22 photo adjustments into a Core Image filter chain.
/// Used by the editor's live preview and when saving, so both look the same.
nonisolated enum PhotoFilter {
    static func apply(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        let a = adjustments
        let extent = input.extent
        var image = input

        // Light
        if a.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = image; f.ev = Float(a.exposure); image = f.outputImage ?? image
        }
        if a.gamma != 0 {
            let f = CIFilter.gammaAdjust(); f.inputImage = image; f.power = Float(pow(2, -a.gamma)); image = f.outputImage ?? image
        }
        if a.shadows != 0 || a.highlights < 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.shadowAmount = Float(a.shadows)
            f.highlightAmount = Float(1 + min(a.highlights, 0))
            f.radius = 0
            image = f.outputImage ?? image
        }
        // Whites, blacks, positive highlights, fade and dehaze bend the tone curve.
        if a.whites != 0 || a.blacks != 0 || a.highlights > 0 || a.fade != 0 || a.dehaze != 0 {
            let f = CIFilter.toneCurve()
            f.inputImage = image
            let lift = max(a.blacks, 0) * 0.10 + max(a.fade, 0) * 0.14 - max(a.dehaze, 0) * 0.04
            f.point0 = CGPoint(x: 0, y: clamp(lift))
            f.point1 = CGPoint(x: 0.25, y: clamp(0.25 + a.blacks * 0.06 + a.fade * 0.04 - a.dehaze * 0.03))
            f.point2 = CGPoint(x: 0.5, y: 0.5)
            f.point3 = CGPoint(x: 0.75, y: clamp(0.75 + max(a.highlights, 0) * 0.08 + a.whites * 0.05))
            f.point4 = CGPoint(x: 1, y: clamp(1 + min(a.whites, 0) * 0.12 - max(a.fade, 0) * 0.06))
            image = f.outputImage ?? image
        }
        let saturation = 1 + a.saturation - max(a.fade, 0) * 0.2 + max(a.dehaze, 0) * 0.15
        let contrast = 1 + a.contrast * 0.5 + a.dehaze * 0.15
        if a.brightness != 0 || contrast != 1 || saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = Float(a.brightness * 0.25)
            f.contrast = Float(contrast)
            f.saturation = Float(max(saturation, 0))
            image = f.outputImage ?? image
        }

        // Color
        if a.temperature != 0 || a.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - a.temperature * 2500, y: -a.tint * 60)
            image = f.outputImage ?? image
        }
        if a.vibrance != 0 {
            let f = CIFilter.vibrance(); f.inputImage = image; f.amount = Float(a.vibrance); image = f.outputImage ?? image
        }
        if a.hue != 0 {
            let f = CIFilter.hueAdjust(); f.inputImage = image; f.angle = Float(a.hue * .pi); image = f.outputImage ?? image
        }

        // Detail
        if a.noiseReduction > 0 {
            let f = CIFilter.noiseReduction()
            f.inputImage = image; f.noiseLevel = Float(a.noiseReduction * 0.06); f.sharpness = 0.4
            image = f.outputImage ?? image
        }
        if a.clarity != 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image; f.radius = Float(max(extent.width, extent.height) / 80); f.intensity = Float(a.clarity * 0.6)
            image = f.outputImage ?? image
        }
        if a.texture != 0 {
            let f = CIFilter.unsharpMask(); f.inputImage = image; f.radius = 2.5; f.intensity = Float(a.texture * 0.9)
            image = f.outputImage ?? image
        }
        if a.sharpness > 0 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = image; f.sharpness = Float(a.sharpness); f.radius = 1.7
            image = f.outputImage ?? image
        }
        if a.blur > 0 {
            let f = CIFilter.gaussianBlur()
            f.inputImage = image.clampedToExtent(); f.radius = Float(a.blur * max(extent.width, extent.height) / 60)
            image = (f.outputImage ?? image).cropped(to: extent)
        }

        // Effects
        if a.vignette > 0 {
            let f = CIFilter.vignette(); f.inputImage = image; f.intensity = Float(a.vignette * 1.6); f.radius = 2
            image = f.outputImage ?? image
        }
        if a.grain > 0 {
            image = addGrain(to: image, amount: a.grain, extent: extent)
        }
        return image.cropped(to: extent)
    }

    private static func addGrain(to image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        // Grey, see-through noise, blended softly over the photo.
        let grey = CIFilter.colorMatrix()
        grey.inputImage = noise
        let v = CIVector(x: 0, y: 1, z: 0, w: 0)
        grey.rVector = v; grey.gVector = v; grey.bVector = v
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount * 0.35))
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = grey.outputImage?.cropped(to: extent)
        blend.backgroundImage = image
        return blend.outputImage ?? image
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// Shared, reusable Core Image context (making one is slow).
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
}
