#if os(macOS)
import SwiftUI
import AppKit

private final class ImmediateSelectTableView: NSTableView {
    var onRowClicked: ((Int) -> Void)?
    var onLinkClicked: ((MetadataLinkTarget) -> Void)?
    private var lastFittedWidth: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        if clickedRow >= 0 {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }

            let clickedCol = column(at: point)
            if clickedCol >= 0 {
                let colID = tableColumns[clickedCol].identifier.rawValue
                if colID == "tags" {
                    super.mouseDown(with: event)
                    return
                }
                if let cellView = view(atColumn: clickedCol, row: clickedRow, makeIfNecessary: false) {
                    if let linkCell = cellView as? LinkTextCellView, let target = linkCell.linkTarget {
                        onLinkClicked?(target)
                        super.mouseDown(with: event)
                        return
                    }
                    if let seriesCell = cellView as? SeriesCellView, let target = seriesCell.linkTarget {
                        onLinkClicked?(target)
                        super.mouseDown(with: event)
                        return
                    }
                    if let titleCell = cellView as? TitleAuthorCellView, let target = titleCell.authorLinkTarget {
                        let pointInCell = cellView.convert(point, from: self)
                        if titleCell.authorLabelContainsPoint(pointInCell) {
                            onLinkClicked?(target)
                            super.mouseDown(with: event)
                            return
                        }
                    }
                }
            }
            onRowClicked?(clickedRow)
        }

        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        adjustWidthToClipView()
    }

    private func adjustWidthToClipView() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let availableWidth = clipView.bounds.width
        guard availableWidth > 0, !tableColumns.isEmpty else { return }

        if abs(availableWidth - lastFittedWidth) > 0.5 {
            fitVisibleColumns(to: availableWidth)
            lastFittedWidth = availableWidth
        }

        if abs(frame.width - availableWidth) > 0.5 {
            setFrameSize(NSSize(width: availableWidth, height: frame.height))
        }
    }

    private func fitVisibleColumns(to availableWidth: CGFloat) {
        let visibleColumns = tableColumns.filter { !$0.isHidden }
        guard !visibleColumns.isEmpty else { return }

        let totalWidth = visibleColumns.reduce(0) { $0 + $1.width }
        let extraWidth = max(frame.width - totalWidth, 0)
        let targetWidth = max(availableWidth - extraWidth, 0)
        guard totalWidth > targetWidth + 0.5 else { return }

        let minTotal = visibleColumns.reduce(0) { $0 + $1.minWidth }
        if minTotal >= targetWidth {
            for column in visibleColumns {
                column.width = column.minWidth
            }
            return
        }

        let adjustable = visibleColumns.reduce(0) { $0 + max($1.width - $1.minWidth, 0) }
        guard adjustable > 0 else { return }

        let overflow = totalWidth - targetWidth
        for column in visibleColumns {
            let delta = max(column.width - column.minWidth, 0)
            let shrink = overflow * (delta / adjustable)
            let proposed = column.width - shrink
            column.width = max(column.minWidth, proposed)
        }
    }
}

