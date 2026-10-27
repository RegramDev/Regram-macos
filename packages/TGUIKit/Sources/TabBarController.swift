import Cocoa
import AppKit

private class TabBarViewController : View {
    let tabView:TabBarView
    private let accessory = ImageButton()
    var presentation = TabBarPresentation() {
        didSet {
            tabView.showsLabels = presentation.showsLabels
            tabView.externalTabIndex = presentation.externalTabIndex
            accessory.isHidden = presentation.accessoryAction == nil || tabView.isHidden
            if let image = presentation.accessoryImage { accessory.set(image: image, for: .Normal) }
            accessory.setAccessibilityLabel(presentation.accessoryTitle)
            accessory.toolTip = presentation.accessoryTitle
            needsLayout = true
        }
    }
    private let tabShadowView = EdgeEffectView()
    private var shadowColor = PresentationTheme.current.colors.listBackground

    
    required init(frame frameRect: NSRect) {
        tabView = TabBarView(frame: FloatingTabBarLayout.frame(in: frameRect.size))
        super.init(frame: frameRect)
        tabShadowView.isEventLess = true
        addSubview(tabShadowView)
        addSubview(tabView)
        accessory.isHidden = true
        accessory.scaleOnClick = true
        accessory.set(handler: { [weak self] _ in self?.presentation.accessoryAction?() }, for: .Click)
        addSubview(accessory)
        updateShadow()
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.background = .clear
        shadowColor = theme.colors.listBackground
        updateShadow()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        let tabFrame = presentation.frame(in: frame.size, count: tabView.count)
        transition.updateFrame(view: tabView, frame: tabFrame)
        accessory.isHidden = presentation.accessoryAction == nil || tabView.isHidden
        transition.updateFrame(view: accessory, frame: NSMakeRect(tabFrame.maxX + 8, tabFrame.minY, presentation.height, presentation.height))
        accessory.layer?.cornerRadius = presentation.height / 2
        for subview in subviews where subview !== tabView && subview !== accessory && subview !== tabShadowView {
            transition.updateFrame(view: subview, frame: frame.size.bounds)
        }
        updateShadow(transition: transition)
    }

    func addContentView(_ view: NSView) {
        addSubview(view, positioned: .below, relativeTo: tabShadowView)
    }

    func updateShadow(transition: ContainedViewLayoutTransition = .immediate) {
        let minY = max(0, tabView.frame.minY - 24)
        let rect = NSRect(x: 0, y: minY, width: bounds.width, height: max(0, bounds.height - minY))
        transition.updateFrame(view: tabShadowView, frame: rect)
        tabShadowView.isHidden = tabView.isHidden || tabView.isEmpty
        tabShadowView.update(color: shadowColor, alpha: 0.6, edge: .top, edgeSize: min(60, rect.height), rect: rect, transition: transition)
    }

    override func layout() {
        super.layout()
        updateFrame(frame, transition: .immediate)
    }
}

public class TabBarController: ViewController, TabViewDelegate {

    
    public var didChangedIndex:(Int)->Void = {_ in}
    public var selectedIndex: Int {
        return genericView.tabView.selectedIndex
    }
    public var contentBottomInset: CGFloat {
        return genericView.tabView.isHidden ? 0 : genericView.presentation.height + FloatingTabBarLayout.bottomGap
    }
    
    public weak var current:ViewController? {
        didSet {
            current?.navigationController = self.navigationController
        }
    }
    
    public override var navigationController: NavigationViewController? {
        didSet {
            current?.navigationController = self.navigationController
        }
    }
    
    public override var redirectUserInterfaceCalls: Bool {
        return true
    }
    
    private var genericView:TabBarViewController {
        return view as! TabBarViewController
    }
    
    public override func viewClass() -> AnyClass {
        return TabBarViewController.self
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        genericView.tabView.enumerateItems({ item in
            if item.controller.isLoaded() {
                item.controller.updateLocalizationAndTheme(theme: theme)
            }
            return false
        })
    }
    
    public override func loadView() {
        super.loadView()
        genericView.tabView.delegate = self
        genericView.autoresizingMask = []
    }
    
