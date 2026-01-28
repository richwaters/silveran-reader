#if os(macOS)
import SwiftUI
import AppKit

private final class ImmediateSelectTableView: NSTableView {
    var onRowClicked: ((Int) -> Void)?
    private var lastFittedWidth: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        if clickedRow >= 0 {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        let coordinator = context.coordinator
        let oldItems = coordinator.items
        let newItems = items

        coordinator.parent = self
        coordinator.items = items
        coordinator.coverPreference = coverPreference
        coordinator.mediaViewModel = mediaViewModel

        if oldItems.map(\.id) != newItems.map(\.id) {
            tableView.reloadData()
        } else if oldItems != newItems {
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
                return makeTextCell(tableView: tableView, cellID: cellID, text: item.authors?.first?.name ?? "", secondary: true)
            case "series":
                return makeSeriesCell(tableView: tableView, cellID: cellID, item: item)
            case "progress":
                return makeProgressCell(tableView: tableView, cellID: cellID, item: item)
            case "narrator":
                return makeTextCell(tableView: tableView, cellID: cellID, text: item.narrators?.first?.name ?? "", secondary: true)
            case "translator":
                return makeTextCell(tableView: tableView, cellID: cellID, text: item.sortableTranslator, secondary: true)
            case "publicationYear":
                return makeTextCell(tableView: tableView, cellID: cellID, text: formatDate(item.publicationDate), secondary: true)
            case "status":
                return makeTextCell(tableView: tableView, cellID: cellID, text: item.status?.name ?? "", secondary: true)
            case "added":
                return makeTextCell(tableView: tableView, cellID: cellID, text: formatDate(item.createdAt), secondary: true)
            case "lastRead":
                return makeTextCell(tableView: tableView, cellID: cellID, text: formatDate(item.position?.updatedAt), secondary: true)
            case "tags":
                return makeTextCell(tableView: tableView, cellID: cellID, text: item.sortableTags, secondary: true)
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

        func tableViewColumnDidMove(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let order = tableView.tableColumns.map { $0.identifier.rawValue }
            MediaTableView.saveColumnOrder(order)
        }

        private func makeCoverCell(tableView: NSTableView, cellID: NSUserInterfaceItemIdentifier, item: BookMetadata) -> NSView {
            let height: CGFloat = 40
            let coverVariant = resolveCoverVariant(for: item)
            let aspectRatio = coverVariant.preferredAspectRatio
            let width = height * aspectRatio

            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? CoverCellView
                ?? CoverCellView(identifier: cellID)

            let coverState = mediaViewModel.coverState(for: item, variant: coverVariant)
            cell.configure(image: coverState.nsImage, width: width, height: height)

            if coverState.nsImage == nil {
                mediaViewModel.ensureCoverLoaded(for: item, variant: coverVariant)
            }

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

private final class TitleAuthorCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()

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
    }
}

private final class SeriesCellView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()

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
            if let position = series.position {
                positionLabel.stringValue = "#\(position)"
                positionLabel.font = .systemFont(ofSize: 11)
                positionLabel.isHidden = false
            } else {
                positionLabel.isHidden = true
            }
        } else {
            nameLabel.stringValue = ""
            positionLabel.isHidden = true
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

private final class CoverCellView: NSTableCellView {
    private let coverImageView = NSImageView()
    private let backgroundLayer = CALayer()
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        layer?.masksToBounds = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundLayer.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        backgroundLayer.cornerRadius = 3
        backgroundLayer.masksToBounds = true
        layer?.addSublayer(backgroundLayer)

        coverImageView.imageScaling = .scaleProportionallyDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.cornerRadius = 3
        coverImageView.layer?.masksToBounds = true
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverImageView)

        NSLayoutConstraint.activate([
            coverImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            coverImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = coverImageView.frame
        CATransaction.commit()
    }

    func configure(image: NSImage?, width: CGFloat, height: CGFloat) {
        coverImageView.image = image

        widthConstraint?.isActive = false
        heightConstraint?.isActive = false
        widthConstraint = coverImageView.widthAnchor.constraint(equalToConstant: width)
        heightConstraint = coverImageView.heightAnchor.constraint(equalToConstant: height)
        widthConstraint?.isActive = true
        heightConstraint?.isActive = true

        needsLayout = true
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
