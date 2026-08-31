import AppKit

@MainActor
final class SlideThumbnailSidebar: NSView,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSCollectionViewDelegateFlowLayout
{
    var onSelectIndex: ((Int) -> Void)?
    private(set) var itemCount = 0
    private(set) var currentSelection: Int?

    private struct Slide {
        let title: String
        var image: NSImage?
    }

    private static let itemIdentifier = NSUserInterfaceItemIdentifier(
        "SlideThumbnailCollectionItem"
    )

    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let emptyLabel = NSTextField(labelWithString: "No slides")
    private var slides: [Slide] = []
    private var deckVersion: Int64?
    private var isApplyingSelection = false
    private var lastLayoutWidth: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupInterface()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateSlides(titles: [String], deckVersion: Int64) {
        guard self.deckVersion != deckVersion
                || slides.map(\.title) != titles else {
            return
        }

        clearCollectionSelection()
        self.deckVersion = deckVersion
        slides = titles.map { Slide(title: $0, image: nil) }
        itemCount = slides.count
        currentSelection = nil
        collectionView.reloadData()
        updateEmptyState()
    }

    func setThumbnail(
        _ image: NSImage,
        at index: Int,
        deckVersion: Int64
    ) {
        guard self.deckVersion == deckVersion,
              slides.indices.contains(index) else {
            return
        }
        slides[index].image = image
        updateVisibleItem(at: index)
    }

    func select(index: Int, scrollToVisible: Bool) {
        guard slides.indices.contains(index) else { return }
        let oldSelection = currentSelection
        currentSelection = index
        let path = IndexPath(item: index, section: 0)

        isApplyingSelection = true
        if let oldSelection, oldSelection != index {
            collectionView.deselectItems(
                at: [IndexPath(item: oldSelection, section: 0)]
            )
        }
        collectionView.selectItems(
            at: [path],
            scrollPosition: scrollToVisible ? .centeredVertically : []
        )
        isApplyingSelection = false

        if let oldSelection, oldSelection != index {
            updateVisibleItem(at: oldSelection)
        }
        updateVisibleItem(at: index)
    }

    func clear() {
        clearCollectionSelection()
        deckVersion = nil
        slides.removeAll(keepingCapacity: true)
        itemCount = 0
        currentSelection = nil
        collectionView.reloadData()
        updateEmptyState()
    }

    override func layout() {
        super.layout()
        let width = scrollView.contentView.bounds.width
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        flowLayout.invalidateLayout()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        slides.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: Self.itemIdentifier,
            for: indexPath
        )
        guard let item = item as? SlideThumbnailCollectionItem,
              slides.indices.contains(indexPath.item) else {
            return item
        }
        let slide = slides[indexPath.item]
        item.onActivate = { [weak self] index in
            self?.activate(index: index, updateCollectionSelection: true)
        }
        item.configure(
            index: indexPath.item,
            title: slide.title,
            image: slide.image,
            selected: currentSelection == indexPath.item
        )
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard !isApplyingSelection,
              let path = indexPaths.first,
              slides.indices.contains(path.item) else {
            return
        }
        activate(index: path.item, updateCollectionSelection: false)
    }

    private func activate(index: Int, updateCollectionSelection: Bool) {
        guard slides.indices.contains(index) else { return }
        let oldSelection = currentSelection
        currentSelection = index
        if updateCollectionSelection {
            let path = IndexPath(item: index, section: 0)
            isApplyingSelection = true
            collectionView.deselectItems(at: collectionView.selectionIndexPaths)
            collectionView.selectItems(at: [path], scrollPosition: [])
            isApplyingSelection = false
        }
        if let oldSelection, oldSelection != index {
            updateVisibleItem(at: oldSelection)
        }
        updateVisibleItem(at: index)
        onSelectIndex?(index)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let viewportWidth = collectionView.enclosingScrollView?.contentSize.width
            ?? collectionView.bounds.width
        let itemWidth = max(
            1,
            viewportWidth - flowLayout.sectionInset.left
                - flowLayout.sectionInset.right
        )
        let imageWidth = itemWidth - SlideThumbnailCollectionItem.horizontalInset * 2
        let itemHeight = SlideThumbnailCollectionItem.verticalChromeHeight
            + imageWidth * 9 / 16
        return NSSize(width: itemWidth, height: itemHeight)
    }

    private func setupInterface() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        flowLayout.scrollDirection = .vertical
        flowLayout.minimumLineSpacing = 8
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = NSEdgeInsets(
            top: 10,
            left: 10,
            bottom: 10,
            right: 10
        )

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            SlideThumbnailCollectionItem.self,
            forItemWithIdentifier: Self.itemIdentifier
        )
        collectionView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(frame.width, 1),
            height: max(frame.height, 1)
        )
        collectionView.autoresizingMask = [.width]

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 16
            ),
            emptyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -16
            )
        ])
        updateEmptyState()
    }

    private func updateEmptyState() {
        let isEmpty = slides.isEmpty
        emptyLabel.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }

    private func clearCollectionSelection() {
        isApplyingSelection = true
        collectionView.deselectItems(at: collectionView.selectionIndexPaths)
        isApplyingSelection = false
    }

    private func updateVisibleItem(at index: Int) {
        guard slides.indices.contains(index),
              let item = collectionView.item(
                  at: IndexPath(item: index, section: 0)
              ) as? SlideThumbnailCollectionItem else {
            return
        }
        let slide = slides[index]
        item.configure(
            index: index,
            title: slide.title,
            image: slide.image,
            selected: currentSelection == index
        )
    }
}

