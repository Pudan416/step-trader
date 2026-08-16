import Foundation

enum RichFigureAssignment {
    static func previewItems(
        elements: [CanvasElement],
        dayKey: String,
        shuffleNonce: Int
    ) -> [RichFigurePreviewItem] {
        let styles = make(elements: elements, dayKey: dayKey, shuffleNonce: shuffleNonce)
        let layouts = RichFigureLayout.make(elements: elements, styles: styles)
        return elements.compactMap { element in
            guard let style = styles[element.id], let layout = layouts[element.id] else { return nil }
            return RichFigurePreviewItem(source: element, style: style, layout: layout)
        }
    }

    static func make(
        elements: [CanvasElement],
        dayKey: String,
        shuffleNonce: Int
    ) -> [UUID: RichFigureStyleSpec] {
        let ordered = elements.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        let baseSeed = CanvasElement.makeSeed(
            optionId: "rich-lab-\(shuffleNonce)",
            dayKey: dayKey,
            index: ordered.count
        )
        var familyRNG = SeededRNG.derived(from: baseSeed, domain: "richFamily")
        var fillRNG = SeededRNG.derived(from: baseSeed, domain: "richFill")
        let families = repairedDeck(
            values: RichFigureFamily.allCases,
            count: ordered.count,
            using: &familyRNG
        )
        let fills = repairedDeck(
            values: RichFillKind.allCases,
            count: ordered.count,
            using: &fillRNG
        )

        let sizeOrdered = ordered.sorted {
            let lhs = Double($0.userSize ?? CGFloat($0.size))
            let rhs = Double($1.userSize ?? CGFloat($1.size))
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }
        let sizeRank = Dictionary(uniqueKeysWithValues:
            sizeOrdered.enumerated().map { ($0.element.id, $0.offset) }
        )

        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { index, element in
            let seed = element.shapeSeed ?? CanvasElement.stableSeed(for: element.id)
            var motion = SeededRNG.derived(from: seed ^ baseSeed, domain: "richMotion")
            return (element.id, RichFigureStyleSpec(
                family: families[index],
                fill: fills[index],
                primaryHex: element.hexColor,
                secondaryHex: element.hexColor2,
                geometrySeed: seed,
                animationPhase: motion.nextDouble(in: 0...(2 * .pi)),
                speedMultiplier: motion.nextDouble(in: 0.75...1.25),
                detailTier: detailTier(index: sizeRank[element.id] ?? index, count: ordered.count),
                glowIntensity: motion.nextDouble(in: 0.55...0.9),
                particleEligible: index % 3 == 0
            ))
        })
    }

    private static func repairedDeck<T: Equatable>(
        values: [T],
        count: Int,
        using rng: inout SeededRNG
    ) -> [T] {
        guard count > 0 else { return [] }

        var deck: [T] = []
        while deck.count < count {
            deck.append(contentsOf: values)
        }
        deck = Array(deck.prefix(count)).shuffled(using: &rng)

        guard deck.count > 1 else { return deck }
        for index in 1..<deck.count where deck[index] == deck[index - 1] {
            guard let replacement = deck.indices.dropFirst(index + 1)
                .first(where: { deck[$0] != deck[index] })
            else { continue }
            deck.swapAt(index, replacement)
        }
        return deck
    }

    private static func detailTier(index: Int, count: Int) -> RichFigureDetailTier {
        guard count > 1 else { return .medium }
        if index == 0 { return .accent }
        if index >= Int(ceil(Double(count) * 0.7)) { return .large }
        return .medium
    }
}
