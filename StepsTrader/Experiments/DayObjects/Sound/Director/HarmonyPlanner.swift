#if DEBUG || INTERNAL_BUILD
enum HarmonyPlanner {
    private struct RoleTemplate {
        let role: HarmonyRole
        let compatibleCategories: [DayObjectsInstrumentCategory]
        let preferredCategory: DayObjectsInstrumentCategory?
        let register: ClosedRange<UInt8>
        let targetGain: Double
        let attackSeconds: Double
        let releaseSeconds: Double
        let delaySend: Double
        let reverbSend: Double
        let activationStart: Double
        let activationFull: Double
        let crossfadeBars: Double
    }

    static func makePlan(
        input: NormalizedDayMusicInput,
        tonalWorld: TonalWorldPlan,
        instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld? = nil,
        mood: DayObjectsSoundMood = .moving,
        recipeIDs: [DayObjectsInstrumentID]? = nil,
        arrangement: DayObjectsArrangementProfile? = nil
    ) -> HarmonyPlan {
        let sleepProgress = unitValue(input.sleepProgress)
        let curated = instrumentDescriptors.filter { recipeIDs?.contains($0.id) ?? false }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        let worldDescriptors = soundWorld.map { world in
            instrumentDescriptors.filter { world.harmonyInstrumentIDs.contains($0.id.rawValue) }
        } ?? instrumentDescriptors
        let sortedDescriptors = worldDescriptors.sorted {
            $0.id.rawValue < $1.id.rawValue
        }
        let primaryDescriptor = selectedDescriptor(
            for: template(for: .primaryPad),
            from: sortedDescriptors,
            seed: remixSeed,
            excluding: []
        )
        let primaryID = primaryDescriptor?.id
        let secondaryTemplate = template(for: .secondaryPadOrKeys)
        let secondaryAlternatives = compatibleDescriptors(
            for: secondaryTemplate,
            from: sortedDescriptors
        ).filter { $0.id != primaryID }
        let secondaryDescriptor = selectedDescriptor(
            for: secondaryTemplate,
            from: sortedDescriptors,
            seed: remixSeed,
            excluding: secondaryAlternatives.isEmpty ? [] : Set([primaryID].compactMap { $0 })
        )

        var selectedByRole: [HarmonyRole: HarmonyInstrumentTarget?] = [
            .drone: selectedDescriptor(
                for: template(for: .drone),
                from: sortedDescriptors,
                seed: remixSeed,
                excluding: []
            ).map { .tonal($0.id) },
            .primaryPad: primaryDescriptor.map { .tonal($0.id) },
            .secondaryPadOrKeys: secondaryDescriptor.map { .tonal($0.id) },
            .pianoOrKeysAccents: .feltPiano,
            .innerMotion: selectedDescriptor(
                for: template(for: .innerMotion),
                from: sortedDescriptors,
                seed: remixSeed,
                excluding: []
            ).map { .tonal($0.id) }
        ]
        if !curated.isEmpty {
            var random = StableMusicRandom(seed: remixSeed, domain: .harmonyInstruments)
            let ordered = random.shuffled(curated)
            for (index, role) in HarmonyRole.allCases.enumerated() {
                selectedByRole[role] = .tonal(ordered[index % ordered.count].id)
            }
        }

        let roles = roleTemplates.compactMap { baseTemplate -> HarmonyRolePlan? in
            if let arrangement, !arrangement.harmonyRoles.contains(baseTemplate.role) { return nil }
            let template = processedTemplate(baseTemplate, soundWorld: soundWorld, mood: mood)
            guard let instrumentTarget = selectedByRole[template.role] ?? nil else { return nil }
            let amount = activationAmount(
                for: template.role,
                sleepProgress: sleepProgress,
                start: template.activationStart,
                full: template.activationFull
            )
            return HarmonyRolePlan(
                role: template.role,
                instrumentTarget: instrumentTarget,
                register: template.register,
                gain: template.targetGain * amount,
                attackSeconds: template.attackSeconds,
                releaseSeconds: template.releaseSeconds * (arrangement?.harmonyReleaseMultiplier ?? 1),
                delaySend: template.delaySend,
                reverbSend: template.reverbSend,
                activation: HarmonyActivationPlan(
                    startProgress: template.activationStart,
                    fullProgress: template.activationFull,
                    amount: amount
                ),
                chordSchedule: chordSchedule(
                    for: template.role,
                    tonalWorld: tonalWorld,
                    register: template.register,
                    soundWorld: soundWorld,
                    mood: mood
                ),
                crossfadeBars: template.crossfadeBars
            )
        }

        return HarmonyPlan(
            sleepProgress: sleepProgress,
            cycleBars: tonalWorld.cycleBars,
            chordCount: tonalWorld.progression.count,
            roles: roles
        )
    }