struct MediaTableView: NSViewRepresentable {
    let items: [BookMetadata]
    let coverPreference: CoverPreference
    let mediaViewModel: MediaViewModel
    @Binding var selection: BookMetadata.ID?
    @Binding var columnCustomization: TableColumnCustomization<BookMetadata>
    @Binding var sortOrder: [KeyPathComparator<BookMetadata>]
    let onSelect: (BookMetadata) -> Void
    let onInfo: (BookMetadata) -> Void
    var onMetadataLinkClicked: ((MetadataLinkTarget) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, mediaViewModel: mediaViewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = ImmediateSelectTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 48
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        tableView.headerView = NSTableHeaderView()

        setupColumns(tableView: tableView, context: context)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        let coordinator = context.coordinator
        tableView.onRowClicked = { [weak coordinator] row in
            coordinator?.handleRowClicked(row)
        }
        tableView.onLinkClicked = { [weak coordinator] target in
            coordinator?.handleLinkClicked(target)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        let coordinator = context.coordinator
        let oldItems = coordinator.items
        let newItems = items
        let oldCoverPreference = coordinator.coverPreference

        coordinator.parent = self
        coordinator.items = items
        coordinator.coverPreference = coverPreference
        coordinator.mediaViewModel = mediaViewModel

        if oldItems.map(\.id) != newItems.map(\.id) {
            tableView.reloadData()
        } else if oldItems != newItems {
            tableView.reloadData()
        } else if oldCoverPreference != coverPreference {
            tableView.reloadData()
        }

        if let selectedID = selection {
            if let index = items.firstIndex(where: { $0.id == selectedID }) {
                if tableView.selectedRow != index {
                    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                }
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }

        updateSortIndicators(tableView: tableView, context: context)
        updateColumnVisibility(tableView: tableView)
    }

    private static let defaultVisibleColumns: Set<String> = ["cover", "title", "series", "media"]
    private static let columnOrderKey = "library.table.columnOrder"
    private static let defaultColumnOrder = ["cover", "title", "author", "series", "progress", "narrator", "translator", "publicationYear", "status", "added", "lastRead", "tags", "media"]

    private func updateColumnVisibility(tableView: NSTableView) {
        for column in tableView.tableColumns {
            let id = column.identifier.rawValue
            let visibility = columnCustomization[visibility: id]
            let isVisible: Bool
            switch visibility {
            case .visible:
                isVisible = true
            case .hidden:
                isVisible = false
            default:
                isVisible = Self.defaultVisibleColumns.contains(id)
            }
            column.isHidden = !isVisible
        }
    }

    private func setupColumns(tableView: NSTableView, context: Context) {
        let columnDefs: [String: (title: String, minWidth: CGFloat, width: CGFloat, maxWidth: CGFloat)] = [
            "cover": ("", 30, 50, 70),
            "title": ("Title", 100, 200, 10000),
            "author": ("Author", 80, 150, 10000),
            "series": ("Series", 80, 140, 10000),
            "progress": ("Progress", 60, 100, 140),
            "narrator": ("Narrator", 80, 120, 10000),
            "translator": ("Translator", 80, 120, 10000),
            "publicationYear": ("Published", 80, 100, 10000),
            "status": ("Status", 60, 80, 10000),
            "added": ("Added", 80, 100, 10000),
            "lastRead": ("Last Read", 80, 100, 10000),
            "tags": ("Tags", 80, 120, 10000),
            "media": ("Media", 100, 120, 150),
        ]

        let savedOrder = UserDefaults.standard.stringArray(forKey: Self.columnOrderKey) ?? Self.defaultColumnOrder
        let columnOrder = savedOrder.filter { columnDefs[$0] != nil }
        let missingColumns = Self.defaultColumnOrder.filter { !columnOrder.contains($0) }
        let finalOrder = columnOrder + missingColumns

        for id in finalOrder {
            guard let def = columnDefs[id] else { continue }
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = def.title
            column.minWidth = def.minWidth
            column.width = def.width
            column.maxWidth = def.maxWidth
            column.isEditable = false

            if id == "title" || id == "author" || id == "series" ||
               id == "narrator" || id == "translator" || id == "publicationYear" ||
               id == "status" || id == "added" || id == "tags" {
                column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            }

            if id == "lastRead" {
                column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: false)
            }

            if id == "progress" {
                column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: false)
            }

            tableView.addTableColumn(column)
        }
    }

    fileprivate static func saveColumnOrder(_ order: [String]) {
        UserDefaults.standard.set(order, forKey: columnOrderKey)
    }

    private func updateSortIndicators(tableView: NSTableView, context: Context) {
        for column in tableView.tableColumns {
            tableView.setIndicatorImage(nil, in: column)
        }

        guard let comparator = sortOrder.first else { return }

        let keyPathToColumn: [AnyKeyPath: String] = [
            \BookMetadata.title: "title",
            \BookMetadata.sortableAuthor: "author",
            \BookMetadata.sortableSeries: "series",
            \BookMetadata.progress: "progress",
            \BookMetadata.sortableNarrator: "narrator",
            \BookMetadata.sortableTranslator: "translator",
            \BookMetadata.sortablePublicationYear: "publicationYear",
            \BookMetadata.sortableStatus: "status",
            \BookMetadata.sortableAdded: "added",
            \BookMetadata.sortableLastRead: "lastRead",
            \BookMetadata.sortableTags: "tags",
        ]

        guard let columnID = keyPathToColumn[comparator.keyPath],
              let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(columnID)) else {
            return
        }

