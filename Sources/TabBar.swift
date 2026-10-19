import AppKit

/// The fixed tab-colour palette. Index `0` is "no colour" (`nil`); the rest map
/// to adaptive system colours so they read correctly in light and dark mode.
enum TabPalette {
    struct Entry {
        let name: String
        let color: NSColor?
    }

    static let entries: [Entry] = [
        Entry(name: "无颜色", color: nil),
        Entry(name: "红", color: .systemRed),
        Entry(name: "橙", color: .systemOrange),
        Entry(name: "黄", color: .systemYellow),
        Entry(name: "绿", color: .systemGreen),
        Entry(name: "薄荷", color: .systemMint),
        Entry(name: "蓝", color: .systemBlue),
        Entry(name: "靛蓝", color: .systemIndigo),
        Entry(name: "紫", color: .systemPurple),
        Entry(name: "粉", color: .systemPink),
        Entry(name: "灰", color: .systemGray),
    ]

    /// Out-of-range (including negative) indices clamp to `0`.
    static func normalized(_ index: Int) -> Int {
        (index >= 0 && index < entries.count) ? index : 0
    }

    static func color(at index: Int) -> NSColor? {
        entries[normalized(index)].color
    }

    static func name(at index: Int) -> String {
        entries[normalized(index)].name
    }
}

/// Events emitted by the tab bar. All indices are current at call time; the bar
/// reloads after the controller applies the change.
protocol TabBarDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, didSelect index: Int)
    func tabBar(_ bar: TabBarView, didClose index: Int)
    func tabBarDidRequestNewTab(_ bar: TabBarView)
    func tabBar(_ bar: TabBarView, didSetColor color: Int, at index: Int)
    func tabBar(_ bar: TabBarView, didRequestCloseOthers index: Int)
}

/// The 34pt bar at the top of the window: a horizontally scrolling strip of
/// `TabItemView`s plus a trailing "+" button.
final class TabBarView: NSView {
    static let barHeight: CGFloat = 34

    weak var delegate: TabBarDelegate?

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let addButton = NSButton()
    private var itemViews: [TabItemView] = []
    private var selectedIndex = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder

        // The stack is the documentView, laid out frame-based so it never
        // fights the clip view's own scrolling geometry. Its width grows with
        // the tabs; the scroll view scrolls it.
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stackView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.documentView = stackView

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.isBordered = false
        addButton.bezelStyle = .regularSquare
        addButton.setButtonType(.momentaryChange)
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签页")
        addButton.imagePosition = .imageOnly
        addButton.contentTintColor = .secondaryLabelColor
        addButton.focusRingType = .none
        addButton.target = self
        addButton.action = #selector(addClicked)

        addSubview(scrollView)
        addSubview(addButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 22),
            addButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        applyBarColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBarColor()
        itemViews.forEach { $0.refreshColors() }
    }

    private func applyBarColor() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    /// Rebuilds the strip from the controller's model. Called on add, close,
    /// select, colour change, title/URL change and restore.
    func reload(titles: [String], colors: [Int], selected: Int) {
        selectedIndex = selected
        for view in itemViews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        itemViews.removeAll()

        for (index, title) in titles.enumerated() {
            let item = TabItemView()
            item.title = title
            item.colorIndex = index < colors.count ? colors[index] : 0
            item.isSelectedTab = (index == selected)
            item.onSelect = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didSelect: index)
            }
            item.onClose = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didClose: index)
            }
            item.onSetColor = { [weak self] color in
                guard let self else { return }
                self.delegate?.tabBar(self, didSetColor: color, at: index)
            }
            item.onCloseOthers = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didRequestCloseOthers: index)
            }
            stackView.addArrangedSubview(item)
            itemViews.append(item)
        }

        layoutStrip()
        scrollSelectedIntoView()
    }

    private func layoutStrip() {
        let fitting = stackView.fittingSize
        stackView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(fitting.width, 1),
            height: max(fitting.height, Self.barHeight)
        )
        // Position the arranged subviews within the new frame before scrolling,
        // otherwise `scrollSelectedIntoView` sees stale item frames.
        stackView.layoutSubtreeIfNeeded()
    }

    private func scrollSelectedIntoView() {
        guard selectedIndex >= 0, selectedIndex < itemViews.count else { return }
        let item = itemViews[selectedIndex]
        item.scrollToVisible(item.bounds)
    }

    @objc private func addClicked() {
        delegate?.tabBarDidRequestNewTab(self)
    }
}

/// A single tab: colour dot, truncating title and a borderless close button.
/// Clicking selects; the close button closes without selecting; right-click
/// opens the colour / close context menu.
final class TabItemView: NSView {
    var title: String = "" {
        didSet { titleLabel.stringValue = title }
    }
    var colorIndex: Int = 0 {
        didSet { refreshColors() }
    }
    var isSelectedTab: Bool = false {
        didSet { refreshColors() }
    }

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onSetColor: ((Int) -> Void)?
    var onCloseOthers: (() -> Void)?

    private let dotView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 26) }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 5
        dotView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.setButtonType(.momentaryChange)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.focusRingType = .none
        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        addSubview(dotView)
        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            heightAnchor.constraint(equalToConstant: 26),
        ])

        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    fileprivate func refreshColors() {
        if isSelectedTab {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            titleLabel.textColor = .white
            closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = .labelColor
            closeButton.contentTintColor = .secondaryLabelColor
        }

        if let color = TabPalette.color(at: colorIndex) {
            dotView.isHidden = false
            dotView.layer?.backgroundColor = color.cgColor
        } else {
            // "无颜色": keep the slot but show nothing so titles stay aligned.
            dotView.isHidden = true
            dotView.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func colorClicked(_ sender: NSMenuItem) {
        onSetColor?(sender.tag)
    }

    @objc private func closeMenuClicked() {
        onClose?()
    }

    @objc private func closeOthersMenuClicked() {
        onCloseOthers?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let colorItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for (index, entry) in TabPalette.entries.enumerated() {
            let item = NSMenuItem(title: entry.name, action: #selector(colorClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = (index == colorIndex) ? .on : .off
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        let close = NSMenuItem(title: "关闭标签页", action: #selector(closeMenuClicked), keyEquivalent: "")
        close.target = self
        menu.addItem(close)

        let closeOthers = NSMenuItem(title: "关闭其他标签页", action: #selector(closeOthersMenuClicked), keyEquivalent: "")
        closeOthers.target = self
        menu.addItem(closeOthers)

        return menu
    }
}
