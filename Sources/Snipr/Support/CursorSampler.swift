import AppKit

/// One sampled cursor position, relative to sampling start.
struct CursorSample: Equatable, Sendable {
    let time: TimeInterval
    let location: CGPoint   // global Cocoa coordinates (bottom-left origin)
}

/// Polls the global mouse location at 60 Hz while a recording runs. Polling
/// `NSEvent.mouseLocation` needs no permissions, unlike event taps.
@MainActor
final class CursorSampler {
    private(set) var samples: [CursorSample] = []
    // nonisolated(unsafe) only so the nonisolated deinit can invalidate it;
    // all other access stays on the main actor, and deinit has exclusive
    // access to stored properties.
    private nonisolated(unsafe) var timer: Timer?
    private var startedAt: TimeInterval = 0

    var isSampling: Bool { timer != nil }

    deinit {
        // RunLoop.main retains the timer independently of this object; without
        // this, releasing the sampler mid-run would leave it firing forever.
        timer?.invalidate()
    }

    func start() {
        discard()
        samples.reserveCapacity(60 * 60 * 5)   // 5 minutes without realloc
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.samples.append(CursorSample(
                    time: ProcessInfo.processInfo.systemUptime - self.startedAt,
                    location: NSEvent.mouseLocation
                ))
            }
        }
        // .common so sampling continues while menus/drags run their tracking loops.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() -> [CursorSample] {
        timer?.invalidate()
        timer = nil
        return samples
    }

    func discard() {
        timer?.invalidate()
        timer = nil
        samples = []
    }
}

/// Pure math for turning sampled global points into video-pixel keyframes.
enum CursorPath {
    /// Global Cocoa point (bottom-left origin) → video pixels (top-left
    /// origin, matching the flipped compositing layer space).
    static func mapToVideoPixels(_ point: CGPoint, region: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x - region.minX) * scale,
            y: (region.maxY - point.y) * scale
        )
    }

    /// Every `stride`-th sample plus the final one, so cubic interpolation
    /// has anchors at both ends. `stride <= 1` returns the input unchanged.
    static func thinned(_ samples: [CursorSample], stride strideLength: Int) -> [CursorSample] {
        guard strideLength > 1, samples.count > 2 else { return samples }
        var kept = Swift.stride(from: 0, to: samples.count, by: strideLength).map { samples[$0] }
        if let last = samples.last, kept.last != last {
            kept.append(last)
        }
        return kept
    }
}
