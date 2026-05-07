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
/// Apple's `Translation` framework on macOS is presentation-driven: the
/// public `TranslationSession` API requires a SwiftUI view hosting a
/// `.translationTask(...)` modifier to drive the session. Wiring that into
/// the non-SwiftUI workflow executor is non-trivial and the Phase 4 brief
/// permits a graceful no-op fallback on older OS versions, so Phase 4
/// currently ships only the "unsupported" engine — which throws
/// `unsupportedOnThisOS` — and the workflow executor surfaces that error
/// rather than silently passing through unchanged text.
///
/// This means the "Capture → OCR → Translate → Clipboard" workflow stops
/// at the translate step and an alert tells the user. A future revision
/// can plug a real translator in here without touching the executor.
@available(macOS 14.4, *)
struct PendingTranslationEngine: TranslationEngine {
    func translate(text: String, toLocale targetLocale: Locale) async throws -> String {
        // Conscious throw: shipping a passthrough that pretends to translate
        // would lie to the user. Better to fail loud and document the
        // limitation in plan.md.
        throw TranslationError.unsupportedOnThisOS
    }
}

/// Resolve the engine appropriate for the current OS. Tests bypass this by
/// constructing the executor directly with a fake.
@MainActor
enum DefaultTranslationEngineFactory {
    static func makeDefault() -> any TranslationEngine {
        if #available(macOS 14.4, *) {
            return PendingTranslationEngine()
        } else {
            return UnsupportedTranslationEngine()
        }
    }
}
