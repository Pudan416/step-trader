import Foundation
import simd

@_alignment(16)
struct MetalShapeMaterialUniforms: Codable, Equatable, Sendable {
    static let metalStride = 128

    let color0: SIMD4<Float>
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let params0: SIMD4<Float>
    let params1: SIMD4<Float>
    let params2: SIMD4<Float>
    let params3: SIMD4<Float>
    let metadata: SIMD4<UInt32>

    var materialIndex: UInt32 { metadata.x }
    var direction: SIMD2<Float> { SIMD2(params1.x, params1.y) }

    /// Replace retired Canvas fills at render time, keeping saved parameters
    /// readable and retaining the figure's frozen colors and geometry.
    var primaryCanvasMaterial: Self {
        var safeMetadata = metadata
        switch materialIndex {
        case 8: safeMetadata.x = 2 // Dense nested contour -> simple outline.
        case 10: safeMetadata.x = 4 // Sunset -> two-color radial gradient.
        default: return self
        }
        return Self(color0: color0, color1: color1, color2: color2, params0: params0, params1: params1, params2: params2, params3: params3, metadata: safeMetadata)
    }

    /// Rotate the frozen palette, retaining one/two-color material relationships.
    func withColorVariant(_ variant: Int) -> Self {
        let angle = Float(variant % 97 + 1) * 2.3999632
        let axis = SIMD3<Float>(repeating: 1 / sqrt(3))
        func rotate(_ c: SIMD4<Float>) -> SIMD4<Float> {
            let rgb = SIMD3(c.x, c.y, c.z)
            let value = simd_clamp(rgb * cos(angle) + simd_cross(axis, rgb) * sin(angle) + axis * simd_dot(axis, rgb) * (1 - cos(angle)), SIMD3(repeating: 0), SIMD3(repeating: 1))
            return SIMD4(value, c.w)
        }
        return Self(color0: rotate(color0), color1: rotate(color1), color2: rotate(color2), params0: params0, params1: params1, params2: params2, params3: params3, metadata: metadata)
    }

    var colorsAreFiniteAndBounded: Bool {
        [color0, color1, color2].allSatisfy { color in
            color.x.isFinite && color.y.isFinite && color.z.isFinite && color.w.isFinite
                && (0...1).contains(color.x) && (0...1).contains(color.y)
                && (0...1).contains(color.z) && (0...1).contains(color.w)
        }
    }
}