        let image = comparator.order == .forward
            ? NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Ascending")
            : NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Descending")
        tableView.setIndicatorImage(image, in: column)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: MediaTableView
        var items: [BookMetadata]
        var coverPreference: CoverPreference
        var mediaViewModel: MediaViewModel
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        init(parent: MediaTableView, mediaViewModel: MediaViewModel) {
            self.parent = parent
            self.items = parent.items
            self.coverPreference = parent.coverPreference
            self.mediaViewModel = mediaViewModel
            super.init()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let columnID = tableColumn?.identifier.rawValue, row < items.count else { return nil }
            let item = items[row]
            let cellID = NSUserInterfaceItemIdentifier("\(columnID)Cell")

            switch columnID {
            case "cover":
                return makeCoverCell(tableView: tableView, cellID: cellID, item: item)
            case "title":
                return makeTitleCell(tableView: tableView, cellID: cellID, item: item)
            case "author":
                let name = item.authors?.first?.name ?? ""
                let target: MetadataLinkTarget? = name.isEmpty ? nil : .author(name)
                return makeLinkTextCell(tableView: tableView, cellID: cellID, text: name, linkTarget: target)
            case "series":
                return makeSeriesCell(tableView: tableView, cellID: cellID, item: item)
            case "progress":
                return makeProgressCell(tableView: tableView, cellID: cellID, item: item)
            case "narrator":
                let name = item.narrators?.first?.name ?? ""
                let target: MetadataLinkTarget? = name.isEmpty ? nil : .narrator(name)
                return makeLinkTextCell(tableView: tableView, cellID: cellID, text: name, linkTarget: target)
            case "translator":
                let name = item.sortableTranslator
                let target: MetadataLinkTarget? = name.isEmpty ? nil : .translator(name)
                return makeLinkTextCell(tableView: tableView, cellID: cellID, text: name, linkTarget: target)
            case "publicationYear":
                let year = item.sortablePublicationYear
                let displayText = formatDate(item.publicationDate)
                let target: MetadataLinkTarget? = year.isEmpty ? nil : .publicationYear(year)
                return makeLinkTextCell(tableView: tableView, cellID: cellID, text: displayText, linkTarget: target)
            case "status":
                let statusName = item.status?.name ?? ""
                let target: MetadataLinkTarget? = statusName.isEmpty ? nil : .status(statusName)
                return makeLinkTextCell(tableView: tableView, cellID: cellID, text: statusName, linkTarget: target)
            case "added":
                return makeTextCell(tableView: tableView, cellID: cellID, text: formatDate(item.createdAt), secondary: true)
            case "lastRead":
                return makeTextCell(tableView: tableView, cellID: cellID, text: formatDate(item.position?.updatedAt), secondary: true)
            case "tags":
                return makeTagsCell(tableView: tableView, cellID: cellID, item: item)
            case "media":
                return makeMediaCell(tableView: tableView, cellID: cellID, item: item)
            default:
                return nil
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key else { return }

            let order: SortOrder = descriptor.ascending ? .forward : .reverse

            switch key {
            case "title":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.title, order: order)]
            case "author":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableAuthor, order: order)]
            case "series":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableSeries, order: order)]
            case "progress":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.progress, order: order)]
            case "narrator":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableNarrator, order: order)]
            case "translator":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableTranslator, order: order)]
            case "publicationYear":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortablePublicationYear, order: order)]
            case "status":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableStatus, order: order)]
            case "added":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableAdded, order: order)]
            case "lastRead":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableLastRead, order: order)]
            case "tags":
                parent.sortOrder = [KeyPathComparator(\BookMetadata.sortableTags, order: order)]
            default:
                break
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 && selectedRow < items.count {
                let item = items[selectedRow]
                parent.selection = item.id
                parent.onSelect(item)
            } else {
                parent.selection = nil
            }
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return true
        }

        func handleRowClicked(_ row: Int) {
            guard row >= 0 && row < items.count else { return }
            let item = items[row]
            parent.onInfo(item)
        }

        func handleLinkClicked(_ target: MetadataLinkTarget) {
            parent.onMetadataLinkClicked?(target)
        }

        func tableViewColumnDidMove(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let order = tableView.tableColumns.map { $0.identifier.rawValue }
            MediaTableView.saveColumnOrder(order)
        }

        private func makeCoverCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let coverVariant = resolveCoverVariant(for: item)

            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? HostingCellView
                ?? HostingCellView(identifier: cellID)
            let content = CoverCellContent(
                item: item,
                coverVariant: coverVariant,
                mediaViewModel: mediaViewModel
            )
            cell.setContent(content)
            return cell
        }

        private func makeTitleCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let stackedCellID = NSUserInterfaceItemIdentifier("titleStackedCell")
            let cell = tableView.makeView(withIdentifier: stackedCellID, owner: self) as? TitleAuthorCellView
                ?? TitleAuthorCellView(identifier: stackedCellID)
            cell.configure(title: item.title, author: item.authors?.first?.name)
            return cell
        }

        private func makeTextCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, text: String, secondary: Bool) -> NSView {
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? TextCellView
                ?? TextCellView(identifier: cellID)
            cell.configure(text: text, secondary: secondary)
            return cell
        }

        private func makeLinkTextCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, text: String, linkTarget: MetadataLinkTarget?) -> NSView {
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? LinkTextCellView
                ?? LinkTextCellView(identifier: cellID)
            cell.configure(text: text, linkTarget: linkTarget)
            return cell
        }

        private func makeSeriesCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? SeriesCellView
                ?? SeriesCellView(identifier: cellID)
            cell.configure(series: item.series?.first)
            return cell
        }

        private func makeProgressCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? ProgressCellView
                ?? ProgressCellView(identifier: cellID)
            let progress = mediaViewModel.progress(for: item.id)
            cell.configure(progress: progress)
            return cell
        }

        private func makeTagsCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? HostingCellView
                ?? HostingCellView(identifier: cellID)
            let onLinkClicked = parent.onMetadataLinkClicked
            let content = TagFlowCellContent(
                tags: item.tagNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                onTagClicked: onLinkClicked != nil ? { tag in onLinkClicked?(.tag(tag)) } : nil
            )
            cell.setContent(content)
            return cell
        }

        private func makeMediaCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? HostingCellView
                ?? HostingCellView(identifier: cellID)
            let content = MediaIndicatorCellContent(item: item, mediaViewModel: mediaViewModel)
            cell.setContent(content)
            return cell
        }

        private func resolveCoverVariant(for item: BookMetadata) -> MediaViewModel.CoverVariant {
            switch coverPreference {
            case .preferEbook:
                if item.hasAvailableEbook { return .standard }
                return item.hasAvailableAudiobook ? .audioSquare : .standard
            case .preferAudiobook:
                if item.hasAvailableAudiobook || item.isAudiobookOnly { return .audioSquare }
                return .standard
            }
        }

        private func formatDate(_ dateString: String?) -> String {
            guard let dateString, !dateString.isEmpty else { return "" }
            return DateFormatterCache.shared.format(dateString)
        }
    }
}

