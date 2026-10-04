import Foundation
import simd

/// The day's art direction, frozen independently of actor count and catalog edits.
struct NativeAtlasDailyStyle: Codable, Equatable {
    enum Family: String, Codable, CaseIterable {
        case circles, blobs, squares, clovers, flowers, rays
    }

    let family: Family
    let presetID: String
    let materialID: MetalShapeMaterial
    var palette: [SIMD3<Float>]
    let shape: MetalShapeGenomeUniforms
    var material: MetalShapeMaterialUniforms
    let orientation: Float
    /// Missing in saved atlas-2 artwork; preserve its original color policy.
    var sharesPaletteOrder: Bool? = nil
    /// Missing in historical artwork; opt in without changing its frozen policy.
    var softGradients: Bool? = nil
    /// Opt-in actor diversity and perceptible idle motion; archives keep their policy.
    var livingVariation: Bool? = nil

    /// A is opt-in: nil retains the exact archived appearance and motion.
    var appearancePolicyVersion: Int? = nil
    /// Missing in archives: their shared contour and narrow rotation stay exact.
    var silhouettePolicyVersion: Int? = nil
    var usesIndividualSilhouettes: Bool { silhouettePolicyVersion == 1 }
    /// Only new/current editable artwork adopts the complete reference fills.
    var materialPolicyVersion: Int? = nil
    var materialOrder: [MetalShapeMaterial]? = nil
    var usesReferenceMaterials: Bool { materialPolicyVersion == 1 }
    var neighboringPigments: [SIMD3<Float>]? = nil
    var neighboringPaletteCategories: [ModernPaletteCategory]? = nil
    var usesApprovedAppearance: Bool { appearancePolicyVersion == 1 }

    static func referenceMaterials(for preset: MetalShapePreset) -> [MetalShapeMaterial] {
        MetalShapeMaterial.allCases.filter {
            $0 != .proceduralLight && $0 != .proceduralFlow
                && preset.compatibility.allowed.contains($0)
        }
    }

    mutating func freezeReferenceMaterials(seed: UInt64) {
        guard !usesReferenceMaterials,
              let preset = MetalShapeGenomeCatalog.presets.first(where: { $0.id == presetID }) else { return }
        var materials = family == .rays ? [.directionalBlur] : Self.referenceMaterials(for: preset)
        var rng = SeededRNG(seed: seed ^ 0x5245_4646_494C_4C53)
        if materials.count > 1 {
            for index in stride(from: materials.count - 1, through: 1, by: -1) {
                materials.swapAt(index, rng.nextInt(in: 0...index))
            }
            // Supported blur appears even on a sparse two-event day, rather
            // than being hidden behind eight later slots or another Remix.
            if let blur = materials.firstIndex(of: .directionalBlur) { materials.swapAt(1, blur) }
        }
        materialOrder = materials
        materialPolicyVersion = 1
    }

