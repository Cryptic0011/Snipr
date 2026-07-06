import CoreGraphics
import Foundation
import XCTest
@testable import Snipr

@MainActor
final class WorkflowExecutorTests: XCTestCase {
    func testRunsStepsInOrder() async throws {
        let env = FakeWorkflowEnvironment()
        env.captureResult = .success(makeImage())
        env.ocrResult = .success("hello")
        env.translationResult = .success("hola")

        let executor = WorkflowExecutor(environment: env)
        let workflow = Workflow(
            id: "test",
            title: "Test",
            subtitle: "Test",
            steps: [.capture, .ocr, .translate(toLocale: Locale(identifier: "es-ES")), .clipboard]
        )

        let context = try await executor.run(workflow)

        XCTAssertEqual(env.calls, ["capture", "ocr", "translate", "clipboard"])
        XCTAssertEqual(context.executedSteps, ["Capture", "OCR", "Translate (es-ES)", "Clipboard"])
        XCTAssertEqual(env.lastClipboardText, "hola")
    }

    func testCaptureProducesImageThenOCRConsumesIt() async throws {
        let env = FakeWorkflowEnvironment()
        env.captureResult = .success(makeImage())
        env.ocrResult = .success("recognized")

        let executor = WorkflowExecutor(environment: env)
        let workflow = Workflow(
            id: "test",
            title: "Test",
            subtitle: "Test",
            steps: [.capture, .ocr, .clipboard]
        )

        let context = try await executor.run(workflow)
        XCTAssertEqual(context.text, "recognized")
        XCTAssertEqual(env.lastClipboardText, "recognized")
    }

    func testErrorShortCircuitsRemainingSteps() async {
        struct StubError: Error {}
        let env = FakeWorkflowEnvironment()
        env.captureResult = .success(makeImage())
        env.ocrResult = .failure(StubError())

        let executor = WorkflowExecutor(environment: env)
        let workflow = Workflow(
            id: "test",
            title: "Test",
            subtitle: "Test",
            steps: [.capture, .ocr, .clipboard]
        )

        do {
            _ = try await executor.run(workflow)
            XCTFail("expected throw")
        } catch {
            // expected
        }
        XCTAssertEqual(env.calls, ["capture", "ocr"])
        XCTAssertNil(env.lastClipboardText)
    }

    func testTranslateStepFailsLoudlyOnUnsupportedOS() async {
        let env = FakeWorkflowEnvironment()
        env.captureResult = .success(makeImage())
        env.ocrResult = .success("hello")
        env.translationResult = .failure(TranslationError.unsupportedOnThisOS)

        let executor = WorkflowExecutor(environment: env)
        let workflow = Workflow(
            id: "test",
            title: "Test",
            subtitle: "Test",
            steps: [.capture, .ocr, .translate(toLocale: Locale.current), .clipboard]
        )

        do {
            _ = try await executor.run(workflow)
            XCTFail("expected throw — unsupported OS step should propagate")
        } catch {
            // expected — short-circuits clipboard
        }
        XCTAssertEqual(env.calls, ["capture", "ocr", "translate"])
        XCTAssertNil(env.lastClipboardText)
    }

    func testCaptureStepReturningNilShortCircuitsImageDependentSteps() async {
        let env = FakeWorkflowEnvironment()
        env.captureResult = .success(nil)

        let executor = WorkflowExecutor(environment: env)
        let workflow = Workflow(
            id: "test",
            title: "Test",
            subtitle: "Test",
            steps: [.capture, .ocr]
        )

        do {
            _ = try await executor.run(workflow)
            XCTFail("expected throw — OCR can't run without image")
        } catch {
            // expected
        }
    }

    func testBuiltInWorkflowsExist() {
        let workflows = Workflow.builtIns
        XCTAssertEqual(workflows.count, 2)
        XCTAssertEqual(workflows[0].steps, [.capture, .ocr, .clipboard])
        XCTAssertEqual(workflows[1].steps, [.capture, .pin])
        // The translate workflow stays out of the palette until the engine
        // actually translates.
        XCTAssertFalse(workflows.contains { $0.steps.contains { step in
            if case .translate = step { return true } else { return false }
        } })
    }

    func testTranslationPendingEngineThrowsOnAllOSes() async {
        // The Phase 4 implementation explicitly does not silently pass the
        // text through unchanged on macOS 14.4+ — there is no translation
        // happening behind the API yet, so the engine throws and the
        // executor short-circuits the rest of the workflow.
        guard #available(macOS 14.4, *) else { return }
        let engine = PendingTranslationEngine()
        do {
            _ = try await engine.translate(text: "hello", toLocale: Locale(identifier: "es-ES"))
            XCTFail("expected throw — translation backend is not yet wired")
        } catch let error as TranslationError {
            switch error {
            case .unsupportedOnThisOS:
                break
            case .failed:
                XCTFail("expected unsupportedOnThisOS")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testUnsupportedTranslationEngineThrows() async {
        let engine = UnsupportedTranslationEngine()
        do {
            _ = try await engine.translate(text: "hello", toLocale: Locale.current)
            XCTFail("expected throw")
        } catch let error as TranslationError {
            switch error {
            case .unsupportedOnThisOS:
                break
            case .failed:
                XCTFail("expected unsupportedOnThisOS")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    private func makeImage() -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return ctx.makeImage()!
    }
}

@MainActor
private final class FakeWorkflowEnvironment: WorkflowEnvironment {
    var captureResult: Result<CGImage?, Error> = .success(nil)
    var ocrResult: Result<String, Error> = .success("")
    var translationResult: Result<String, Error> = .success("")
    var calls: [String] = []
    var lastClipboardText: String?
    var lastClipboardImage: CGImage?

    func captureImage() async throws -> CGImage? {
        calls.append("capture")
        return try captureResult.get()
    }

    func ocrText(in image: CGImage) async throws -> String {
        calls.append("ocr")
        return try ocrResult.get()
    }

    func translate(text: String, to locale: Locale) async throws -> String {
        calls.append("translate")
        return try translationResult.get()
    }

    func writeToClipboard(text: String?, image: CGImage?) {
        calls.append("clipboard")
        lastClipboardText = text
        lastClipboardImage = image
    }

    func saveImage(_ image: CGImage) async throws -> URL? {
        calls.append("save")
        return URL(fileURLWithPath: "/tmp/fake.png")
    }

    func pinImage(_ image: CGImage, at savedURL: URL?) {
        calls.append("pin")
    }

    func annotateImage(at url: URL) {
        calls.append("annotate")
    }
}