private final class TextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(text: String, secondary: Bool) {
        label.stringValue = text
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.font = .systemFont(ofSize: 13)
    }
}

private final class LinkTextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    var linkTarget: MetadataLinkTarget?
    private var trackingArea: NSTrackingArea?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(text: String, linkTarget: MetadataLinkTarget?) {
        label.stringValue = text
        self.linkTarget = linkTarget
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if linkTarget != nil {
            NSCursor.pointingHand.push()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if linkTarget != nil {
            NSCursor.pop()
        }
    }
}

private final class TitleAuthorCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()
    var authorLinkTarget: MetadataLinkTarget?
    private var trackingArea: NSTrackingArea?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor

        authorLabel.lineBreakMode = .byTruncatingTail
        authorLabel.maximumNumberOfLines = 1
        authorLabel.font = .systemFont(ofSize: 11)
        authorLabel.textColor = .secondaryLabelColor

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 1
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(authorLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(title: String, author: String?) {
        titleLabel.stringValue = title
        authorLabel.stringValue = author ?? ""
        authorLabel.isHidden = author?.isEmpty ?? true
        if let author, !author.isEmpty {
            authorLinkTarget = .author(author)
        } else {
            authorLinkTarget = nil
        }
    }

    func authorLabelContainsPoint(_ pointInCell: NSPoint) -> Bool {
        guard !authorLabel.isHidden, authorLinkTarget != nil else { return false }
        let pointInStack = stackView.convert(pointInCell, from: self)
        return authorLabel.frame.contains(pointInStack)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if authorLabelContainsPoint(point) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

private final class SeriesCellView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()
    var linkTarget: MetadataLinkTarget?
    private var trackingArea: NSTrackingArea?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.textColor = .secondaryLabelColor

        positionLabel.lineBreakMode = .byClipping
        positionLabel.maximumNumberOfLines = 1
        positionLabel.textColor = .tertiaryLabelColor

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(nameLabel)
        stackView.addArrangedSubview(positionLabel)
        addSubview(stackView)

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        positionLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(series: BookSeries?) {
        if let series {
            nameLabel.stringValue = series.name
            nameLabel.font = .systemFont(ofSize: 13)
            nameLabel.textColor = .secondaryLabelColor
            linkTarget = .series(series.name)
            if let formatted = series.formattedPosition {
                positionLabel.stringValue = "#\(formatted)"
                positionLabel.font = .systemFont(ofSize: 11)
                positionLabel.isHidden = false
            } else {
                positionLabel.isHidden = true
            }
        } else {
            nameLabel.stringValue = ""
            nameLabel.textColor = .secondaryLabelColor
            linkTarget = nil
            positionLabel.isHidden = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if linkTarget != nil {
            NSCursor.pointingHand.push()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if linkTarget != nil {
            NSCursor.pop()
        }
    }
}

private final class ProgressCellView: NSTableCellView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let percentLabel = NSTextField(labelWithString: "")
    private var currentProgress: Double = 0

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        trackLayer.cornerRadius = 2
        trackLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        layer?.addSublayer(trackLayer)

        fillLayer.cornerRadius = 2
        fillLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        layer?.addSublayer(fillLayer)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)

        NSLayoutConstraint.activate([
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 32),
        ])
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let barHeight: CGFloat = 4
        let barWidth = bounds.width - 48
        let y = (bounds.height - barHeight) / 2
        trackLayer.frame = CGRect(x: 4, y: y, width: barWidth, height: barHeight)
        fillLayer.frame = CGRect(x: 4, y: y, width: barWidth * currentProgress, height: barHeight)
        CATransaction.commit()
    }

    func configure(progress: Double) {
        currentProgress = min(max(progress, 0), 1)
        percentLabel.stringValue = "\(Int(currentProgress * 100))%"
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        let barHeight: CGFloat = 4
        trackLayer.cornerRadius = barHeight / 2
        fillLayer.cornerRadius = barHeight / 2

        needsLayout = true
    }
}

