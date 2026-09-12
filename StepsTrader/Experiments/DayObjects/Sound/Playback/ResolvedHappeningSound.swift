struct ResolvedHappeningSound: Equatable, Sendable {
    let recipeID: HappeningSoundRecipeID
    let resourceName: String
    let sourceRootMIDI: UInt8?
    let targetMIDI: UInt8?
    let playbackRate: Double
    let resonantFilterHz: Double?
}