    /// Freeze numerical pigments only at creation, current-day upgrade or edit.
    mutating func freezeApprovedAppearance(background: DayObjectMeshGradientStyle,
                                          categories: Set<ModernPaletteCategory>, seed: UInt64) {
        appearancePolicyVersion = 1
        neighboringPaletteCategories = categories.sorted { $0.rawValue < $1.rawValue }
        let anchors = palette.isEmpty ? [SIMD3<Float>(repeating: 0.5)] : palette
        guard background.isNoir != true else { neighboringPigments = anchors; return }
        let labs = anchors.map { DayObjectRGB(linearRGB: $0).perceptualOKLab }
        func distance(_ rgb: SIMD3<Float>) -> Float {
            let lab = DayObjectRGB(linearRGB: rgb).perceptualOKLab
            return labs.map { simd_length(lab - $0) }.min() ?? 1
        }
        var rankedPalettes: [(code: String, colors: [SIMD3<Float>], score: Float)] = []
        for item in ModernPaletteCatalog.palettes(matching: categories)
            where !item.categories.contains(.noir) {
            let colors: [SIMD3<Float>] = item.hexes.map { DayObjectRGB(hex: $0).linearRGB }
            var score: Float = 0
            for color in colors { score += distance(color) }
            score /= Float(max(1, colors.count))
            rankedPalettes.append((code: item.code, colors: colors, score: score))
        }
        rankedPalettes.sort {
            $0.score == $1.score ? $0.code < $1.code : $0.score < $1.score
        }
        let neighbors = rankedPalettes.prefix(3)
        var candidates = anchors
        for neighbor in neighbors {
            let colors = neighbor.colors
            candidates += colors.filter { rgb in
                let lab = DayObjectRGB(linearRGB: rgb).perceptualOKLab
                let chroma = simd_length(SIMD2(lab.y, lab.z))
                return labs.contains { anchor in
                    let anchorChroma = simd_length(SIMD2(anchor.y, anchor.z))
                    let hueAgreement = anchorChroma < 0.025 || chroma < 0.025
                        || simd_dot(SIMD2(lab.y, lab.z), SIMD2(anchor.y, anchor.z)) / max(chroma * anchorChroma, 0.000001) > 0.70
                    return hueAgreement && simd_length(lab - anchor) <= 0.20
                        && chroma <= max(0.10, anchorChroma + 0.055)
                }
            }
        }
        // Farthest-point ordering gives sparse days distinct pigments while
        // retaining the selected day's related hue range.
        let maximumPoolCount = min(10, candidates.count)
        var pool: [SIMD3<Float>] = [anchors[Int(seed % UInt64(anchors.count))]]
        while pool.count < maximumPoolCount {
            var bestIndex: Int?
            var bestDistance: Float = 0.012
            for index in candidates.indices {
                let lab = DayObjectRGB(linearRGB: candidates[index]).perceptualOKLab
                var nearest: Float = .infinity
                for pigment in pool {
                    let selected = DayObjectRGB(linearRGB: pigment).perceptualOKLab
                    nearest = min(nearest, simd_length(lab - selected))
                }
                if nearest > bestDistance {
                    bestIndex = index
                    bestDistance = nearest
                }
            }
            guard let bestIndex else { break }
            pool.append(candidates.remove(at: bestIndex))
        }
        neighboringPigments = pool
    }

