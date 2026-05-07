import AppKit

/// Modal-ish input that captures `WxH+x+y` strings during selection. Used by
/// the overlay view when the user presses `T` mid-drag.
@MainActor
final class NumericalEntryPanel: NSPanel {
    private let textField: NSTextField
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void

    init(initialText: String, onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.textField = NSTextField(string: initialText)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 88),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Numerical Entry"
        isFloatingPanel = true
        level = .modalPanel
        hidesOnDeactivate = false

        let label = NSTextField(labelWithString: "Format: WxH+x+y (e.g. 800x600+100+200)")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor

        textField.placeholderString = "800x600+100+200"
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        textField.target = self
        textField.action = #selector(submit)

        let okButton = NSButton(title: "Capture", target: self, action: #selector(submit))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, okButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY

        let stack = NSStackView(views: [label, textField, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let content = NSView(frame: contentLayoutRect)
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
        contentView = content
    }

    @objc private func submit() {
        let text = textField.stringValue
        onSubmit(text)
    }

    @objc private func cancel() {
        onCancel()
    }
}

/// Parses an `WxH+x+y` string like `800x600+100+200` into a `CGRect`.
/// Permissive about whitespace and leading sign on offsets. Returns `nil`
/// when the string isn't a valid expression.
enum NumericalEntryParser {
    static func parse(_ text: String) -> CGRect? {
        let stripped = text.replacingOccurrences(of: " ", with: "")
        // Pattern: <w>x<h>+<x>+<y>  (offsets optional, default 0,0)
        let scanner = Scanner(string: stripped)
        scanner.charactersToBeSkipped = nil

        guard let width = scanNonNegativeInt(scanner) else { return nil }
        guard scanner.scanString("x") != nil || scanner.scanString("X") != nil else { return nil }
        guard let height = scanNonNegativeInt(scanner) else { return nil }

        var x = 0
        var y = 0

        if !scanner.isAtEnd {
            guard scanner.scanString("+") != nil else { return nil }
            guard let parsedX = scanInt(scanner) else { return nil }
            x = parsedX
            guard scanner.scanString("+") != nil else { return nil }
            guard let parsedY = scanInt(scanner) else { return nil }
            y = parsedY
        }

        guard scanner.isAtEnd, width > 0, height > 0 else { return nil }
        return CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    private static func scanInt(_ scanner: Scanner) -> Int? {
        scanner.scanInt()
    }

    private static func scanNonNegativeInt(_ scanner: Scanner) -> Int? {
        guard let value = scanner.scanInt(), value >= 0 else { return nil }
        return value
    }
}
