import AppKit
import CoreGraphics
import Foundation

/// Runtime state passed between workflow steps. Mutates as the executor
/// walks the step list — a `capture` step writes the image, an `ocr` step
/// writes the text, `translate` rewrites the text, `clipboard` reads
/// whichever is available.
struct WorkflowContext: Sendable {
    var image: CGImage?
    var text: String?
    var lastSavedURL: URL?
    /// Steps that have already executed, in order. Tests assert on this.
    var executedSteps: [String] = []
}

/// Hooks the executor calls into. Splitting the side-effecting work behind a
/// protocol lets `WorkflowExecutorTests` swap in a fake without spinning up
/// the capture overlay or pasteboard.
@MainActor
protocol WorkflowEnvironment: AnyObject {
    /// Drive the standard capture flow and return the resulting CGImage when
    /// the user commits the selection. Returning `nil` short-circuits the
    /// rest of the workflow.
    func captureImage() async throws -> CGImage?
    /// Run the configured OCR engine against `image`.
    func ocrText(in image: CGImage) async throws -> String
    /// Translate `text` into `locale` via the configured `TranslationEngine`.
    /// Errors propagate so the executor can short-circuit the chain.
    func translate(text: String, to locale: Locale) async throws -> String
    /// Copy `text` (preferred) or PNG-encoded `image` to the system clipboard.
    func writeToClipboard(text: String?, image: CGImage?)
    /// Persist `image` to the capture store and return the on-disk URL.
    func saveImage(_ image: CGImage) async throws -> URL?
    /// Show `image` (or its persisted URL) as a pinned floating panel.
    func pinImage(_ image: CGImage, at savedURL: URL?)
    /// Open the annotation/preview surface for the last saved capture URL.
    func annotateImage(at url: URL)
}

enum WorkflowExecutorError: LocalizedError {
    case missingImage(stepTitle: String)
    case missingText(stepTitle: String)

    var errorDescription: String? {
        switch self {
        case .missingImage(let stepTitle):
            "Workflow step \(stepTitle) needed an image but none had been captured yet."
        case .missingText(let stepTitle):
            "Workflow step \(stepTitle) needed text but no prior step produced any."
        }
    }
}

/// Walks a `Workflow.steps` array against a `WorkflowEnvironment`. Errors
/// short-circuit — the first thrown step bubbles up via the optional
/// `onError` callback the coordinator wires into `NSAlert`.
@MainActor
final class WorkflowExecutor {
    let environment: any WorkflowEnvironment

    init(environment: any WorkflowEnvironment) {
        self.environment = environment
    }

    /// Returns the final `WorkflowContext` for tests to introspect. Throws on
    /// the first failed step; subsequent steps do not run.
    @discardableResult
    func run(_ workflow: Workflow) async throws -> WorkflowContext {
        var context = WorkflowContext()
        for step in workflow.steps {
            try await execute(step, context: &context)
        }
        return context
    }

    private func execute(_ step: WorkflowStep, context: inout WorkflowContext) async throws {
        context.executedSteps.append(step.title)
        switch step {
        case .capture:
            context.image = try await environment.captureImage()
        case .ocr:
            guard let image = context.image else {
                throw WorkflowExecutorError.missingImage(stepTitle: step.title)
            }
            context.text = try await environment.ocrText(in: image)
        case .translate(let locale):
            guard let text = context.text else {
                throw WorkflowExecutorError.missingText(stepTitle: step.title)
            }
            // Translation errors (including OS-version unsupported) propagate
            // up so the user sees a single explanatory alert. The executor
            // does not silently swallow `unsupportedOnThisOS` — the workflow
            // step runs, throws, and the chain short-circuits.
            context.text = try await environment.translate(text: text, to: locale)
        case .clipboard:
            environment.writeToClipboard(text: context.text, image: context.image)
        case .save:
            guard let image = context.image else {
                throw WorkflowExecutorError.missingImage(stepTitle: step.title)
            }
            context.lastSavedURL = try await environment.saveImage(image)
        case .pin:
            guard let image = context.image else {
                throw WorkflowExecutorError.missingImage(stepTitle: step.title)
            }
            environment.pinImage(image, at: context.lastSavedURL)
        case .annotate:
            guard let url = context.lastSavedURL else {
                throw WorkflowExecutorError.missingImage(stepTitle: step.title)
            }
            environment.annotateImage(at: url)
        }
    }
}
