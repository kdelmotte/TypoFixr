import AppKit
import SwiftUI

@MainActor
final class HUDService {
    static let shared = HUDService()
    
    private var hudWindow: NSWindow?
    private var dismissTimer: Timer?
    private var presentationID = UUID()
    private nonisolated static let defaultBottomMargin: CGFloat = 28
    private nonisolated static let defaultHorizontalSafetyMargin: CGFloat = 12
    
    private init() {}
    
    /// Show the HUD with the specified content
    /// - Parameters:
    ///   - title: Main status text
    ///   - subtitle: Secondary status text
    ///   - isSuccess: Whether this is a success (green) or error (red) state
    ///   - duration: How long to show the HUD before auto-dismissing (2.5 seconds for success; 5–10 seconds for errors)
    func show(title: String, subtitle: String, isSuccess: Bool, duration: TimeInterval? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMainThread(title: title, subtitle: subtitle, isSuccess: isSuccess, duration: duration)
        }
    }

    func showLoading(title: String, subtitle: String) {
        DispatchQueue.main.async { [weak self] in
            self?.showLoadingOnMainThread(title: title, subtitle: subtitle)
        }
    }

    @MainActor
    private func showOnMainThread(title: String, subtitle: String, isSuccess: Bool, duration: TimeInterval?) {
        // Cancel any existing dismiss timer
        dismissTimer?.invalidate()
        dismissTimer = nil

        // Determine the icon based on success/error state
        let icon = isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"

        // Create the SwiftUI view
        let hudView = HUDView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            isSuccess: isSuccess
        )

        presentHUDView(hudView)

        // Schedule auto-dismiss
        let scheduledID = presentationID
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration ?? Self.displayDuration(subtitle: subtitle, isSuccess: isSuccess), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.presentationID == scheduledID else { return }
                self.dismiss()
            }
        }
    }

    @MainActor
    private func showLoadingOnMainThread(title: String, subtitle: String) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        let hudView = HUDView(
            icon: "",
            title: title,
            subtitle: subtitle,
            isSuccess: true,
            isLoading: true
        )

        presentHUDView(hudView)
        // No auto-dismiss — loading HUD stays until replaced
    }

    nonisolated static func displayDuration(subtitle: String, isSuccess: Bool) -> TimeInterval {
        isSuccess ? 2.5 : min(10, max(5, Double(subtitle.count) / 18))
    }

    /// Measure at a known width before attaching to a reused window. Asking for
    /// fittingSize after attachment can measure already-compressed text.
    @MainActor
    static func makeHostingView(for view: HUDView, availableWidth: CGFloat) -> NSHostingView<AnyView> {
        let width = max(1, min(320, availableWidth - 24))
        let root = AnyView(view.frame(width: width))
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []
        let measured = controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.setFrameSize(NSSize(width: width, height: ceil(measured.height)))
        return hosting
    }

    @MainActor
    private func presentHUDView(_ view: HUDView) {
        presentationID = UUID()
        // Create or reuse the window
        if hudWindow == nil {
            hudWindow = Self.createHUDWindow()
        }

        guard let window = hudWindow else { return }

        // Update the content
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let hostingView = Self.makeHostingView(for: view, availableWidth: screen?.visibleFrame.width ?? 1440)
        let measuredSize = hostingView.frame.size
        window.contentView = hostingView
        window.setContentSize(measuredSize)

        // Position the window at the bottom-center of the display under the cursor
        positionWindow(window)

        // Show with fade-in animation
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
    }
    
    /// Dismiss the HUD with fade-out animation
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            self?.dismissOnMainThread()
        }
    }
    
    private func dismissOnMainThread() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        guard let window = hudWindow else { return }
        
        let dismissingID = presentationID
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentationID == dismissingID else { return }
                self.hudWindow?.orderOut(nil)
            }
        })
    }
    
    static func createHUDWindow() -> HUDPanel {
        let window = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true // Draw outside the content, without clipping the card.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true // Click-through
        
        return window
    }
    
    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen else { return }

        let origin = Self.hudOrigin(
            visibleFrame: targetScreen.visibleFrame,
            windowSize: window.frame.size,
            bottomMargin: Self.defaultBottomMargin,
            horizontalSafetyMargin: Self.defaultHorizontalSafetyMargin
        )
        window.setFrameOrigin(origin)
    }

    nonisolated static func hudOrigin(
        visibleFrame: CGRect,
        windowSize: CGSize,
        bottomMargin: CGFloat = defaultBottomMargin,
        horizontalSafetyMargin: CGFloat = defaultHorizontalSafetyMargin
    ) -> CGPoint {
        let centeredX = visibleFrame.minX + (visibleFrame.width - windowSize.width) / 2
        let minXWithMargin = visibleFrame.minX + horizontalSafetyMargin
        let maxXWithMargin = visibleFrame.maxX - windowSize.width - horizontalSafetyMargin

        let x: CGFloat
        if minXWithMargin <= maxXWithMargin {
            x = min(max(centeredX, minXWithMargin), maxXWithMargin)
        } else {
            let minX = visibleFrame.minX
            let maxX = visibleFrame.maxX - windowSize.width
            if minX <= maxX {
                x = min(max(centeredX, minX), maxX)
            } else {
                x = visibleFrame.minX
            }
        }

        let y = visibleFrame.minY + bottomMargin
        return CGPoint(x: round(x), y: round(y))
    }
}


final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