    /// Generate once into the actor payload, independently of the legacy RNG.
    /// A daily family retains its contour kind, square mode and flower petal count.
    func actorGeometry(seed: UInt64, slot: Int) -> MetalShapeGenomeUniforms {
        guard usesIndividualSilhouettes else { return shape }
        let index = min(max(slot, 0), 9)
        let profiles: [Float] = [-1, 1, -0.5, 0.5, 0, -0.8, 0.8, -0.3, 0.3, 0.1]
        let profile = profiles[index]
        var rng = SeededRNG(seed: seed ^ 0x5349_4C48_4F55_4554)
        func random(_ lower: Double, _ upper: Double) -> Float {
            Float(rng.nextDouble(in: lower...upper))
        }
        var formula = shape.superformula
        var h0 = shape.harmonic0, h1 = shape.harmonic1
        var anisotropy = shape.anisotropyOffset, transform = shape.transform
        var metadata = shape.metadata
        switch family {
        case .circles:
            let stretches: [Float] = [0, 0.14, -0.10, 0.07, -0.16, 0.11, -0.04, 0.16, -0.07, 0.04]
            let stretch = stretches[index] + random(-0.008, 0.008)
            anisotropy.x = 1 + stretch
            anisotropy.y = 1 - stretch
        case .blobs:
            // soft-drift's catalog genome is static: changing a frame seed alone
            // cannot change it. Vary its real superformula and harmonic fields.
            formula.y = min(max(formula.y + random(-0.28, 0.28), 1.7), 2.5)
            formula.z = min(max(formula.z + profile * 0.35 + random(-0.12, 0.12), 2.0), 3.0)
            formula.w = min(max(formula.w - profile * 0.25 + random(-0.12, 0.12), 1.25), 2.1)
            h0 = SIMD4(3, random(0.035, 0.11), random(0, 2 * Double.pi), 1)
            h1 = SIMD4(2, random(0.025, 0.065), random(0, 2 * Double.pi), 1)
            let stretch = profile * 0.10 + random(-0.015, 0.015)
            anisotropy.x = 0.98 + stretch
            anisotropy.y = 1.02 - stretch
            anisotropy.z = random(-0.055, 0.055)
            anisotropy.w = random(-0.045, 0.045)
            let genome = MetalShapeGenome(morphology: .softRadial, superformula: formula,
                harmonics: [.init(frequency: 3, amplitude: h0.y, phase: h0.z),
                            .init(frequency: 2, amplitude: h1.y, phase: h1.z)],
                anisotropy: SIMD2(anisotropy.x, anisotropy.y),
                centerOffset: SIMD2(anisotropy.z, anisotropy.w), rotation: transform.x)
            transform.y = MetalShapeGenomeFrame.normalization(genome)
            metadata.w = 2
        case .squares:
            let stretch = profile * 0.075 + random(-0.012, 0.012)
            anisotropy.x = 1 + stretch
            anisotropy.y = 1 - stretch
            if shape.sourceKind == 4 {
                transform.z = min(max(shape.transform.z + profile * 0.045, 0.62), 0.72)
                transform.w = min(max(shape.transform.w + random(-0.55, 0.55), 2.4), 4.0)
                formula.y = transform.z
                formula.z = transform.w
            }
        case .clovers:
            transform.z = min(max(shape.transform.z + profile * 0.05, 0.46), 0.58)
            transform.w = min(max(shape.transform.w + random(-0.075, 0.075), 0.54), 0.74)
            formula.y = transform.z
            formula.z = transform.w
            let stretch = profile * 0.08 + random(-0.012, 0.012)
            anisotropy.x = 1 + stretch
            anisotropy.y = 1 - stretch
        case .flowers:
            if shape.sourceKind == 2 {
                // Snowflake packs harmonic count/amplitudes in these fields,
                // unlike Windflower's valley/tip parameters. Keep its frozen
                // folds and normalized contour; vary the ellipse proportions.
                let stretch = profile * 0.06
                anisotropy.x = 1 + stretch
                anisotropy.y = 1 - stretch
                break
            }
            formula.y = min(max(shape.superformula.y + profile * 0.04, 0.30), 0.45)
            formula.z = min(max(shape.superformula.z + random(-0.08, 0.08), 0.16), 0.38)
            formula.w = min(max(shape.superformula.w + random(-0.08, 0.08), 0.50), 0.78)
            metadata.y = UInt32(truncatingIfNeeded: seed)
            let stretch = profile * 0.06
            anisotropy.x = 1 + stretch
            anisotropy.y = 1 - stretch
        case .rays:
            // The diffuse beam branch owns its silhouette; keep its carrier.
            return shape
        }
        return .init(superformula: formula, harmonic0: h0, harmonic1: h1,
                     harmonic2: shape.harmonic2, anisotropyOffset: anisotropy,
                     transform: transform, metadata: metadata, reserved: shape.reserved)
    }

    func actorRotation(seed: UInt64, slot: Int, legacyRotation: Float) -> Float {
        guard usesIndividualSilhouettes else { return legacyRotation }
        // First five slots cover a whole turn; ten fill the gaps. Symmetric
        // families spread within one symmetry sector rather than aliasing axes.
        let phases: [Float] = [0, 0.4, 0.8, 0.2, 0.6, 0.1, 0.5, 0.9, 0.3, 0.7]
        let period: Float
        switch family {
        case .circles: period = .pi
        case .squares, .clovers: period = .pi / 2
        case .flowers: period = 2 * .pi / Float(max(3, shape.metadata.z))
        default: period = 2 * .pi
        }
        var rng = SeededRNG(seed: seed ^ 0x4F52_4945_4E54_4154)
        let jitter = Float(rng.nextDouble(in: -0.02...0.02))
        return orientation + (phases[min(max(slot, 0), 9)] + jitter) * period
    }

    func actorMaterialID(slot: Int) -> MetalShapeMaterial {
        guard usesApprovedAppearance else { return materialID }
        if usesReferenceMaterials, let materials = materialOrder, !materials.isEmpty {
            return materials[max(0, slot) % materials.count]
        }
        if family == .rays { return .directionalBlur }
        let requested: MetalShapeMaterial = [.solid, .solid, .radialTwo, .contour][max(0, slot) % 4]
        let preset = MetalShapeGenomeCatalog.presets.first { $0.id == presetID }
        return preset?.compatibility.allowed.contains(requested) == true ? requested : .sideLight
    }

