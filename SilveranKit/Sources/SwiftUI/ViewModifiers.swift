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

    init(expandRight: Bool, expandLeft: Bool, rightAmount: CGFloat, leftAmount: CGFloat, savedWidthKey: String? = nil) {
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

            if !coordinator.initialized {
                coordinator.initialized = true
                coordinator.lastExpandedRight = expandRight
                coordinator.lastExpandedLeft = expandLeft
                setupResizeObserver(window: window, coordinator: coordinator)

                if let key = savedWidthKey,
                   let savedWidth = UserDefaults.standard.object(forKey: key) as? CGFloat,
                   savedWidth > 0,
                   window.frame.width != savedWidth {
                    var frame = window.frame
                    frame.size.width = savedWidth
                    window.setFrame(frame, display: true, animate: false)
                }
                return
            }

            var frame = window.frame
            var needsUpdate = false

            if expandRight != coordinator.lastExpandedRight {
                if expandRight {
                    frame.size.width += rightAmount
                } else {
                    frame.size.width -= rightAmount
                }
                coordinator.lastExpandedRight = expandRight
                needsUpdate = true
            }

            if expandLeft != coordinator.lastExpandedLeft {
                if expandLeft {
                    frame.size.width += leftAmount
                    frame.origin.x -= leftAmount
                } else {
                    frame.size.width -= leftAmount
                    frame.origin.x += leftAmount
                }
                coordinator.lastExpandedLeft = expandLeft
                needsUpdate = true
            }

            if needsUpdate {
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
            UserDefaults.standard.set(window.frame.width, forKey: key)
        }
    }

    class Coordinator {
        var initialized = false
        var lastExpandedRight = false
        var lastExpandedLeft = false
        var resizeObserver: Any?
        weak var window: NSWindow?
        var rightAmount: CGFloat = 0
        var leftAmount: CGFloat = 0

        deinit {
            if let observer = resizeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            guard let window else { return }
            var frame = window.frame
            if lastExpandedRight { frame.size.width -= rightAmount }
            if lastExpandedLeft {
                frame.size.width -= leftAmount
                frame.origin.x += leftAmount
            }
            if lastExpandedRight || lastExpandedLeft {
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
#endif
