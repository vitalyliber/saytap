import Cocoa

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

final class Popup {
    var onReplay: (() -> Void)?
    // A line about speech under every pop-up while it's set; the open pop-up updates when it changes.
    var speechNote: String? {
        didSet { if panel.isVisible, let shown { show(word: shown.word, translation: shown.translation, status: shown.status) } }
    }

    var style = POPUP_STYLES.first { $0.title == DEFAULT_POPUP_STYLE }! {
        didSet { applyStyle() }
    }

    private let panel: PopupPanel
    private let stack = NSStackView()
    private var hideTimer: Timer?
    private var monitors: [Any] = []
    private var shown: (word: String, translation: Translation?, status: String?)?

    init() {
        panel = PopupPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: POPUP_PADDING, left: POPUP_PADDING, bottom: POPUP_PADDING, right: POPUP_PADDING)
        stack.translatesAutoresizingMaskIntoConstraints = false
        applyStyle()
    }

    // Puts the content on a new background, and redraws the open pop-up in the new style.
    private func applyStyle() {
        let background = style.material.map { roundedEffectView(material: $0, cornerRadius: style.cornerRadius) }
            ?? PopupBackground(style: style)
        stack.removeFromSuperview()
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: POPUP_WIDTH),
        ])
        panel.contentView = background
        if panel.isVisible, let shown { show(word: shown.word, translation: shown.translation, status: shown.status) }
    }

    // An empty word shows only the status, for messages that aren't about a word.
    func show(word: String, translation: Translation?, status: String? = nil, at point: NSPoint? = nil) {
        shown = (word, translation, status)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if !word.isEmpty { stack.addArrangedSubview(header(word: word, phonetic: translation?.phonetic)) }
        if let translation {
            stack.addArrangedSubview(label(translation.text, size: 16, weight: .medium))
            for entry in translation.dictionary {
                stack.addArrangedSubview(dictionaryLine(entry.partOfSpeech, entry.terms))
            }
        }
        for line in [status, word.isEmpty ? nil : speechNote].compactMap({ $0 }) {
            stack.addArrangedSubview(label(line, size: 13, color: style.secondary))
        }

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView!.fittingSize
        let origin = point.map { position(for: size, near: $0) } ?? panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        // The shadow follows the window's opaque pixels, so it's rebuilt for the rounded corners at this size.
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        startHiding()
    }

    func hide() {
        panel.orderOut(nil)
        hideTimer?.invalidate()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func startHiding() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: POPUP_LIFETIME, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) { self.startHiding() } else { self.hide() }
        }

        guard monitors.isEmpty else { return }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        }) { monitors.append(clicks) }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == ESCAPE_KEY_CODE { self?.hide() }
        }) { monitors.append(keys) }
    }

    // Below-right of the cursor, flipped to stay on the screen the cursor is on.
    private func position(for size: NSSize, near point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        var x = point.x + POPUP_CURSOR_OFFSET
        var y = point.y - POPUP_CURSOR_OFFSET - size.height
        if x + size.width > bounds.maxX { x = point.x - POPUP_CURSOR_OFFSET - size.width }
        if y < bounds.minY { y = point.y + POPUP_CURSOR_OFFSET }
        return NSPoint(x: max(bounds.minX, x), y: min(y, bounds.maxY - size.height))
    }

    private func header(word: String, phonetic: String?) -> NSView {
        let replay = NSButton(image: NSImage(systemSymbolName: style.speakerSymbol, accessibilityDescription: "Say again")!,
                              target: self, action: #selector(replay))
        replay.isBordered = false
        replay.contentTintColor = style.accent

        let title = label(word, size: style.wordSize, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 2
        let row = NSStackView(views: [replay, title])
        row.spacing = 6
        guard let phonetic, !phonetic.isEmpty else { return row }

        let column = NSStackView(views: [row, label(style.phonetic.prefix + phonetic + style.phonetic.suffix, size: 13, color: style.secondary)])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        return column
    }

    private func dictionaryLine(_ partOfSpeech: String, _ terms: [String]) -> NSTextField {
        let text = NSMutableAttributedString(string: "\(partOfSpeech)  ", attributes: [
            .font: font(size: 12, weight: .medium, italic: style.italicPartOfSpeech),
            .foregroundColor: style.secondary,
        ])
        text.append(NSAttributedString(string: terms.joined(separator: ", "), attributes: [
            .font: font(size: 13, weight: .regular),
            .foregroundColor: style.text,
        ]))
        let field = NSTextField(labelWithAttributedString: text)
        field.preferredMaxLayoutWidth = POPUP_WIDTH - 2 * POPUP_PADDING
        return field
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font(size: size, weight: weight)
        field.textColor = color ?? style.text
        field.isSelectable = false
        field.preferredMaxLayoutWidth = POPUP_WIDTH - 2 * POPUP_PADDING
        return field
    }

    // The system font in the style's design: rounded, serif or the default.
    private func font(size: CGFloat, weight: NSFont.Weight, italic: Bool = false) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        descriptor = descriptor.withDesign(style.design) ?? descriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    @objc private func replay() { onReplay?() }
}
