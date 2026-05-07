#!/usr/bin/env swift -package-path /Users/graysonpatterson/Grayson/Snipr
// swift-tools-version: 6.0
//
// Best-effort time-to-pixel measurement for Phase 1's capture flow.
//
// Per plan.md the goal is hotkey-handler-entry → `pngData.write` return p50
// ≤ 200 ms. Two limitations are unavoidable from a SwiftPM script:
//
// 1. We can't fire the global hotkey here; the script sits ~1 layer below
//    the hotkey path (CaptureFlowPresenter.storeCapture).
// 2. SCK requires Screen Recording permission for the bundle that runs it.
//    A bare swift script gets prompted on first call. The measurement only
//    runs when permission is granted; otherwise we report what we can.
//
// Run from the repo root:
//   swift run MeasureCapture
//
// The script is registered as a separate executable target only when this
// file is compiled into the build — the main `swift build` ignores it (no
// target wired in Package.swift). To measure, copy this file into a project
// `script/` runner of your choice; the file lives here primarily as a
// canonical recipe rather than an automated CI step.

import AppKit
import CoreGraphics
import Foundation
import os.signpost
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
struct Measurement {
    static func main() async {
        let log = OSLog(subsystem: "com.snipr.measure", category: .pointsOfInterest)
        let signpostID = OSSignpostID(log: log)

        let runs = 20
        var samples: [TimeInterval] = []

        guard let screen = NSScreen.main, let displayID = screen.sniprDisplayID else {
            print("No main screen available — abort.")
            exit(1)
        }

        let rect = CGRect(x: 0, y: 0, width: min(800, screen.frame.width), height: min(600, screen.frame.height))

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            print("SCShareableContent failed (likely missing Screen Recording permission): \(error)")
            print("p50: requires GUI / permission, could not measure")
            return
        }

        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            print("No SCDisplay for main display.")
            return
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width)
        configuration.height = Int(rect.height)
        configuration.showsCursor = false

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let tempURL = FileManager.default.temporaryDirectory.appending(path: "snipr-measure.png")

        for run in 0..<runs {
            let start = ContinuousClock.now
            os_signpost(.begin, log: log, name: "Capture", signpostID: signpostID, "%d", run)

            do {
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let data = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, cgImage, nil)
                _ = CGImageDestinationFinalize(dest)
                try (data as Data).write(to: tempURL)
            } catch {
                print("Run \(run) failed: \(error)")
                continue
            }

            os_signpost(.end, log: log, name: "Capture", signpostID: signpostID)
            let elapsed = ContinuousClock.now - start
            samples.append(elapsed.toMilliseconds())
        }

        guard !samples.isEmpty else {
            print("No successful runs.")
            return
        }

        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        print(String(format: "Runs: %d  p50: %.1f ms  p95: %.1f ms  min: %.1f ms  max: %.1f ms",
                     sorted.count, p50, p95, sorted.first!, sorted.last!))
    }
}

extension Duration {
    func toMilliseconds() -> Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

extension NSScreen {
    fileprivate var sniprDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

await Measurement.main()
