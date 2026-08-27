import AppKit
import Observation
import SwiftUI

/// Installs SwiftUI content in the titlebar segment aligned with the detail split column.
struct DetailColumnHeaderAccessory<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> DetailColumnHeaderInstallerView<Content> {
        DetailColumnHeaderInstallerView(content: content)
    }

    func updateNSView(
        _ nsView: DetailColumnHeaderInstallerView<Content>,
        context: Context
    ) {
        nsView.update(content: content)
    }

    static func dismantleNSView(
        _ nsView: DetailColumnHeaderInstallerView<Content>,
        coordinator: Void
    ) {
        nsView.uninstall()
    }
}

/// Keeps the hosting root stable so content updates do not relayout the AppKit titlebar.
@Observable
@MainActor
private final class DetailColumnHeaderModel<Content: View> {
    var content: Content
    var dividerThickness: CGFloat = 0
    var dividerColor: NSColor = .clear

    init(content: Content) {
        self.content = content
    }
}

private struct DetailColumnHeaderSurface<Content: View>: View {
    let model: DetailColumnHeaderModel<Content>

    var body: some View {
        HStack(spacing: 0) {
            NativeSplitViewDivider(color: model.dividerColor)
                .frame(width: model.dividerThickness)
            model.content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NativeSplitViewDivider: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> NativeSplitViewDividerView {
        NativeSplitViewDividerView(color: color)
    }

    func updateNSView(_ nsView: NativeSplitViewDividerView, context: Context) {
        nsView.color = color
    }
}

@MainActor
private final class NativeSplitViewDividerView: NSView {
    var color: NSColor {
        didSet {
            needsDisplay = true
        }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

struct DetailColumnHeaderTitle: View {
    let title: String
    let systemImage: String?

    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }
}

@MainActor
final class DetailColumnHeaderInstallerView<Content: View>: NSView {
    private var content: Content
    private var installationTask: Task<Void, Never>?
    private weak var installedWindow: NSWindow?
    private weak var observedSplitView: NSSplitView?
    private weak var detailPane: NSView?
    private var accessoryViewController: DetailColumnHeaderAccessoryViewController<Content>?

    init(content: Content) {
        self.content = content
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            uninstall()
        } else {
            scheduleInstallation()
        }
    }

    func update(content: Content) {
        self.content = content
        if let accessoryViewController {
            accessoryViewController.update(content: content)
        } else {
            scheduleInstallation()
        }
    }

    func uninstall() {
        installationTask?.cancel()
        installationTask = nil
        stopObservingSplitView()

        guard
            let installedWindow,
            let accessoryViewController,
            let index = installedWindow.titlebarAccessoryViewControllers.firstIndex(where: {
                $0 === accessoryViewController
            })
        else {
            self.installedWindow = nil
            self.accessoryViewController = nil
            return
        }

        installedWindow.removeTitlebarAccessoryViewController(at: index)
        self.installedWindow = nil
        self.accessoryViewController = nil
    }

    private func scheduleInstallation() {
        installationTask?.cancel()
        installationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.install()
        }
    }

    private func install() {
        guard let window, let (splitView, pane) = enclosingSplitPane() else { return }

        if window === installedWindow, let accessoryViewController {
            observe(splitView: splitView, detailPane: pane)
            accessoryViewController.update(content: content)
            updateAccessoryLayout()
            return
        }

        uninstall()
        removeStaleAccessoryController(from: window)

        let controller = DetailColumnHeaderAccessoryViewController(content: content)
        controller.setLayout(
            width: accessoryWidth(splitView: splitView, detailPane: pane),
            dividerThickness: splitView.dividerThickness,
            dividerColor: splitView.dividerColor
        )
        window.addTitlebarAccessoryViewController(controller)
        installedWindow = window
        accessoryViewController = controller
        observe(splitView: splitView, detailPane: pane)
    }

    private func removeStaleAccessoryController(from window: NSWindow) {
        for index in window.titlebarAccessoryViewControllers.indices.reversed()
        where window.titlebarAccessoryViewControllers[index]
            is any DetailColumnHeaderAccessoryController
        {
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }

    private func enclosingSplitPane() -> (NSSplitView, NSView)? {
        var ancestor = superview
        while let view = ancestor {
            if let splitView = view as? NSSplitView,
                let pane = splitView.subviews.first(where: { isDescendant(of: $0) })
            {
                return (splitView, pane)
            }
            ancestor = view.superview
        }
        return nil
    }

    private func observe(splitView: NSSplitView, detailPane: NSView) {
        guard splitView !== observedSplitView else {
            self.detailPane = detailPane
            return
        }

        stopObservingSplitView()
        observedSplitView = splitView
        self.detailPane = detailPane
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )
    }

    private func stopObservingSplitView() {
        if let observedSplitView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSSplitView.didResizeSubviewsNotification,
                object: observedSplitView
            )
        }
        observedSplitView = nil
        detailPane = nil
    }

    @objc private func splitViewDidResize(_: Notification) {
        updateAccessoryLayout()
    }

    private func updateAccessoryLayout() {
        guard let observedSplitView, let detailPane else { return }
        accessoryViewController?.setLayout(
            width: accessoryWidth(splitView: observedSplitView, detailPane: detailPane),
            dividerThickness: observedSplitView.dividerThickness,
            dividerColor: observedSplitView.dividerColor
        )
    }

    /// The split divider sits immediately before the detail pane rather than inside it.
    /// Include its native thickness so the titlebar separator shares the same coordinate.
    private func accessoryWidth(splitView: NSSplitView, detailPane: NSView) -> CGFloat {
        detailPane.bounds.width + splitView.dividerThickness
    }
}

@MainActor
private protocol DetailColumnHeaderAccessoryController: AnyObject {}

@MainActor
private final class DetailColumnHeaderAccessoryViewController<Content: View>:
    NSTitlebarAccessoryViewController,
    DetailColumnHeaderAccessoryController
{
    private let model: DetailColumnHeaderModel<Content>
    private let hostingView: NSHostingView<DetailColumnHeaderSurface<Content>>

    init(content: Content) {
        let model = DetailColumnHeaderModel(content: content)
        self.model = model
        hostingView = NSHostingView(rootView: DetailColumnHeaderSurface(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = hostingView
    }

    func setLayout(width: CGFloat, dividerThickness: CGFloat, dividerColor: NSColor) {
        hostingView.frame.size.width = max(0, width)
        model.dividerThickness = max(0, dividerThickness)
        model.dividerColor = dividerColor
    }

    func update(content: Content) {
        model.content = content
    }
}