    /// Shuffle each calendar block of six. Repair only the first two entries,
    /// leaving the last entry stable so the preceding block needs no recursion.
    static func family(dayKey: String) -> Family {
        let datePart = String(dayKey.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let ordinal: Int
        if let date = formatter.date(from: datePart) {
            ordinal = Int(floor(date.timeIntervalSince1970 / 86400))
        } else {
            ordinal = Int(CanvasElement.makeSeed(optionId: "daily-family", dayKey: dayKey, index: 0) % 100_000)
        }
        let block = Int(floor(Double(ordinal) / 6))
        let offset = ordinal - block * 6
        func shuffled(_ cycle: Int) -> [Family] {
            var values = Family.allCases
            var rng = SeededRNG(seed: CanvasElement.makeSeed(optionId: "daily-family-cycle", dayKey: String(cycle), index: 0))
            for i in stride(from: values.count - 1, through: 1, by: -1) {
                values.swapAt(i, rng.nextInt(in: 0...i))
            }
            return values
        }
        var values = shuffled(block)
        if values[0] == shuffled(block - 1).last { values.swapAt(0, 1) }
        return values[offset]
    }

    /// Explicit Remix consumes the entire seed, independent of the calendar.
    /// Keep one coherent family and guarantee a change from the saved family.
    static func remixFamily(seedKey: String, excluding previous: Family?) -> Family {
        let candidates = Family.allCases.filter { $0 != previous }
        var rng = SeededRNG(seed: CanvasElement.makeSeed(
            optionId: "remix-family", dayKey: seedKey, index: 0
        ))
        return candidates[rng.nextInt(in: 0...(candidates.count - 1))]
    }

    /// Called explicitly by today's unlocked Canvas adoption, never decoding.
    func adoptingLivingVariation(seed: UInt64) -> Self {
        var result = self
        if family == .rays, livingVariation != true,
           let beam = MetalShapeGenomeCatalog.presets.first(where: { $0.id == "legacy.rounded-triangle" }) {
            // The existing directional-blur branch opens this contour into a
            // diffuse directed beam. Fresh uniforms cannot inherit a light flag.
            let frame = MetalShapeGenomeFrame.make(preset: beam, material: .directionalBlur, seed: seed)
            result = Self(family: family, presetID: beam.id, materialID: .directionalBlur,
                          palette: palette, shape: frame.geometry, material: frame.material,
                          orientation: orientation, sharesPaletteOrder: true,
                          softGradients: true, livingVariation: true)
        }
        result.livingVariation = true
        return result
    }

    func recolored(_ source: MetalShapeMaterialUniforms, seed: UInt64, slot: Int = 0, colorVariant: Int? = nil) -> MetalShapeMaterialUniforms {
        if usesApprovedAppearance { return approvedPigment(source, seed: seed, slot: slot, colorVariant: colorVariant) }
        // Frozen background colors are already linear RGB, matching the shader.
        let colors = palette.isEmpty ? [SIMD3<Float>(repeating: 0.5)] : palette
        // Keep the same dominant hues across the day's figures. Picker variants
        // include an identity hash even before a reroll, so neither that hash
        // nor an actor seed may rotate the shared palette.
        let ordered = sharesPaletteOrder == true
        let offset = ordered ? 0 : Int(seed % UInt64(colors.count))
        let meanLightness = colors.reduce(Float(0)) {
            $0 + DayObjectRGB(linearRGB: $1).perceptualOKLab.x
        } / Float(colors.count)
        let separation: Float = meanLightness > 0.6 ? -0.07 : 0.07
        var rng = SeededRNG(seed: seed ^ 0x5049_474D_454E_5453)
        let living = livingVariation == true
        let variation = ordered ? Float(rng.nextDouble(in: living ? -0.055...0.055 : -0.018...0.018))
            : (Float((seed >> 12) % 7) / 6 - 0.5) * 0.036
        if softGradients == true {
            // Bias the whole ordered gradient toward a member of the day's
            // palette. Absolute palette/seed input prevents cumulative tint
            // when the current day is adopted again or its colors are edited.
            let emphasis = living ? Float(rng.nextDouble(in: 0.12...0.32)) : 0
            let anchor = colors[living ? rng.nextInt(in: 0...(colors.count - 1)) : 0]
            let chroma = living ? Float(rng.nextDouble(in: 0.68...0.88)) : 0.75
            let pigments = colors.map { $0 + (anchor - $0) * emphasis }
            let perceptualColors = pigments.map { DayObjectRGB(linearRGB: $0).perceptualOKLab }
            let minimum = perceptualColors.map(\.x).min() ?? meanLightness
            let maximum = perceptualColors.map(\.x).max() ?? meanLightness
            let midpoint = (minimum + maximum) * 0.5
            let lightnessScale = min(1, 0.19 / max(maximum - minimum, 0.000_001))
            // Keep palette context, while moving extreme palettes toward a
            // moderate field. All stops share the actor's small seed variation.
            let center = min(max(meanLightness * 0.70 + 0.60 * 0.30, 0.32), 0.80)
            func softColor(_ index: Int) -> SIMD4<Float> {
                let paletteIndex = (offset + index) % colors.count
                let target = center + (perceptualColors[paletteIndex].x - midpoint) * lightnessScale + variation
                let rgb = DayObjectRGB(linearRGB: pigments[paletteIndex])
                    .fittingPerceptualLightness(to: target, chromaFraction: chroma).linearRGB
                return SIMD4(rgb, 1)
            }
            var metadata = source.metadata
            if source.materialIndex == 6 {
                metadata.y |= 0x8000_0000
            }
            var firstColor = softColor(0)
            if living, family == .rays, source.materialIndex == 3, source.metadata.y == 0 {
                // The diffuse beam's mode 0 uses only color0. A dark shared
                // endpoint vanishes at its soft edge, so give this light role
                // a muted tone from the brighter half of the same pigments.
                let ranked = pigments.indices.sorted {
                    let left = perceptualColors[$0].x, right = perceptualColors[$1].x
                    return left == right ? $0 < $1 : left > right
                }
                var beamRNG = SeededRNG(seed: seed ^ 0x4245_414D_544F_4E45)
                let count = max(1, (ranked.count + 1) / 2)
                let selected = ranked[beamRNG.nextInt(in: 0...(count - 1))]
                let target = min(max(0.77 + variation * 0.9, 0.72), 0.82)
                firstColor = SIMD4(DayObjectRGB(linearRGB: pigments[selected])
                    .fittingPerceptualLightness(to: target, chromaFraction: min(chroma, 0.75)).linearRGB, 1)
            }
            return .init(color0: firstColor, color1: softColor(1), color2: source.materialIndex == 1 ? softColor(1) : softColor(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: metadata)
        }
        func color(_ index: Int) -> SIMD4<Float> {
            let rgb = DayObjectRGB(linearRGB: colors[(offset + index) % colors.count])
                .shiftingPerceptualLightness(by: separation + variation).linearRGB
            return SIMD4(rgb, 1)
        }
        return .init(color0: color(0), color1: color(1), color2: source.materialIndex == 1 ? color(1) : color(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: source.metadata)
    }

    func actorSize(base: Float, slot: Int, seed: UInt64, legacyScale: Float) -> Float {
        if usesApprovedAppearance {
            let sizes: [Float] = [0.41, 0.15, 0.27, 0.22, 0.35, 0.19, 0.38, 0.16, 0.29, 0.24]
            let size = sizes[min(max(slot, 0), sizes.count - 1)]
            return family == .rays ? max(0.30, size * 1.80) : size
        }
        guard livingVariation == true else { return base * legacyScale }
        // Stable slots alternate large, small and medium figures immediately,
        // even on a sparse day. Event additions/removals never rescale survivors.
        let tiers: [Float] = [1.18, 0.70, 0.96, 0.65, 1.10, 0.82, 1.25, 0.72, 1.02, 0.90]
        var rng = SeededRNG(seed: seed ^ 0x5349_5A45_5449_4552)
        let tier = tiers[min(max(slot, 0), tiers.count - 1)]
        let scale = min(max(tier + Float(rng.nextDouble(in: -0.03...0.03)), 0.65), 1.25)
        return base * scale
    }

    private func approvedPigment(_ source: MetalShapeMaterialUniforms, seed: UInt64, slot: Int, colorVariant: Int?) -> MetalShapeMaterialUniforms {
        let colors = neighboringPigments.flatMap { $0.isEmpty ? nil : $0 }
            ?? (palette.isEmpty ? [SIMD3<Float>(repeating: 0.5)] : palette)
        let role = max(0, slot) % 4
        let slotPigment = colors[max(0, slot) % colors.count]
        // Picker identities carry a variant even before a reroll. Keep the
        // slot's dominant pigment and let those identities tint it gently.
        let pigment: DayObjectRGB
        if let colorVariant {
            let tintIndex = Int(UInt(bitPattern: colorVariant) % UInt(colors.count))
            var tintRNG = SeededRNG(seed: UInt64(truncatingIfNeeded: colorVariant) ^ 0x5449_4E54_524F_4C45)
            let tint = Float(tintRNG.nextDouble(in: 0.10...0.18))
            pigment = DayObjectRGB(linearRGB: slotPigment + (colors[tintIndex] - slotPigment) * tint)
        } else { pigment = DayObjectRGB(linearRGB: slotPigment) }
        let mean = palette.reduce(Float(0)) { $0 + DayObjectRGB(linearRGB: $1).perceptualOKLab.x } / Float(max(1, palette.count))
        var rng = SeededRNG(seed: seed ^ 0x5049_474D_454E_5453)
        let variation = Float(rng.nextDouble(in: -0.012...0.012))
        let referenceGradient = usesReferenceMaterials && [1, 5, 8, 9, 10].contains(source.materialIndex)
        let isTwo = source.materialIndex == 4 || (source.materialIndex == 3 && source.metadata.y == 2) || referenceGradient
        let contour = source.materialIndex == 2 || (usesReferenceMaterials && source.materialIndex == 8)
        let lightness: Float = contour ? (mean > 0.55 ? 0.49 : 0.76)
            : isTwo ? (mean > 0.78 ? 0.66 : 0.78)
            : family == .rays ? (role == 1 ? 0.70 : 0.79)
            : min(max(pigment.perceptualOKLab.x + (mean > 0.65 ? -0.035 : 0.07), 0.48), 0.84)
        let first = SIMD4(pigment.fittingPerceptualLightness(to: lightness + variation, chromaFraction: 0.92).linearRGB, 1)
        if usesReferenceMaterials {
            func relatedColor(offset: Int, lightnessShift: Float) -> SIMD4<Float> {
                let neighbor = colors[(max(0, slot) + offset) % colors.count]
                let mixed = pigment.linearRGB + (neighbor - pigment.linearRGB) * 0.16
                return SIMD4(DayObjectRGB(linearRGB: mixed).fittingPerceptualLightness(
                    to: min(max(lightness + lightnessShift + variation, 0.42), 0.88),
                    chromaFraction: 0.78).linearRGB, 1)
            }
            let second = isTwo ? relatedColor(offset: 1, lightnessShift: 0.055) : first
            let third = source.materialIndex == 5 ? relatedColor(offset: 2, lightnessShift: -0.035) : second
            var metadata = source.metadata
            if source.materialIndex == 8 || source.materialIndex == 10 {
                metadata.y |= MetalShapeMaterialUniforms.referenceMaterialFlag
            }
            return .init(color0: first, color1: second, color2: third,
                         params0: source.params0, params1: source.params1, params2: source.params2,
                         params3: source.params3, metadata: metadata)
        }
        let second = isTwo ? SIMD4(pigment.fittingPerceptualLightness(to: lightness + 0.08 + variation, chromaFraction: 0.65).linearRGB, 1) : first
        return .init(color0: first, color1: second, color2: second,
                     params0: source.params0, params1: source.params1, params2: source.params2,
                     params3: source.params3, metadata: source.metadata)
    }

    func variedMaterial(_ source: MetalShapeMaterialUniforms, seed: UInt64) -> MetalShapeMaterialUniforms {
        guard livingVariation == true else { return source }
        var rng = SeededRNG(seed: seed ^ 0x4D41_5445_5249_414C)
        var params1 = source.params1, params2 = source.params2
        // Directed beams keep their local axis; the frozen actor rotation owns
        // their aim. Other fills can share a material with different light paths.
        if source.materialIndex != 3 {
            let angle = Float(rng.nextDouble(in: -0.22...0.22))
            let direction = source.direction
            params1.x = direction.x * cos(angle) - direction.y * sin(angle)
            params1.y = direction.x * sin(angle) + direction.y * cos(angle)
        }
        if source.materialIndex == 6 {
            for index in 0..<4 {
                params2[index] = min(max(params2[index] + Float(rng.nextDouble(in: -0.10...0.10)), 0), 1)
            }
        }
        return .init(color0: source.color0, color1: source.color1, color2: source.color2,
                     params0: source.params0, params1: params1, params2: params2,
                     params3: source.params3, metadata: source.metadata)
    }
}