private struct CoverCellContent: View {
    let item: BookMetadata
    let coverVariant: MediaViewModel.CoverVariant
    let mediaViewModel: MediaViewModel

    private let height: CGFloat = 40

    var body: some View {
        let coverState = mediaViewModel.coverState(for: item, variant: coverVariant)
        let width = height * coverVariant.preferredAspectRatio

        ZStack {
            Color(white: 0.2)
            if let image = coverState.image {
                image
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .task(id: coverVariant) {
            mediaViewModel.ensureCoverLoaded(for: item, variant: coverVariant)
        }
    }
}

private final class HostingCellView: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent<V: View>(_ view: V) {
        if let existingHostingView = hostingView {
            existingHostingView.rootView = AnyView(view)
        } else {
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hostingView = hosting
        }
    }
}

private final class TagLayoutState: @unchecked Sendable {
    var visibleCount: Int = 0
}

private struct TagFlowCellContent: View {
    let tags: [String]
    var onTagClicked: ((String) -> Void)?
    @State private var showPopover = false
    @State private var layoutState = TagLayoutState()

    private var hiddenTags: [String] {
        let count = layoutState.visibleCount
        guard count < tags.count else { return [] }
        return Array(tags.suffix(from: count))
    }

    var body: some View {
        TagFlowLayout(spacing: 4, maxRows: 2, state: layoutState) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                if let onTagClicked {
                    Button {
                        onTagClicked(tag)
                    } label: {
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
                } else {
                    Text(tag)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            }
            Text("\u{2026}")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.25)))
                .layoutValue(key: IsOverflowIndicator.self, value: true)
                .onHover { showPopover = $0 }
                .popover(isPresented: $showPopover) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hiddenTags, id: \.self) { tag in
                            Text(tag).font(.system(size: 12))
                        }
                    }
                    .padding(8)
                }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct IsOverflowIndicator: LayoutValueKey {
    static let defaultValue = false
}

