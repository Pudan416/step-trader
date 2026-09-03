#if DEBUG || INTERNAL_BUILD
enum HappeningMusicPlanner {
    static func makePlans(
        input: NormalizedDayMusicInput,
        tonalWorld: TonalWorldPlan,
        remixSeed: UInt64
    ) -> [HappeningMusicPlan] {
        let recipes = recipePermutation(remixSeed: remixSeed)
        return zip(input.happeningIDs.prefix(10), recipes).map { happeningID, recipe in
            makePlan(
                happeningID: happeningID,
                tonalWorld: tonalWorld,
                recipe: recipe,
                remixSeed: remixSeed
            )
        }
    }

    private static func makePlan(
        happeningID: String,
        tonalWorld: TonalWorldPlan,
        recipe: HappeningSoundRecipe,
        remixSeed: UInt64
    ) -> HappeningMusicPlan {
        var identityRandom = StableMusicRandom(
            seed: remixSeed,
            domain: .happeningIdentity(stableID: happeningID)
        )
        let family = soundFamily(for: recipe.family)
        let legacyFamilyIndex = identityRandom.nextInt(
            upperBound: HappeningSoundFamily.allCases.count
        ) ?? 0
        _ = identityRandom.nextInt(upperBound: legacyFamilyIndex == 3 ? 6 : 3)
        let legacyMotifLength = 1 + (identityRandom.nextInt(upperBound: 3) ?? 0)
        _ = Array(identityRandom.shuffled(tonalWorld.mode.scaleIntervals).prefix(legacyMotifLength))
        let gain = 0.62 + (0.18 * identityRandom.nextUnitDouble())
        let birthGain = min(0.95, gain + 0.10 + (0.08 * identityRandom.nextUnitDouble()))
        _ = identityRandom.nextInt(
            upperBound: legacyFamilyIndex == 0 || legacyFamilyIndex == 2 ? 3 : 2
        )
        let pan = -0.85 + (1.70 * identityRandom.nextUnitDouble())

        var scheduleRandom = StableMusicRandom(
            seed: remixSeed,
            domain: .happeningSchedule(stableID: happeningID)
        )
        let scheduleSeed = scheduleRandom.nextUInt64()
        let alignmentRank = scheduleRandom.nextUInt64()
        let magnitude = scheduleRandom.bernoulli(probability: 0.5) ? 0.25 : 0.50
        let floatingOffset = scheduleRandom.bernoulli(probability: 0.5) ? magnitude : -magnitude

        return HappeningMusicPlan(
            happeningID: happeningID,
            family: family,
            recipeID: recipe.id,
            pan: pan,
            gain: gain,
            birthGain: birthGain,
            attackSeconds: recipe.attackSeconds,
            releaseSeconds: recipe.releaseSeconds,
            delaySend: recipe.delayMix,
            reverbSend: recipe.reverbMix,
            recurrence: HappeningRecurrencePlan(
                scheduleSeed: scheduleSeed,
                alignmentRank: alignmentRank,
                floatingOffsetBeats: floatingOffset
            )
        )
    }

    private static func recipePermutation(remixSeed: UInt64) -> [HappeningSoundRecipe] {
        var random = StableMusicRandom(
            seed: remixSeed,
            domain: .happeningIdentity(stableID: "recipe-permutation")
        )
        let familyOrder = random.shuffled(HappeningRecipeFamily.allCases)
        var remaining = familyOrder.map { family in
            (family: family, recipes: random.shuffled(
                HappeningSoundCatalog.recipes.filter { $0.family == family }
            ))
        }
        var result: [HappeningSoundRecipe] = []
        result.reserveCapacity(HappeningSoundCatalog.recipes.count)
        while result.count < HappeningSoundCatalog.recipes.count {
            var appended = false
            for index in remaining.indices where !remaining[index].recipes.isEmpty {
                result.append(remaining[index].recipes.removeFirst())
                appended = true
            }
            if !appended { break }
        }
        return result
    }

    private static func soundFamily(for family: HappeningRecipeFamily) -> HappeningSoundFamily {
        switch family {
        case .synthPluck: return .pluck
        case .acousticMallet: return .mallet
        case .acousticBell: return .bell
        case .softOneShot: return .softOneShot
        case .texture: return .texture
        }
    }

}
#endif
