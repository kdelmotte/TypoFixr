import AppKit
import SwiftUI

class HUDService {
    static let shared = HUDService()
    
    private var hudWindow: NSWindow?
    private var dismissTimer: Timer?
    
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
        
        // Create or reuse the window
        if hudWindow == nil {
            hudWindow = createHUDWindow()
        }
        
        guard let window = hudWindow else { return }
        
        // Update the content
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
        
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
        
        // Position the window near the mouse cursor
        positionWindow(window)
        
        // Show with fade-in animation
        window.alphaValue = 0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
        
        // Schedule auto-dismiss
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
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
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        // Top-right corner with padding
        let x = screenFrame.maxX - windowSize.width - 20
        let y = screenFrame.maxY - windowSize.height - 20

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
