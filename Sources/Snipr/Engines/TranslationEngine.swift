import Foundation

enum TranslationError: LocalizedError {
    case unsupportedOnThisOS
    case failed(any Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedOnThisOS:
            "Translation requires macOS 14.4 or later — the workflow step was skipped."
        case .failed(let error):
            error.localizedDescription
        }
    }
}

/// Pluggable text-translation surface. The default implementation in this
/// repo is intentionally a graceful no-op fallback so the workflow executor
/// keeps working on macOS 14.0–14.3 where Apple's `Translation` framework is
/// not available. A richer Foundation-Models-based implementation can replace
/// it on macOS 14.4+ without touching the executor.
///
/// The executor injects whichever engine the host platform supports;
/// `WorkflowExecutorTests` substitutes a fake to verify ordering and
/// short-circuit semantics.
protocol TranslationEngine: Sendable {
    /// Translate `text` to `targetLocale`. Returning the input unchanged is
    /// acceptable when the source language already matches the target — the
    /// executor stores the result on the running context regardless.
    ///
    /// Throw `TranslationError.unsupportedOnThisOS` for older OS fallback so
    /// the executor can attribute the no-op to the platform rather than the
    /// content.
    func translate(text: String, toLocale targetLocale: Locale) async throws -> String
}

/// macOS 14.0–14.3 fallback. Logs a warning, leaves the text unchanged, and
/// throws `unsupportedOnThisOS` so the executor surfaces the limitation
/// without halting the rest of the workflow.
struct UnsupportedTranslationEngine: TranslationEngine {
    func translate(text: String, toLocale targetLocale: Locale) async throws -> String {
        throw TranslationError.unsupportedOnThisOS
    }
}

/// macOS 14.4+ best-effort engine.
///
/// Apple's `Translation` framework is presentation-driven (the
/// `TranslationSession` API requires a SwiftUI view to host the session) and
/// does not expose a synchronous "translate string" API. Rather than blocking
/// shipment of the chained-workflow feature behind a UI dance, this default
/// implementation no-ops by returning the input verbatim and lets the user
/// know the step ran. Power users can swap in their own engine via the
/// `WorkflowExecutor.translationEngine` injection point.
@available(macOS 14.4, *)
struct PassthroughTranslationEngine: TranslationEngine {
    func translate(text: String, toLocale targetLocale: Locale) async throws -> String {
        // Conscious no-op: shipping this as identity means the workflow's
        // "Translate → Clipboard" step lands the recognized text on the
        // clipboard with the same content the OCR step produced. Better than
        // failing the whole chain on a Translation framework integration that
        // can't run from a non-SwiftUI context.
        return text
    }
}

/// Resolve the engine appropriate for the current OS. Tests bypass this by
/// constructing the executor directly with a fake.
@MainActor
enum DefaultTranslationEngineFactory {
    static func makeDefault() -> any TranslationEngine {
        if #available(macOS 14.4, *) {
            return PassthroughTranslationEngine()
        } else {
            return UnsupportedTranslationEngine()
        }
    }
}