    private static func selectedDescriptor(
        for template: RoleTemplate,
        from descriptors: [DayObjectsInstrumentDescriptor],
        seed: UInt64,
        excluding excludedIDs: Set<DayObjectsInstrumentID>
    ) -> DayObjectsInstrumentDescriptor? {
        let compatible = compatibleDescriptors(for: template, from: descriptors)
            .filter { !excludedIDs.contains($0.id) }
        guard !compatible.isEmpty else { return nil }

        let preferred = template.preferredCategory.map { preferredCategory in
            compatible.filter { $0.category == preferredCategory }
        } ?? []
        let candidates = preferred.isEmpty ? compatible : preferred
        var random = StableMusicRandom(
            seed: seed,
            domain: MusicSeedDomain(
                "\(MusicSeedDomain.harmonyInstruments.rawValue).\(template.role.seedComponent)"
            )
        )
        return random.choice(from: candidates)
    }

    private static func compatibleDescriptors(
        for template: RoleTemplate,
        from descriptors: [DayObjectsInstrumentDescriptor]
    ) -> [DayObjectsInstrumentDescriptor] {
        descriptors.filter { template.compatibleCategories.contains($0.category) }
    }

    private static func activationAmount(
        for role: HarmonyRole,
        sleepProgress: Double,
        start: Double,
        full: Double
    ) -> Double {
        let smoothAmount = smoothActivation(sleepProgress, start: start, end: full)
        if role == .drone {
            return 0.18 + (0.82 * smoothAmount)
        }
        return smoothAmount
    }

    private static func chordSchedule(
        for role: HarmonyRole,
        tonalWorld: TonalWorldPlan,
        register: ClosedRange<UInt8>,
        soundWorld: DayObjectsSoundWorld?,
        mood: DayObjectsSoundMood
    ) -> [HarmonyChordScheduleEntry] {
        var startBar = 0
        var previousNotes: [UInt8]?
        let fullSchedule = tonalWorld.progression.enumerated().map { index, chord -> HarmonyChordScheduleEntry in
            let pitchClasses: [Int]
            let voiceCount: Int
            if role == .drone {
                pitchClasses = [chord.rootPitchClass, (chord.rootPitchClass + 7) % 12]
                voiceCount = 2
            } else {
                pitchClasses = chord.chordPitchClasses
                voiceCount = min(4, max(3, pitchClasses.count))
            }
            let voicedNotes: [UInt8]
            if let soundWorld {
                voicedNotes = AmbientVoiceLeading.nearestVoicing(
                    chordPitchClasses: pitchClasses, previousNotes: previousNotes,
                    world: soundWorld, mood: mood, register: register, chordIndex: index
                )
            } else {
                voicedNotes = AmbientVoiceLeading.nearestVoicing(
                    chordPitchClasses: pitchClasses,
                    previousNotes: previousNotes,
                    register: register,
                    voiceCount: voiceCount
                )
            }
            previousNotes = voicedNotes
            let entry = HarmonyChordScheduleEntry(
                chordIndex: index,
                startBar: startBar,
                durationBars: chord.durationBars,
                rootPitchClass: chord.rootPitchClass,
                chordPitchClasses: pitchClasses,
                safePassingPitchClasses: chord.safePassingPitchClasses,
                voicedMIDINotes: voicedNotes
            )
            startBar += chord.durationBars
            return entry
        }

        guard role == .pianoOrKeysAccents, let accent = fullSchedule.last else {
            return fullSchedule
        }
        return [HarmonyChordScheduleEntry(
            chordIndex: accent.chordIndex,
            startBar: accent.startBar,
            durationBars: 1,
            rootPitchClass: accent.rootPitchClass,
            chordPitchClasses: accent.chordPitchClasses,
            safePassingPitchClasses: accent.safePassingPitchClasses,
            voicedMIDINotes: accent.voicedMIDINotes
        )]
    }

    private static func template(for role: HarmonyRole) -> RoleTemplate {
        roleTemplates.first { $0.role == role } ?? roleTemplates[0]
    }

