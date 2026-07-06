import Foundation

/// Sequence of steps the executor walks in order. Phase 4's command palette
/// macros register a small set of canonical workflows ("Capture → OCR →
/// Clipboard", etc.) but the model is open: more steps slot in via
/// `WorkflowStep`.
struct Workflow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let steps: [WorkflowStep]

    init(id: String, title: String, subtitle: String, steps: [WorkflowStep]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.steps = steps
    }
}

extension Workflow {
    /// Built-in workflows surfaced by the command palette under their own
    /// "Workflows" section. Stays here (rather than baked into the palette
    /// view) so unit tests can verify the step composition without booting
    /// the UI.
    @MainActor
    static var builtIns: [Workflow] {
        // Only end-to-end working workflows ship in the palette. The translate
        // step (WorkflowStep.translate + PendingTranslationEngine) stays in
        // the codebase for when Apple's Translation framework gets wired in,
        // but a built-in that always errors is worse than its absence.
        [
            Workflow(
                id: "snipr.workflow.capture-ocr-clipboard",
                title: "Capture → OCR → Clipboard",
                subtitle: "Capture a region, recognize text, copy result",
                steps: [.capture, .ocr, .clipboard]
            ),
            Workflow(
                id: "snipr.workflow.capture-pin",
                title: "Capture → Pin",
                subtitle: "Capture a region and pin it as a floating reference",
                steps: [.capture, .pin]
            )
        ]
    }
}
