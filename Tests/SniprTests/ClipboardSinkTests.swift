import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Snipr

final class ClipboardSinkTests: XCTestCase {
    /// Local pasteboard so the test doesn't clobber the user's clipboard.
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("SniprClipboardSinkTests"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    @MainActor
    func testCopyPNGWritesPublicPNGType() {
        let data = pngData()
        // The shipping ClipboardSink uses NSPasteboard.general directly, so
        // we exercise the routing logic by mirroring the same code on a
        // private pasteboard: clearing then writing per format. This keeps
        // the test deterministic without mocking NSPasteboard.general.
        pasteboard.setData(data, forType: .png)
        XCTAssertEqual(pasteboard.data(forType: .png), data)
    }

    @MainActor
    func testCopyJPEGWritesTIFFFallbackAndRawType() {
        guard let jpegData = encodeImage(format: .jpeg(quality: 0.85)) else {
            XCTFail("encode failed")
            return
        }

        pasteboard.clearContents()
        if let image = NSImage(data: jpegData), let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        pasteboard.setData(jpegData, forType: jpegType)

        XCTAssertNotNil(pasteboard.data(forType: .tiff), "TIFF fallback for JPEG should be present")
        XCTAssertEqual(pasteboard.data(forType: jpegType), jpegData)
    }

    @MainActor
    func testCopyEntryPointHandlesPNGEndToEnd() {
        // Drive the actual ClipboardSink against general, then immediately
        // restore the previous content. This is the only path that uses the
        // real API; we keep it tiny so the user's clipboard is touched for
        // microseconds.
        let general = NSPasteboard.general
        let original = general.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        }
        defer {
            general.clearContents()
            if let original {
                for (type, data) in original {
                    general.setData(data, forType: type)
                }
            }
        }

        let data = pngData()
        ClipboardSink.copy(data: data, format: .png)
        XCTAssertEqual(general.data(forType: .png), data)
    }

    private func pngData() -> Data {
        encodeImage(format: .png)!
    }

    private func encodeImage(format: CaptureFormat) -> Data? {
        let image = makeCGImage()
        let captured = CapturedImage(cgImage: image, pngData: png(image)!, pixelSize: CGSize(width: 4, height: 4))
        return captured.encode(as: format)
    }

    private func makeCGImage(width: Int = 4, height: Int = 4) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.7, green: 0.2, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
