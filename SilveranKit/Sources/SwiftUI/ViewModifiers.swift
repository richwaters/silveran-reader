import SwiftUI

struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

#if os(macOS)
import AppKit

@MainActor
private final class WindowExpansionState {
    static let shared = WindowExpansionState()
    private var windowStates: [ObjectIdentifier: (right: CGFloat, left: CGFloat)] = [:]

    func getExpansion(for window: NSWindow) -> (right: CGFloat, left: CGFloat) {
        return windowStates[ObjectIdentifier(window)] ?? (0, 0)
    }

    func setExpansion(for window: NSWindow, right: CGFloat, left: CGFloat) {
        windowStates[ObjectIdentifier(window)] = (right, left)
    }
}

struct WindowFrameAdjuster: NSViewRepresentable {
    let expandRight: Bool
    let expandLeft: Bool
    let rightAmount: CGFloat
    let leftAmount: CGFloat
    let savedWidthKey: String?

    init(expandRight: Bool, rightAmount: CGFloat, savedWidthKey: String? = nil) {
        self.expandRight = expandRight
        self.expandLeft = false
        self.rightAmount = rightAmount
        self.leftAmount = 0
        self.savedWidthKey = savedWidthKey
    }

    init(
        expandRight: Bool,
        expandLeft: Bool,
        rightAmount: CGFloat,
        leftAmount: CGFloat,
        savedWidthKey: String? = nil
    ) {
        self.expandRight = expandRight
        self.expandLeft = expandLeft
        self.rightAmount = rightAmount
        self.leftAmount = leftAmount
        self.savedWidthKey = savedWidthKey
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }

            let coordinator = context.coordinator
            coordinator.window = window
            coordinator.rightAmount = rightAmount
            coordinator.leftAmount = leftAmount

            let sharedState = WindowExpansionState.shared
            let currentExpansion = sharedState.getExpansion(for: window)

            if !coordinator.initialized {
                coordinator.initialized = true
                coordinator.lastExpandedRight = expandRight
                coordinator.lastExpandedLeft = expandLeft
                setupResizeObserver(window: window, coordinator: coordinator)

                if let key = savedWidthKey,
                    let savedWidth = UserDefaults.standard.object(forKey: key) as? CGFloat,
                    savedWidth > 0
                {
                    let expectedWidth = savedWidth + currentExpansion.right + currentExpansion.left
                    if abs(window.frame.width - expectedWidth) > 1 {
                        var frame = window.frame
                        frame.size.width = expectedWidth
                        window.setFrame(frame, display: true, animate: false)
                    }
                }

                if expandRight && currentExpansion.right == 0 {
                    var frame = window.frame
                    frame.size.width += rightAmount
                    sharedState.setExpansion(
                        for: window,
                        right: rightAmount,
                        left: currentExpansion.left
                    )
                    window.setFrame(frame, display: true, animate: true)
                }
                if expandLeft && currentExpansion.left == 0 {
                    var frame = window.frame
                    frame.size.width += leftAmount
                    frame.origin.x -= leftAmount
                    sharedState.setExpansion(
                        for: window,
                        right: currentExpansion.right,
                        left: leftAmount
                    )
                    window.setFrame(frame, display: true, animate: true)
                }
                return
            }

            var frame = window.frame
            var needsUpdate = false
            var newRight = currentExpansion.right
            var newLeft = currentExpansion.left

            if expandRight != coordinator.lastExpandedRight {
                if expandRight && currentExpansion.right == 0 {
                    frame.size.width += rightAmount
                    newRight = rightAmount
                    needsUpdate = true
                } else if !expandRight && currentExpansion.right > 0 {
                    frame.size.width -= rightAmount
                    newRight = 0
                    needsUpdate = true
                }
                coordinator.lastExpandedRight = expandRight
            }

            if expandLeft != coordinator.lastExpandedLeft {
                if expandLeft && currentExpansion.left == 0 {
                    frame.size.width += leftAmount
                    frame.origin.x -= leftAmount
                    newLeft = leftAmount
                    needsUpdate = true
                } else if !expandLeft && currentExpansion.left > 0 {
                    frame.size.width -= leftAmount
                    frame.origin.x += leftAmount
                    newLeft = 0
                    needsUpdate = true
                }
                coordinator.lastExpandedLeft = expandLeft
            }

            if needsUpdate {
                sharedState.setExpansion(for: window, right: newRight, left: newLeft)
                window.setFrame(frame, display: true, animate: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func setupResizeObserver(window: NSWindow, coordinator: Coordinator) {
        guard let key = savedWidthKey, coordinator.resizeObserver == nil else { return }

        coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if window.contentView?.inLiveResize == true {
                    return
                }
                let expansion = WindowExpansionState.shared.getExpansion(for: window)
                guard expansion.right == 0 && expansion.left == 0 else { return }
                UserDefaults.standard.set(window.frame.width, forKey: key)
            }
        }

        coordinator.resizeEndObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let expansion = WindowExpansionState.shared.getExpansion(for: window)
                guard expansion.right == 0 && expansion.left == 0 else { return }
                UserDefaults.standard.set(window.frame.width, forKey: key)
            }
        }
    }

    class Coordinator {
        var initialized = false
        var lastExpandedRight = false
        var lastExpandedLeft = false
        var resizeObserver: Any?
        var resizeEndObserver: Any?
        weak var window: NSWindow?
        var rightAmount: CGFloat = 0
        var leftAmount: CGFloat = 0

        deinit {
            if let observer = resizeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = resizeEndObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            guard let window else { return }

            let capturedWindow = window
            let capturedLastExpandedRight = lastExpandedRight
            let capturedLastExpandedLeft = lastExpandedLeft
            let capturedRightAmount = rightAmount
            let capturedLeftAmount = leftAmount

            DispatchQueue.main.async {
                let sharedState = WindowExpansionState.shared
                let currentExpansion = sharedState.getExpansion(for: capturedWindow)
                var frame = capturedWindow.frame
                var newRight = currentExpansion.right
                var newLeft = currentExpansion.left
                var needsUpdate = false

                if capturedLastExpandedRight && currentExpansion.right > 0 {
                    frame.size.width -= capturedRightAmount
                    newRight = 0
                    needsUpdate = true
                }
                if capturedLastExpandedLeft && currentExpansion.left > 0 {
                    frame.size.width -= capturedLeftAmount
                    frame.origin.x += capturedLeftAmount
                    newLeft = 0
                    needsUpdate = true
                }
                if needsUpdate {
                    sharedState.setExpansion(for: capturedWindow, right: newRight, left: newLeft)
                    capturedWindow.setFrame(frame, display: true, animate: false)
                }
            }
        }
    }
}
#endif
