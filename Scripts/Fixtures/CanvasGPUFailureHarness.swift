import Foundation
import CoreGraphics

// Metal/UIKit boundaries only. The draw body below is copied from production.
class MTKView {
    var isPaused = false
    var presentsWithTransaction = false
    var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    var drawableSize = CGSize(width: 100, height: 100)
    var contentScaleFactor: CGFloat = 1
    var acquisitions = 0
    var currentDrawable: Drawable? { acquisitions += 1; return Drawable() }
    var currentRenderPassDescriptor: Int? { 1 }
}
final class Drawable { let texture = 1; func present() {} }
enum Status { case completed, error }
let MTLCommandBufferErrorDomain = "MTLCommandBufferErrorDomain"
enum MTLCommandBufferError: Int { case notPermitted = 7 }
struct ErrorOptions: OptionSet {
    let rawValue: Int
    static let encoderExecutionStatus = Self(rawValue: 1)
}
final class MTLCommandBufferDescriptor { var errorOptions: ErrorOptions = [] }
final class MTLCommandBuffer {
    var status = Status.completed
    var error: Error?
    var label: String?
    var handlers: [(MTLCommandBuffer) -> Void] = []
    func addCompletedHandler(_ handler: @escaping (MTLCommandBuffer) -> Void) { handlers.append(handler) }
    func commit() { handlers.forEach { $0(self) } }
    func waitUntilScheduled() {}
}
final class CommandQueue {
    var nextStatus = Status.completed
    var lastDescriptor: MTLCommandBufferDescriptor?
    func makeCommandBuffer(descriptor: MTLCommandBufferDescriptor) -> MTLCommandBuffer? {
        lastDescriptor = descriptor
        let buffer = MTLCommandBuffer()
        buffer.status = nextStatus
        return buffer
    }
}
enum Privacy { case `public` }
struct LogMessage: ExpressibleByStringInterpolation {
    init(stringLiteral: String) {}
    init(stringInterpolation: StringInterpolation) {}
    struct StringInterpolation: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ value: String) {}
        mutating func appendInterpolation<T>(_ value: T, privacy: Privacy) {}
    }
}
final class Logger { var failures = 0; func error(_ message: LogMessage) { failures += 1 } }
enum AppLogger { static let ui = Logger() }
final class DayObjectsDrawableView: MTKView {
    var palettePresentationIsActive = true
    var drawableMatchesBounds = true
    var paletteResizeHandoff = Handoff()
    func didPresentPaletteFrame(viewportSize: CGSize, cameraOrigin: CGPoint) {}
}
struct Handoff {
    var isPending = false
    func canPresent(viewportSize: CGSize, boundsSize: CGSize, cameraOrigin: CGPoint) -> Bool { true }
}
struct Presentation { var viewportSize = CGSize.zero; var cameraOrigin = CGPoint.zero }
enum Mode { case canvas, happeningPalette(Presentation) }
enum CATransaction { static func begin() {}; static func setDisableActions(_ value: Bool) {}; static func commit() {} }
struct Clock { var elapsedTime: TimeInterval = 0 }
final class Probe { func recordAttempt() {}; func recordResourceDrop() {} }
/*__STATE__*/

final class RendererHarness {
    let gpuFailureState = DayObjectsGPUFailureState()
    let commandQueue = CommandQueue()
    var presentationMode = Mode.canvas
    var clock = Clock()
    var performanceProbe: Probe? = Probe()
    var lastDisplayedTime: TimeInterval = 0
    var encodings = 0
    func encodeFrame(outputTexture: Int, outputPass: Int, drawableSize: CGSize,
                     pointToPixelScale: Float, elapsedTime: TimeInterval,
                     present: Drawable?) -> MTLCommandBuffer? {
        encodings += 1
        return makeTrackedCommandBuffer()
    }
    func configureAnimation(_ view: MTKView, elapsedTime: TimeInterval, requestsStaticFrame: Bool) {}
    /*__DRAW__*/
    /*__TRACKED__*/
}

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: " + message); exit(1) }
}
let renderer = RendererHarness(), view = MTKView()
renderer.draw(in: view)
expect(renderer.encodings == 1 && view.acquisitions == 1, "healthy renderer must still draw")
let background = renderer.makeTrackedCommandBuffer()!
background.status = .error
background.error = NSError(domain: MTLCommandBufferErrorDomain, code: 7)
background.commit()
expect(!renderer.gpuFailureState.hasFailed, "background rejection must allow future foreground frames")
let lateSuccess = renderer.makeTrackedCommandBuffer()!
let fault = renderer.makeTrackedCommandBuffer()!
fault.status = .error
fault.error = NSError(domain: "MTLCommandBufferErrorDomain", code: 3)
fault.commit() // Actual production completion handler receives the GPU fault.
lateSuccess.commit()
expect(renderer.gpuFailureState.hasFailed, "a late success must not clear a prior failure")
expect(AppLogger.ui.failures == 1, "first fault must be diagnosed once")
fault.commit()
expect(AppLogger.ui.failures == 1, "repeated failure must not flood diagnostics")
for _ in 0..<100 { renderer.draw(in: view) }
expect(view.acquisitions == 1, "failed renderer must not acquire more drawables")
expect(renderer.encodings == 1, "failed renderer must not encode or submit another frame")
expect(view.isPaused, "failed renderer must pause its display link")
expect(renderer.makeTrackedCommandBuffer() == nil, "failed queue must also reject offscreen submissions")
expect(renderer.commandQueue.lastDescriptor?.errorOptions == .encoderExecutionStatus,
       "internal builds must retain encoder execution diagnostics")
print("PASS: production Canvas draw stops after GPU failure")
