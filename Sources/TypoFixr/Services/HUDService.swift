import AppKit
import SwiftUI

class HUDService {
    static let shared = HUDService()
    
    private var hudWindow: NSWindow?
    private var dismissTimer: Timer?
    private static let defaultBottomMargin: CGFloat = 28
    private static let defaultHorizontalSafetyMargin: CGFloat = 12
    
    private init() {}
    
    /// Show the HUD with the specified content
    /// - Parameters:
    ///   - title: Main status text
    ///   - subtitle: Secondary status text
    ///   - isSuccess: Whether this is a success (green) or error (red) state
    ///   - duration: How long to show the HUD before auto-dismissing (default 2 seconds)
    func show(title: String, subtitle: String, isSuccess: Bool, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMainThread(title: title, subtitle: subtitle, isSuccess: isSuccess, duration: duration)
        }
    }

    func showLoading(title: String, subtitle: String) {
        DispatchQueue.main.async { [weak self] in
            self?.showLoadingOnMainThread(title: title, subtitle: subtitle)
        }
    }

    private func showOnMainThread(title: String, subtitle: String, isSuccess: Bool, duration: TimeInterval) {
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

        presentHUDView(AnyView(hudView))

        // Schedule auto-dismiss
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

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

        presentHUDView(AnyView(hudView))
        // No auto-dismiss — loading HUD stays until replaced
    }

    private func presentHUDView(_ view: AnyView) {
        // Create or reuse the window
        if hudWindow == nil {
            hudWindow = createHUDWindow()
        }

        guard let window = hudWindow else { return }

        // Update the content
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)

        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)

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
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.hudWindow?.orderOut(nil)
        })
    }
    
    private func createHUDWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false // We use SwiftUI shadow instead
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
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

    static func hudOrigin(
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
