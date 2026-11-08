import Cocoa

final class HistoryTable: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if DELETE_KEY_CODES.contains(event.keyCode) { onDelete?() } else { super.keyDown(with: event) }
    }
}

// A list of the history with a search field. Clicking a row speaks the word; ⌫ deletes the selected rows.
final class HistoryWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onSpeak: ((String) -> Void)?

    private let history: History
    private let window: NSWindow
    private let search = NSSearchField()
    private let table = HistoryTable()
    private let dateFormatter = DateFormatter()
    private var shown: [HistoryEntry] = []

    init(history: History) {
        self.history = history
        window = NSWindow(contentRect: NSRect(origin: .zero, size: HISTORY_WINDOW_SIZE),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        super.init()
        window.title = "Word History"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("History")

        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true

        search.placeholderString = "Search words and translations"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(reload)

        for column in HISTORY_COLUMNS {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.width = column.width
            table.addTableColumn(tableColumn)
        }
        table.usesAutomaticRowHeights = true
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(speakClickedRow)
        table.onDelete = { [weak self] in self?.deleteSelectedRows() }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let stack = NSStackView(views: [search, scroll])
        stack.orientation = .vertical
        stack.spacing = HISTORY_SPACING
        stack.edgeInsets = NSEdgeInsets(top: HISTORY_SPACING, left: HISTORY_SPACING, bottom: HISTORY_SPACING, right: HISTORY_SPACING)
        window.contentView = stack

        history.onChange = { [weak self] in self?.reload() }
        // Wrapped text gets taller or shorter as its column changes width.
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: NSTableView.columnDidResizeNotification, object: table)
    }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func reload() {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        shown = query.isEmpty ? history.entries : history.entries.filter { $0.matches(query) }
        table.reloadData()
    }

    @objc private func speakClickedRow() {
        guard shown.indices.contains(table.clickedRow) else { return }
        onSpeak?(shown[table.clickedRow].word)
    }

    private func deleteSelectedRows() {
        history.remove(Set(table.selectedRowIndexes.map { shown[$0].word }))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let entry = shown[row]
        let view = cell(id)
        switch id.rawValue {
        case "word":
            view.textField?.attributedStringValue = twoLines(entry.word, entry.translation.phonetic.map { "[\($0)]" })
        case "translation":
            let meanings = entry.translation.dictionary.map { "\($0.partOfSpeech): \($0.terms.joined(separator: ", "))" }
            view.textField?.attributedStringValue = twoLines(entry.translation.text, meanings.isEmpty ? nil : meanings.joined(separator: "; "))
        case "count":
            view.textField?.stringValue = "×\(entry.count)"
        default:
            view.textField?.stringValue = dateFormatter.string(from: entry.lastLookedUp)
        }
        return view
    }

    private func cell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        if let reused = table.makeView(withIdentifier: id, owner: self) as? NSTableCellView { return reused }
        let view = NSTableCellView()
        view.identifier = id
        let field = NSTextField(wrappingLabelWithString: "")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)
        view.textField = field
        // The row grows to fit the whole text, and keeps the usual height for a short one.
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HISTORY_CELL_INSET),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HISTORY_CELL_INSET),
            field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            field.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: HISTORY_CELL_INSET),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: HISTORY_ROW_HEIGHT),
        ])
        return view
    }

    // Long text wraps, so the whole phrase and translation show.
    private func twoLines(_ main: String, _ detail: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSMutableAttributedString(string: main, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .paragraphStyle: paragraph,
        ])
        if let detail {
            text.append(NSAttributedString(string: "\n\(detail)", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph,
            ]))
        }
        return text
    }
}