@MainActor
final class SlideThumbnailCollectionItem: NSCollectionViewItem {
    static let horizontalInset: CGFloat = 8
    static let verticalChromeHeight: CGFloat = 47

    private let imageContainer = NSView()
    private let thumbnailImageView = NSImageView()
    private let placeholderView = NSView()
    private let pageLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private(set) var representedSlideIndex: Int?
    var onActivate: ((Int) -> Void)?

    var displayedImage: NSImage? {
        thumbnailImageView.image
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func loadView() {
        let root = AccessibleThumbnailView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 7
        root.layer?.borderWidth = 1
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.button)
        root.onPress = { [weak self] in
            guard let self, let index = self.representedSlideIndex else { return }
            self.onActivate?(index)
        }

        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 4
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        imageContainer.setAccessibilityElement(false)
        imageContainer.translatesAutoresizingMaskIntoConstraints = false

        placeholderView.wantsLayer = true
        placeholderView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        placeholderView.setAccessibilityElement(false)
        placeholderView.translatesAutoresizingMaskIntoConstraints = false

        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.setAccessibilityElement(false)
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .right
        pageLabel.setAccessibilityElement(false)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setAccessibilityElement(false)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        imageContainer.addSubview(placeholderView)
        imageContainer.addSubview(thumbnailImageView)
        root.addSubview(imageContainer)
        root.addSubview(pageLabel)
        root.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: Self.horizontalInset
            ),
            imageContainer.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -Self.horizontalInset
            ),
            imageContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            imageContainer.heightAnchor.constraint(
                equalTo: imageContainer.widthAnchor,
                multiplier: 9 / 16
            ),
            placeholderView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            thumbnailImageView.leadingAnchor.constraint(
                equalTo: imageContainer.leadingAnchor
            ),
            thumbnailImageView.trailingAnchor.constraint(
                equalTo: imageContainer.trailingAnchor
            ),
            thumbnailImageView.topAnchor.constraint(
                equalTo: imageContainer.topAnchor
            ),
            thumbnailImageView.bottomAnchor.constraint(
                equalTo: imageContainer.bottomAnchor
            ),
            pageLabel.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: Self.horizontalInset
            ),
            pageLabel.topAnchor.constraint(
                equalTo: imageContainer.bottomAnchor,
                constant: 6
            ),
            pageLabel.widthAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(
                equalTo: pageLabel.trailingAnchor,
                constant: 7
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -Self.horizontalInset
            ),
            titleLabel.firstBaselineAnchor.constraint(
                equalTo: pageLabel.firstBaselineAnchor
            )
        ])
        view = root
        updateSelectionAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedSlideIndex = nil
        onActivate = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
        placeholderView.isHidden = false
        pageLabel.stringValue = ""
        titleLabel.stringValue = ""
        view.setAccessibilityLabel(nil)
        isSelected = false
    }

    @MainActor
    private final class AccessibleThumbnailView: NSView {
        var onPress: (() -> Void)?

        override func accessibilityPerformPress() -> Bool {
            guard let onPress else { return false }
            onPress()
            return true
        }
    }

    func configure(
        index: Int,
        title: String,
        image: NSImage?,
        selected: Bool
    ) {
        loadViewIfNeeded()
        let displayTitle = title.isEmpty ? "(Untitled)" : title
        representedSlideIndex = index
        thumbnailImageView.image = image
        thumbnailImageView.isHidden = image == nil
        placeholderView.isHidden = image != nil
        pageLabel.stringValue = "\(index + 1)"
        titleLabel.stringValue = displayTitle
        view.setAccessibilityLabel("Slide \(index + 1): \(displayTitle)")
        isSelected = selected
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        view.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        view.layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        view.layer?.borderWidth = isSelected ? 2 : 1
        titleLabel.textColor = isSelected ? .controlAccentColor : .labelColor
        view.setAccessibilitySelected(isSelected)
    }
}
