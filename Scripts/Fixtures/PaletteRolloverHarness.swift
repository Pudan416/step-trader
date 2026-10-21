import Foundation

enum HappeningPalettePanel { case creator }
struct Animation {
    static func easeInOut(duration: Double) -> Self { Self() }
}
func withAnimation(_ animation: Animation, _ body: () -> Void) { body() }
struct Canvas { var dayKey: String }
enum Event { case dayBoundary }
final class LoadTask { func cancel() {} }

/*__STATE__*/

final class GalleryHarness {
    var showHappeningPalette = true
    var showEventExplorer = true
    var showsHappeningQuestions = false
    var showsHappeningIntroduction = false
    var happeningPalettePanel: HappeningPalettePanel? = .creator
    var loadTask: LoadTask? = LoadTask()
    var activeDayKey = "old"
    var dayCanvas = Canvas(dayKey: "old")
    var canvasLoaded = true
    var persistedDrafts = 0
    var cancelledInteractions = 0
    var dayBoundaryEvents = 0
    var loads = 0
    func persistHappeningQuestionDraft() { persistedDrafts += 1 }
    func finishHappeningIntroduction() { showsHappeningIntroduction = false }
    func cancelPaletteInteraction() { cancelledInteractions += 1 }
    func makeNewCanvas(dayKey: String) -> Canvas { Canvas(dayKey: dayKey) }
    func send(_ event: Event) { dayBoundaryEvents += 1 }
    func refreshHappeningPalette() {}
    func loadCanvas() { loads += 1 }

    /*__CLOSE__*/
    /*__ROLLOVER__*/
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: " + message); exit(1) }
}
let gallery = GalleryHarness()
if CommandLine.arguments[1] == "questions" {
    gallery.showEventExplorer = false
    gallery.showsHappeningQuestions = true
    gallery.showsHappeningIntroduction = true
}
gallery.rollOverCanvas(to: "new")
expect(!gallery.showHappeningPalette && !gallery.showEventExplorer,
       "the real palette overlay must not survive rollover")
expect(gallery.happeningPalettePanel == nil, "creator must close")
expect(!gallery.showsHappeningQuestions && !gallery.showsHappeningIntroduction,
       "question and introduction presentation must close")
expect(gallery.cancelledInteractions > 0, "old interactions must be cancelled")
expect(gallery.activeDayKey == "new" && gallery.dayCanvas.dayKey == "new",
       "the new day's canvas must load")
expect(gallery.dayBoundaryEvents == 1 && gallery.loads == 1,
       "rollover must preserve its canvas transition")
if CommandLine.arguments[1] == "questions" {
    expect(gallery.persistedDrafts == 1, "closing must retain the survey draft")
}
print("PASS: complete palette rollover " + CommandLine.arguments[1])
