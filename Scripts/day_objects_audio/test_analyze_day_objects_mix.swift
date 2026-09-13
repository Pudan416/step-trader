// Appended to the real CLI source by test_analyze_day_objects_mix.rb.
private var checkCount = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checkCount += 1
}
private func rejects(_ args: [String]) {
    do {
        _ = try parseArguments(["analyzer"] + args)
        preconditionFailure("Accepted invalid arguments: \(args)")
    } catch { checkCount += 1 }
}
private func report(issues: [DayObjectsMixIssue], lufs: Double = -22, peak: Double = -2,
                    loudnessPass: Bool, peakPass: Bool = true, finite: Bool = true) -> FileReport {
    let quality = DayObjectsMixQualityReport(integratedLUFS: lufs, truePeakDBTP: peak,
        maximumAbsoluteDCOffset: 0, crestFactorDB: 12, lowBandEnergyRatio: 0.2,
        midBandEnergyRatio: 0.7, highBandEnergyRatio: 0.1, layerAudibilityDB: [:],
        kickBassLowBandCorrelation: 0, clippedSampleRatio: 0, transientDensityPerSecond: 2,
        harmonyLeadMaskingScore: 0, happeningsLeadMaskingScore: 0, reverbTailEnergyRatio: 0,
        reverbTailEnergyRatioByRole: [:], issues: issues, suggestions: [])
    return FileReport(path: "in-memory", integratedLUFS: lufs, truePeakDBTP: peak, durationSeconds: 24,
        containsOnlyFiniteSamples: finite, passesIntegratedLoudness: loudnessPass,
        passesTruePeak: peakPass, quality: quality)
}

do {
    let defaults = try parseArguments(["analyzer", "/not-read.wav"]).4
    check(defaults.minimumIntegratedLUFS == -18 && defaults.maximumIntegratedLUFS == -16,
          "Default loudness limits changed")
    check(defaults.maximumTruePeakDBTP == -1, "Default peak limit changed")
    let overrides = try parseArguments(["analyzer", "--min-lufs", "-24", "--max-lufs", "-20",
                                       "--max-dbtp", "-0.2", "/not-read.wav"]).4
    check(overrides.minimumIntegratedLUFS == -24 && overrides.maximumIntegratedLUFS == -20,
          "Loudness overrides were not parsed")
    check(overrides.maximumTruePeakDBTP == -0.2, "Peak override was not parsed")
    for args in [["--min-lufs"], ["--min-lufs", "NaN", "mix"], ["--max-lufs", "infinity", "mix"],
                 ["--max-dbtp", "NaN", "mix"], ["--min-lufs", "-15", "mix"],
                 ["--stems-directory", "stems", "mix"], ["--active-stems", "lead", "mix"],
                 ["--stems-directory", "stems", "--active-stems", "lead,lead", "mix"],
                 ["--stems-directory", "stems", "--active-stems", "unknown", "mix"]] {
        rejects(args)
    }
    check(!report(issues: [.integratedLoudness], loudnessPass: false).passes,
          "Default loudness failure was ignored")
    check(report(issues: [.integratedLoudness], loudnessPass: true).passes,
          "An explicit accepted loudness override must replace the default issue gate")
    check(report(issues: [.truePeak], lufs: -17, peak: -0.5, loudnessPass: true).passes,
          "An explicit accepted peak override must replace the default issue gate")
    check(!report(issues: [], lufs: -17, loudnessPass: true, peakPass: false).passes,
          "A stricter command peak limit must still fail")
    check(!report(issues: [], loudnessPass: false).passes, "A stricter command loudness limit must still fail")
    for issue in DayObjectsMixIssue.allCases where issue != .integratedLoudness && issue != .truePeak {
        check(!report(issues: [.integratedLoudness, .truePeak, issue], loudnessPass: true).passes,
              "Overrides bypassed \(issue)")
    }
    check(!report(issues: [], loudnessPass: true, finite: false).passes, "Nonfinite samples must still fail")
    print("\(checkCount) CLI parser/acceptance checks passed; no audio files accessed")
} catch { preconditionFailure("Unexpected parser error: \(error)") }