private struct TagFlowLayout: Layout {
    var spacing: CGFloat
    var maxRows: Int
    var state: TagLayoutState

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computeLayout(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(in: bounds.width, subviews: subviews)
        state.visibleCount = result.visibleCount
        for (i, subview) in subviews.enumerated() {
            if let pos = result.placements[i] {
                let ideal = subview.sizeThatFits(.unspecified)
                let cappedWidth = min(ideal.width, bounds.width)
                subview.place(
                    at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                    proposal: ProposedViewSize(width: cappedWidth, height: ideal.height)
                )
            } else {
                subview.place(at: CGPoint(x: bounds.minX - 10000, y: 0), proposal: .init(width: 0, height: 0))
            }
        }
    }

    private struct ItemInfo {
        let index: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let row: Int
    }

    private struct LayoutResult {
        var size: CGSize
        var placements: [Int: CGPoint]
        var visibleCount: Int
    }

    private func computeLayout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        var overflowIndex: Int?
        var regularIndices: [Int] = []
        for (i, subview) in subviews.enumerated() {
            if subview[IsOverflowIndicator.self] {
                overflowIndex = i
            } else {
                regularIndices.append(i)
            }
        }

        let overflowSize = overflowIndex.map { subviews[$0].sizeThatFits(.unspecified) } ?? .zero

        var items: [ItemInfo] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var currentRow = 0

        for idx in regularIndices {
            let ideal = subviews[idx].sizeThatFits(.unspecified)
            let size = CGSize(width: min(ideal.width, maxWidth), height: ideal.height)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                currentRow += 1
            }
            items.append(ItemInfo(index: idx, x: x, y: y, width: size.width, height: size.height, row: currentRow))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalRows = (items.last?.row ?? -1) + 1
        let hasOverflow = totalRows > maxRows

        if !hasOverflow {
            var placements: [Int: CGPoint] = [:]
            var maxW: CGFloat = 0
            for item in items {
                placements[item.index] = CGPoint(x: item.x, y: item.y)
                maxW = max(maxW, item.x + item.width)
            }
            let h = items.last.map { $0.y + $0.height } ?? 0
            return LayoutResult(size: CGSize(width: maxW, height: h), placements: placements, visibleCount: items.count)
        }

        var visible = items.filter { $0.row < maxRows }

        if overflowIndex != nil {
            while let last = visible.last, last.row == maxRows - 1 {
                let afterLast = last.x + last.width + spacing
                if afterLast + overflowSize.width <= maxWidth { break }
                visible.removeLast()
            }
        }

        var placements: [Int: CGPoint] = [:]
        var maxW: CGFloat = 0
        for item in visible {
            placements[item.index] = CGPoint(x: item.x, y: item.y)
            maxW = max(maxW, item.x + item.width)
        }

        if let oi = overflowIndex {
            let ox: CGFloat
            let oy: CGFloat
            if let last = visible.last {
                ox = last.x + last.width + spacing
                oy = last.y
            } else {
                ox = 0
                oy = 0
            }
            placements[oi] = CGPoint(x: ox, y: oy)
            maxW = max(maxW, ox + overflowSize.width)
        }

        let h = visible.last.map { $0.y + $0.height } ?? overflowSize.height
        return LayoutResult(size: CGSize(width: maxW, height: h), placements: placements, visibleCount: visible.count)
    }
}

private struct MediaIndicatorCellContent: View {
    let item: BookMetadata
    let mediaViewModel: MediaViewModel

    @Environment(\.openWindow) private var openWindow
    @State private var hoveredType: MediaType?
    @State private var showConnectionAlert = false

    private let iconSize: CGFloat = 20
    private let smallIconSize: CGFloat = 16
    private let readaloudSize: CGFloat = 18
    private let buttonSize: CGFloat = 28

    private var hasConnectionError: Bool {
        if mediaViewModel.lastNetworkOpSucceeded == false { return true }
        if case .error = mediaViewModel.connectionStatus { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 6) {
            mediaButton(for: .ebook)
            mediaButton(for: .audio)
            mediaButton(for: .synced)
        }
        .padding(.horizontal, 4)
        .alert("Connection Error", isPresented: $showConnectionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cannot download media while disconnected from the server.")
        }
    }

    private enum MediaType: CaseIterable {
        case ebook, audio, synced

        var category: LocalMediaCategory {
            switch self {
            case .ebook: return .ebook
            case .audio: return .audio
            case .synced: return .synced
            }
        }