    private static func processedTemplate(
        _ template: RoleTemplate,
        soundWorld: DayObjectsSoundWorld?,
        mood: DayObjectsSoundMood
    ) -> RoleTemplate {
        guard let soundWorld else { return template }
        let grammar = DayObjectsHarmonyGrammar.for(world: soundWorld, mood: mood)
        let register: ClosedRange<UInt8>
        if template.role == .primaryPad {
            register = grammar.register
        } else {
            let shift = Int(grammar.register.lowerBound) - Int(AmbientVoiceLeading.ambientRegister.lowerBound)
            register = UInt8(Int(template.register.lowerBound) + shift)...UInt8(Int(template.register.upperBound) + shift)
        }
        let attackMultiplier: Double
        let releaseMultiplier: Double
        let delayMultiplier: Double
        let reverbMultiplier: Double
        switch soundWorld {
        case .feltAndWood, .livingField:
            attackMultiplier = 1.18
            releaseMultiplier = 1.22
            delayMultiplier = 0.62
            reverbMultiplier = 1.08
        case .metalAndCurrent, .electricDream:
            attackMultiplier = 0.72
            releaseMultiplier = 0.82
            delayMultiplier = 1.45
            reverbMultiplier = 1.12
        }
        return RoleTemplate(
            role: template.role,
            compatibleCategories: template.compatibleCategories,
            preferredCategory: template.preferredCategory,
            register: register,
            targetGain: template.targetGain,
            attackSeconds: template.attackSeconds * attackMultiplier,
            releaseSeconds: template.releaseSeconds * releaseMultiplier,
            delaySend: min(template.delaySend * delayMultiplier, 0.72),
            reverbSend: min(template.reverbSend * reverbMultiplier, 0.78),
            activationStart: template.activationStart,
            activationFull: template.activationFull,
            crossfadeBars: template.crossfadeBars
        )
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static let roleTemplates: [RoleTemplate] = [
        RoleTemplate(
            role: .drone,
            compatibleCategories: [.pad, .keys],
            preferredCategory: .pad,
            register: 36...55,
            targetGain: 0.24,
            attackSeconds: 4.0,
            releaseSeconds: 10.0,
            delaySend: 0.08,
            reverbSend: 0.62,
            activationStart: 0.00,
            activationFull: 0.20,
            crossfadeBars: 3
        ),
        RoleTemplate(
            role: .primaryPad,
            compatibleCategories: [.pad],
            preferredCategory: .pad,
            register: 48...72,
            targetGain: 0.48,
            attackSeconds: 3.2,
            releaseSeconds: 8.0,
            delaySend: 0.16,
            reverbSend: 0.54,
            activationStart: 0.20,
            activationFull: 0.55,
            crossfadeBars: 3
        ),
        RoleTemplate(
            role: .secondaryPadOrKeys,
            compatibleCategories: [.pad, .keys],
            preferredCategory: .keys,
            register: 55...79,
            targetGain: 0.34,
            attackSeconds: 2.4,
            releaseSeconds: 7.0,
            delaySend: 0.24,
            reverbSend: 0.48,
            activationStart: 0.58,
            activationFull: 0.88,
            crossfadeBars: 2.5
        ),
        RoleTemplate(
            role: .pianoOrKeysAccents,
            compatibleCategories: [],
            preferredCategory: nil,
            register: 60...84,
            targetGain: 0.16,
            attackSeconds: 0.04,
            releaseSeconds: 2.8,
            delaySend: 0.30,
            reverbSend: 0.42,
            activationStart: 0.72,
            activationFull: 1.00,
            crossfadeBars: 1
        ),
        RoleTemplate(
            role: .innerMotion,
            compatibleCategories: [.keys],
            preferredCategory: .keys,
            register: 55...79,
            targetGain: 0.12,
            attackSeconds: 0.12,
            releaseSeconds: 2.2,
            delaySend: 0.36,
            reverbSend: 0.38,
            activationStart: 0.82,
            activationFull: 1.00,
            crossfadeBars: 1
        )
    ]
}

private extension HarmonyRole {
    var seedComponent: String {
        switch self {
        case .drone: return "drone"
        case .primaryPad: return "primary-pad"
        case .secondaryPadOrKeys: return "secondary-pad-or-keys"
        case .pianoOrKeysAccents: return "piano-or-keys-accents"
        case .innerMotion: return "inner-motion"
        }
    }
}
#endif
