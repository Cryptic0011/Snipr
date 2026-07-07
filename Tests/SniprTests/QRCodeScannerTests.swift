import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import Snipr

final class QRCodeScannerTests: XCTestCase {
    func testReadsPayloadFromGeneratedQRCode() throws {
        let payload = "https://snipr.test/hello?x=1"
        let image = try XCTUnwrap(makeQRImage(payload: payload))
        XCTAssertEqual(try QRCodeScanner.payload(in: image), payload)
    }

    func testThrowsWhenNoCodePresent() {
        let context = CIContext()
        let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        guard let image = context.createCGImage(blank, from: blank.extent) else {
            return XCTFail("Could not build blank fixture")
        }
        XCTAssertThrowsError(try QRCodeScanner.payload(in: image)) { error in
            guard case QRScanError.noCodeFound = error else {
                return XCTFail("Expected noCodeFound, got \(error)")
            }
        }
    }

    private func makeQRImage(payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale up so Vision has real pixels to work with.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