        var iconName: String {
            switch self {
            case .ebook: return "book.fill"
            case .audio: return "headphones"
            case .synced: return "text.bubble"
            }
        }
    }

    private enum MediaStatus: Equatable {
        case unavailable
        case availableNotDownloaded
        case downloaded
        case downloading(progress: Double?)

        var color: Color {
            switch self {
            case .unavailable: return .gray.opacity(0.3)
            case .availableNotDownloaded: return .blue
            case .downloaded: return .green
            case .downloading: return .blue
            }
        }
    }

    private func mediaStatus(for type: MediaType) -> MediaStatus {
        let category = type.category

        if mediaViewModel.isCategoryDownloadInProgress(for: item, category: category) {
            let progress = mediaViewModel.downloadProgressFraction(for: item, category: category)
            return .downloading(progress: progress)
        }

        if mediaViewModel.isCategoryDownloaded(category, for: item) {
            return .downloaded
        }

        let available: Bool
        switch type {
        case .ebook: available = item.hasAvailableEbook
        case .audio: available = item.hasAvailableAudiobook
        case .synced: available = item.hasAvailableReadaloud
        }

        return available ? .availableNotDownloaded : .unavailable
    }

    @ViewBuilder
    private func mediaButton(for type: MediaType) -> some View {
        let status = mediaStatus(for: type)
        let isHovered = hoveredType == type

        Button {
            handleTap(for: type, status: status)
        } label: {
            ZStack {
                if case .downloading(let progress) = status {
                    if isHovered {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: iconSize))
                    } else if let progress {
                        ZStack {
                            Circle()
                                .stroke(status.color.opacity(0.3), lineWidth: 2.5)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(status.color, lineWidth: 2.5)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: iconSize, height: iconSize)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if isHovered && status == .availableNotDownloaded {
                    if hasConnectionError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: smallIconSize))
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: iconSize))
                    }
                } else if isHovered && status == .downloaded {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: iconSize))
                } else {
                    if type == .synced {
                        ReadaloudIcon(size: readaloudSize)
                    } else {
                        Image(systemName: type.iconName)
                            .font(.system(size: smallIconSize))
                    }
                }
            }
            .foregroundStyle(status.color)
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status == .unavailable)
        .onHover { hovering in
            hoveredType = hovering ? type : nil
        }
        .contextMenu {
            if status == .downloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: type.category)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func handleTap(for type: MediaType, status: MediaStatus) {
        let category = type.category

        switch status {
        case .availableNotDownloaded:
            if hasConnectionError {
                showConnectionAlert = true
            } else {
                mediaViewModel.startDownload(for: item, category: category)
            }
        case .downloaded:
            openMedia(for: category)
        case .downloading:
            mediaViewModel.cancelDownload(for: item, category: category)
        case .unavailable:
            break
        }
    }

    private func openMedia(for category: LocalMediaCategory) {
        guard #available(macOS 13.0, *) else { return }
        let windowID: String
        switch category {
        case .audio:
            windowID = "AudiobookPlayer"
        case .ebook, .synced:
            windowID = "EbookPlayer"
        }
        let path = mediaViewModel.localMediaPath(for: item.id, category: category)
        let variant: MediaViewModel.CoverVariant = item.hasAvailableAudiobook ? .audioSquare : .standard
        let cover = mediaViewModel.coverImage(for: item, variant: variant)
        let ebookCover = item.hasAvailableAudiobook
            ? mediaViewModel.coverImage(for: item, variant: .standard)
            : nil
        let bookData = PlayerBookData(
            metadata: item,
            localMediaPath: path,
            category: category,
            coverArt: cover,
            ebookCoverArt: ebookCover
        )
        openWindow(id: windowID, value: bookData)
    }
}

@MainActor
private final class DateFormatterCache {
    static let shared = DateFormatterCache()

    private let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoWithoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private let fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    private var cache: [String: String] = [:]

    func format(_ dateString: String) -> String {
        if let cached = cache[dateString] { return cached }

        let parsedDate =
            isoWithFractional.date(from: dateString)
            ?? isoWithoutFractional.date(from: dateString)
            ?? fallbackFormatter.date(from: dateString)

        let formatted = parsedDate.map { displayFormatter.string(from: $0) } ?? dateString
        cache[dateString] = formatted
        return formatted
    }
}
#endif
