@preconcurrency import AVFoundation
import AppKit
import QuartzCore

/// Everything the compositor needs to draw the synthetic cursor.
struct CursorOverlaySpec: Sendable {
    let samples: [CursorSample]
    let regionInScreen: CGRect
    let scale: Double
    let color: CursorColor
    let smoothed: Bool
}

enum VideoCompositorError: LocalizedError {
    case exportFailed(any Error)
    case sessionUnavailable
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .exportFailed(let error): error.localizedDescription
        case .sessionUnavailable: "Snipr could not start the video export session."
        case .noVideoTrack: "The recording has no video track."
        }
    }
}

/// One AVFoundation compositor for both share-ready features: backdrop
/// exports from the video preview, and the automatic cursor bake after a
/// recording stops. Rendering happens on the GPU via the Core Animation
/// tool — layers are declarative, no per-frame CPU work.
enum VideoCompositor {
    /// H.264 wants even dimensions; round up so content is never cropped.
    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: 2 * ((size.width / 2).rounded(.up)),
            height: 2 * ((size.height / 2).rounded(.up))
        )
    }

    /// Classic macOS arrow, drawn in top-left-origin (y-down) coordinates
    /// with the hotspot/tip at (0,0). Proportions follow the system arrow's
    /// 17:24 box at `height` = 24.
    static func cursorArrowPath(height: CGFloat) -> CGPath {
        let s = height / 24.0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))                       // tip
        path.addLine(to: CGPoint(x: 0, y: 20.5 * s))             // left edge down
        path.addLine(to: CGPoint(x: 4.6 * s, y: 16.2 * s))       // notch in
        path.addLine(to: CGPoint(x: 7.6 * s, y: 24.0 * s))       // down to click-heel
        path.addLine(to: CGPoint(x: 10.5 * s, y: 21.9 * s))      // heel across
        path.addLine(to: CGPoint(x: 7.5 * s, y: 15.0 * s))       // back up
        path.addLine(to: CGPoint(x: 13.9 * s, y: 14.7 * s))      // out to right barb
        path.closeSubpath()
        return path
    }

    static func composite(
        sourceURL: URL,
        outputURL: URL,
        backdrop: VideoBackdrop?,
        backdropScreen: NSScreen?,
        cursor: CursorOverlaySpec?,
        trimStart: TimeInterval?,
        trimEnd: TimeInterval?
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoCompositorError.noVideoTrack
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Canvas: padded per BeautifyRenderer's math when there's a backdrop,
        // bare video size for a cursor-only bake. Even either way.
        let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        let padding: CGFloat
        let canvas: CGSize
        if backdrop != nil {
            let geometry = BeautifyRenderer.canvasGeometry(for: videoSize)
            padding = geometry.padding
            canvas = evenSize(geometry.canvas)
        } else {
            padding = 0
            canvas = evenSize(videoSize)
        }

        // ---- Layer tree (all frames in top-left-origin space via
        // isGeometryFlipped; CoreAnimation renders it upright). ----
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: canvas)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        let videoRect = CGRect(
            x: (canvas.width - videoSize.width) / 2,
            y: (canvas.height - videoSize.height) / 2,
            width: videoSize.width,
            height: videoSize.height
        )

        if let backdrop {
            parentLayer.addSublayer(backdropLayer(for: backdrop, screen: backdropScreen, canvas: canvas))

            // Shadow lives on a container so the video layer itself can clip
            // to rounded corners (shadow + masksToBounds are exclusive).
            let cornerRadius = 16 * (videoSize.width / max(videoSize.width, 1200))
            let shadowContainer = CALayer()
            shadowContainer.frame = videoRect
            shadowContainer.shadowColor = CGColor(gray: 0, alpha: 1)
            shadowContainer.shadowOpacity = 0.45
            shadowContainer.shadowRadius = padding * 0.5
            shadowContainer.shadowOffset = CGSize(width: 0, height: padding * 0.16)
            shadowContainer.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: videoRect.size),
                cornerWidth: max(cornerRadius, 8),
                cornerHeight: max(cornerRadius, 8),
                transform: nil
            )

            videoLayer.frame = CGRect(origin: .zero, size: videoRect.size)
            videoLayer.cornerRadius = max(cornerRadius, 8)
            videoLayer.masksToBounds = true
            shadowContainer.addSublayer(videoLayer)
            parentLayer.addSublayer(shadowContainer)
        } else {
            videoLayer.frame = videoRect
            parentLayer.addSublayer(videoLayer)
        }

        if let cursor, !cursor.samples.isEmpty {
            // Cursor coordinates are relative to the video, so parent the
            // arrow to the layer that contains the video content.
            let host = backdrop != nil ? videoLayer : parentLayer
            let offset = backdrop != nil ? CGPoint.zero : videoRect.origin
            host.addSublayer(cursorLayer(
                for: cursor,
                videoSize: videoSize,
                offset: offset,
                videoDuration: durationSeconds
            ))
        }

        // ---- Composition ----
        let composition = AVMutableVideoComposition(propertiesOf: asset)
        composition.renderSize = canvas
        composition.instructions = passthroughInstruction(for: videoTrack, duration: duration)
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoCompositorError.sessionUnavailable
        }
        session.videoComposition = composition
        session.outputURL = outputURL
        let fileType: AVFileType = outputURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        session.outputFileType = fileType
        // Clamp both bounds to [0, duration] before validating — reuses
        // TrimExporter's math so an out-of-range request (e.g. both bounds
        // past the asset's freshly-loaded duration) degrades to a full-length
        // export instead of an invalid CMTimeRange and a failed session.
        if let trimStart, let trimEnd,
           let range = TrimExporter.clampedRange(start: trimStart, end: trimEnd, duration: durationSeconds) {
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                end: CMTime(seconds: range.end, preferredTimescale: 600)
            )
        }

        do {
            // macOS 15+ exposes `export(to:as:)` async. macOS 14 still ships
            // the deprecated `exportAsynchronously` callback path — see
            // TrimExporter for the same deviation, kept consistent here.
            try await session.export(to: outputURL, as: fileType)
        } catch {
            throw VideoCompositorError.exportFailed(error)
        }
        return outputURL
    }

    // MARK: - Layer builders

    private static func backdropLayer(for backdrop: VideoBackdrop, screen: NSScreen?, canvas: CGSize) -> CALayer {
        let frame = CGRect(origin: .zero, size: canvas)
        switch backdrop {
        case .gradient(let style):
            let layer = CAGradientLayer()
            layer.frame = frame
            let (top, bottom) = style.colors
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            layer.colors = [
                CGColor(colorSpace: space, components: top),
                CGColor(colorSpace: space, components: bottom)
            ].compactMap { $0 }
            layer.startPoint = CGPoint(x: 0, y: 0)
            layer.endPoint = CGPoint(x: 1, y: 1)
            return layer
        case .bundled, .wallpaper:
            let layer = CALayer()
            layer.frame = frame
            if let image = backdrop.resolveImage(for: screen) {
                var rect = CGRect(origin: .zero, size: image.size)
                layer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                layer.contentsGravity = .resizeAspectFill
                layer.masksToBounds = true
            } else {
                // Wallpaper unreadable — graphite gradient fallback (spec).
                return backdropLayer(for: .gradient(.graphite), screen: nil, canvas: canvas)
            }
            return layer
        }
    }

    private static func cursorLayer(
        for cursor: CursorOverlaySpec,
        videoSize: CGSize,
        offset: CGPoint,
        videoDuration: TimeInterval
    ) -> CALayer {
        // Pixels-per-point of the recording; sized so the arrow matches how
        // big the real cursor would have appeared, times the user multiplier.
        let pixelScale = videoSize.width / max(cursor.regionInScreen.width, 1)
        let arrowHeight = 24 * pixelScale * cursor.scale

        let shape = CAShapeLayer()
        shape.path = cursorArrowPath(height: arrowHeight)
        shape.fillColor = cursor.color.fill
        shape.strokeColor = cursor.color.outline
        shape.lineWidth = max(1, arrowHeight / 16)
        shape.lineJoin = .round
        let box = shape.path?.boundingBox ?? .zero
        shape.bounds = CGRect(x: 0, y: 0, width: box.maxX, height: box.maxY)
        shape.anchorPoint = .zero   // position == the arrow tip

        let used = cursor.smoothed
            ? CursorPath.thinned(cursor.samples, stride: 6)   // ~10 Hz anchors
            : cursor.samples
        let points = used.map {
            let p = CursorPath.mapToVideoPixels($0.location, region: cursor.regionInScreen, scale: pixelScale)
            return CGPoint(x: p.x + offset.x, y: p.y + offset.y)
        }

        guard videoDuration > 0, points.count > 1 else {
            shape.position = points.first ?? .zero
            return shape
        }

        shape.position = points[0]
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = points.map { NSValue(point: $0) }
        animation.keyTimes = used.map { NSNumber(value: min(1, $0.time / videoDuration)) }
        animation.calculationMode = cursor.smoothed ? .cubic : .linear
        animation.duration = videoDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        shape.add(animation, forKey: "cursorPath")
        return shape
    }

    /// The CA tool stretches video content to fill `videoLayer`; the
    /// composition instruction only needs to pass the track through
    /// untransformed at its natural size.
    private static func passthroughInstruction(
        for track: AVAssetTrack,
        duration: CMTime
    ) -> [AVMutableVideoCompositionInstruction] {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instruction.layerInstructions = [layerInstruction]
        return [instruction]
    }
}
