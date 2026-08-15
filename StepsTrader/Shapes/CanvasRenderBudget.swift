enum CanvasRenderBudget {
    static func snowflakeTrailLength(elementCount: Int, lowPowerMode: Bool) -> Int {
        let normalBudget: Int
        switch elementCount {
        case ...6:
            normalBudget = 10
        case ...12:
            normalBudget = 7
        default:
            normalBudget = 5
        }
        return lowPowerMode ? min(normalBudget, 5) : normalBudget
    }

    static func organicLayerCount(elementCount: Int, lowPowerMode: Bool) -> Int {
        let normalBudget: Int
        switch elementCount {
        case ...6:
            normalBudget = 4
        case ...12:
            normalBudget = 3
        default:
            normalBudget = 2
        }
        return lowPowerMode ? min(normalBudget, 2) : normalBudget
    }

    static func metaballGridResolution(sourceCount: Int, lowPowerMode: Bool) -> Int {
        let normalBudget: Int
        switch sourceCount {
        case ...5:
            normalBudget = 48
        case ...10:
            normalBudget = 42
        default:
            normalBudget = 36
        }
        return lowPowerMode ? min(normalBudget, 32) : normalBudget
    }
}
