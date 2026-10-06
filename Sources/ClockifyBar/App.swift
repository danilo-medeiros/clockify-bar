import AppKit
import Combine
import SwiftUI

@main
enum ClockifyBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TrackerModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var syncTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        model.onStarted = { [weak self] in self?.popover.performClose(nil) }
        subscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        updateIcon()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        Task {
            await model.restore()
            if model.showSettings || model.error != nil { openPopover() }
        }
    }

    @objc private func clicked() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            openPopover()
            Task { await model.refresh(includeHistory: true) }
        }
    }

    @objc private func wokeUp() {
        Task { await model.refresh(force: true) }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let isRunning = model.running != nil
        if !model.statusKnown, model.connected {
            button.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Clockify status unknown")
            button.image?.isTemplate = true
        } else if isRunning {
            // Non-template drawing preserves red in both light and dark menu bars.
            let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: "Clockify tracking")?
                .withSymbolConfiguration(.init(paletteColors: [.white]))
            let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: rect).fill()
                if let symbol {
                    let scale = min(16 / symbol.size.width, 16 / symbol.size.height)
                    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                    symbol.draw(in: NSRect(x: (rect.width - size.width) / 2,
                                           y: (rect.height - size.height) / 2,
                                           width: size.width, height: size.height))
                }
                return true
            }
            image.isTemplate = false
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Clockify idle")
            button.image?.isTemplate = true
        }
        let state = !model.statusKnown && model.connected ? "Status unknown — click to refresh"
            : isRunning ? "Tracking: \(model.running!.title) — click to open" : "Not tracking — click to open"
        button.toolTip = model.busy ? "Syncing with Clockify…" : state
        button.setAccessibilityLabel("Clockify Bar: " + state)
        button.alphaValue = model.busy ? 0.5 : 1
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