    public func didChange(selected item: TabItem, index: Int) {
        
        let animated = current != nil
        
        if current != item.controller {
            if let current = current {
                _ = current.window?.makeFirstResponder(nil)
                current.viewWillDisappear(false)
                if animated {
                    current.view.layer?.animateAlpha(from: 1, to: 0, duration: 0.15, removeOnCompletion: false, completion: { [weak self, weak current] _ in
                        if self?.current !== current {
                            current?.view.removeFromSuperview()
                        }
                    })
                } else {
                    current.view.removeFromSuperview()
                }
                current.viewDidDisappear(false)
            }
            item.controller._frameRect = bounds
            item.controller.view.frame = item.controller._frameRect
            item.controller.view.layer?.removeAnimation(forKey: "opacity")
            item.controller.updateContainerContentInsets(contentInsetsForTabs, transition: .immediate)
            item.controller.viewWillAppear(false)
            genericView.addContentView(item.controller.view)
            if animated {
                item.controller.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.15)
            }
            item.controller.viewDidAppear(false)
            current = item.controller
            didChangedIndex(index)
        }
    }
    
    public func updatePresentation(_ presentation: TabBarPresentation) {
        let previousBottomInset = contentBottomInset
        genericView.presentation = presentation
        genericView.updateFrame(bounds, transition: .immediate)
        guard contentBottomInset != previousBottomInset else { return }
        genericView.tabView.enumerateItems { item in
            item.controller.updateContainerContentInsets(self.contentInsetsForTabs, transition: .immediate)
            return false
        }
    }

    public func scrollup() {
        current?.scrollup()
    }
    
    public func control(for index: Int) -> Control {
        return self.genericView.tabView.control(for: index)
    }
    
    public func hideTabView(_ hide:Bool) {
        genericView.tabView.isHidden = hide
        genericView.needsLayout = true
        genericView.updateShadow()
        current?.view.frame = bounds
        genericView.tabView.enumerateItems { item in
            item.controller.updateContainerContentInsets(self.contentInsetsForTabs, transition: .immediate)
            return false
        }
    }

    private var contentInsetsForTabs: NSEdgeInsets {
        var insets = containerContentInsets
        insets.bottom += contentBottomInset
        return insets
    }

    public override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        guard isLoaded() else {
            return
        }
        genericView.tabView.enumerateItems { item in
            item.controller.updateContainerContentInsets(self.contentInsetsForTabs, transition: transition)
            return false
        }
    }
    
    public override func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        super.updateFrame(frame, transition: transition)
        self.genericView.updateFrame(frame, transition: transition)
    }
    
    public func select(index:Int) -> Void {
        guard (0 ..< count).contains(index) else {
            return
        }
        if index != self.genericView.tabView.selectedIndex || current !== tab(at: index).controller {
            genericView.tabView.setSelectedIndex(index, respondToDelegate: true, animated: true)
        }
    }
    
    public var count: Int {
        return genericView.tabView.count
    }
    
    public func add(tab:TabItem) -> Void {
        genericView.tabView.addTab(tab)
        genericView.updateShadow()
        tab.controller.updateContainerContentInsets(contentInsetsForTabs, transition: .immediate)
    }
    public func tab(at index:Int) -> TabItem {
        return genericView.tabView.tab(at: index)
    }
    public func replace(tab: TabItem, at index:Int) -> Void {
        if tab.accessibilityTitle == nil, (0 ..< count).contains(index), self.tab(at: index).controller === tab.controller {
            tab.accessibilityTitle = self.tab(at: index).accessibilityTitle
        }
        genericView.tabView.replaceTab(tab, at: index)
    }
    public func insert(tab: TabItem, at index: Int) -> Void {
        genericView.tabView.insertTab(tab, at: index)
        genericView.updateShadow()
        tab.controller.updateContainerContentInsets(contentInsetsForTabs, transition: .immediate)
    }
    public func remove(at index: Int) -> Void {
        genericView.tabView.removeTab(at: index)
        genericView.updateShadow()
    }
    public var isEmpty:Bool {
        return genericView.tabView.isEmpty
    }
    public func showTooltip(text: String, for index: Int) -> Void {
        genericView.tabView.showTooltip(text: text, for: index)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.current?.viewWillAppear(animated)
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.current?.viewDidAppear(animated)
    }
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.current?.viewWillDisappear(animated)
    }
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.current?.viewDidDisappear(animated)
    }
}
