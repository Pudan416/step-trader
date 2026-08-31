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
        remixSeed: UInt64
    ) -> HarmonyPlan {
        let sleepProgress = unitValue(input.sleepProgress)
        let sortedDescriptors = instrumentDescriptors.sorted {
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

        let selectedByRole: [HarmonyRole: DayObjectsInstrumentDescriptor?] = [
            .drone: selectedDescriptor(
                for: template(for: .drone),
                from: sortedDescriptors,
                seed: remixSeed,
                excluding: []
            ),
            .primaryPad: primaryDescriptor,
            .secondaryPadOrKeys: secondaryDescriptor,
            .pianoOrKeysAccents: selectedDescriptor(
                for: template(for: .pianoOrKeysAccents),
                from: sortedDescriptors,
                seed: remixSeed,
                excluding: []
            ),
            .innerMotion: selectedDescriptor(
                for: template(for: .innerMotion),
                from: sortedDescriptors,
                seed: remixSeed,
                excluding: []
            )
        ]

        let roles = roleTemplates.compactMap { template -> HarmonyRolePlan? in
            guard let descriptor = selectedByRole[template.role] ?? nil else { return nil }
            let amount = activationAmount(
                for: template.role,
                sleepProgress: sleepProgress,
                start: template.activationStart,
                full: template.activationFull
            )
            return HarmonyRolePlan(
                role: template.role,
                instrumentID: descriptor.id,
                register: template.register,
                gain: template.targetGain * amount,
                attackSeconds: template.attackSeconds,
                releaseSeconds: template.releaseSeconds,
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
                    register: template.register
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
        register: ClosedRange<UInt8>
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
            let voicedNotes = AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: pitchClasses,
                previousNotes: previousNotes,
                register: register,
                voiceCount: voiceCount
            )
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
            attackSeconds: 2.8,
            releaseSeconds: 6.0,
            delaySend: 0.08,
            reverbSend: 0.62,
            activationStart: 0.00,
            activationFull: 0.20,
            crossfadeBars: 2
        ),
        RoleTemplate(
            role: .primaryPad,
            compatibleCategories: [.pad],
            preferredCategory: .pad,
            register: 48...72,
            targetGain: 0.48,
            attackSeconds: 2.2,
            releaseSeconds: 5.0,
            delaySend: 0.16,
            reverbSend: 0.54,
            activationStart: 0.20,
            activationFull: 0.55,
            crossfadeBars: 2
        ),
        RoleTemplate(
            role: .secondaryPadOrKeys,
            compatibleCategories: [.pad, .keys],
            preferredCategory: .keys,
            register: 55...79,
            targetGain: 0.34,
            attackSeconds: 1.6,
            releaseSeconds: 4.2,
            delaySend: 0.24,
            reverbSend: 0.48,
            activationStart: 0.58,
            activationFull: 0.88,
            crossfadeBars: 2
        ),
        RoleTemplate(
            role: .pianoOrKeysAccents,
            compatibleCategories: [.piano, .keys],
            preferredCategory: .piano,
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
            compatibleCategories: [.keys, .piano],
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
