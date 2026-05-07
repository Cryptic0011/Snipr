import Foundation

/// Atom of a chained workflow. Each case matches a single user-visible action
/// the executor performs against its mock-engine-friendly seams. New steps
/// (`save`, `pin`, `annotate`) are recognized but currently treated as
/// declarative markers — the executor wires them to the existing capture-flow
/// surface.
enum WorkflowStep: Equatable, Sendable {
    /// Trigger the standard region-selection capture overlay; on commit the
    /// captured `CGImage` flows into subsequent steps via `WorkflowContext`.
    case capture
    /// Run OCR on the most recent capture; recognized text replaces the
    /// running context's text payload.
    case ocr
    /// Translate the running context's text payload into the given locale.
    case translate(toLocale: Locale)
    /// Copy the running context's text payload (preferred) or image bytes to
    /// the clipboard.
    case clipboard
    /// Persist the running capture to disk through the smart-folder-aware
    /// `CaptureStore.addCapture` path.
    case save
    /// Open the most recent capture as a floating pinned reference.
    case pin
    /// Open the annotation/preview window for the most recent capture.
    case annotate

    /// Diagnostic title — used by the command palette and tests.
    var title: String {
        switch self {
        case .capture: "Capture"
        case .ocr: "OCR"
        case .translate(let locale): "Translate (\(locale.identifier))"
        case .clipboard: "Clipboard"
        case .save: "Save"
        case .pin: "Pin"
        case .annotate: "Annotate"
        }
    }
}
