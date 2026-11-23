// End-to-end test driver. Opens its own windows, clicks its own Dock icon with synthetic mouse events
// and checks what happened to the windows.
// Usage: DockusE2E <baseline|dockus> <result file>
//   baseline: Dockus is not running; the click must leave the windows alone.
//   dockus:   Dockus is running; the first click must minimize all windows, the second must restore them.
import AppKit

let PHASE = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dockus"
let RESULT_PATH = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/dockus-e2e-result"

func log(_ message: String) {
    print(message)
    fflush(stdout)
}

func finish(_ result: String) -> Never {
    log(result)
    try? (result + "\n").write(toFile: RESULT_PATH, atomically: true, encoding: .utf8)
    exit(result == "PASS" ? 0 : 1)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func pump(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

func waitFor(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        pump(0.1)
    }
    return condition()
}

func dockItemCenter(title: String) -> CGPoint? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
    for list in attribute(dockElement, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        for item in attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? []
        where (attribute(item, kAXTitleAttribute) as? String) == title {
            var position = CGPoint.zero, size = CGSize.zero
            guard let p = attribute(item, kAXPositionAttribute), let s = attribute(item, kAXSizeAttribute),
                  AXValueGetValue(p as! AXValue, .cgPoint, &position),
                  AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
            return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        }
    }
    return nil
}

func click(at point: CGPoint) {
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        pump(0.15)
    }
}

final class Driver: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AXIsProcessTrusted() else { finish("FAIL: test driver has no Accessibility access") }

        for i in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: 200 + i * 60, y: 300 + i * 60, width: 400, height: 250),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Dockus E2E \(i + 1)"
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard waitFor(10, { NSApp.isActive }) else { finish("FAIL: test driver did not become active") }
        pump(1)

        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DockusE2E"
        var point: CGPoint?
        _ = waitFor(10) { point = dockItemCenter(title: name); return point != nil }
        guard let target = point else { finish("FAIL: Dock item '\(name)' not found") }
        log("Dock item '\(name)' at \(target)")

        let allVisible = { self.windows.allSatisfy { !$0.isMiniaturized && $0.isVisible } }
        let allMinimized = { self.windows.allSatisfy { $0.isMiniaturized } }

        if PHASE == "baseline" {
            click(at: target)
            pump(2)
            guard allVisible() else { finish("FAIL: without Dockus the click changed the windows") }
            finish("PASS")
        }

        guard let dockus = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.vdasus.Dockus").first
        else { finish("FAIL: Dockus is not running") }
        let extras = attribute(AXUIElementCreateApplication(dockus.processIdentifier), kAXExtrasMenuBarAttribute)
        let statusItems = extras.flatMap { attribute($0 as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] } ?? []
        guard !statusItems.isEmpty else { finish("FAIL: Dockus has no menu bar item") }
        log("Dockus menu bar items: \(statusItems.count)")

        click(at: target)
        guard waitFor(5, allMinimized) else { finish("FAIL: first click did not minimize all windows") }
        log("First click minimized all windows")

        click(at: target)
        guard waitFor(5, { allVisible() && NSApp.isActive }) else {
            let minimized = windows.filter { $0.isMiniaturized }.count
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
            finish("FAIL: second click: \(minimized) of \(windows.count) windows minimized, active=\(NSApp.isActive), frontmost=\(front)")
        }
        log("Second click restored all windows")

        let modifierDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left)
        modifierDown?.flags = .maskCommand
        modifierDown?.post(tap: .cghidEventTap)
        let modifierUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left)
        modifierUp?.flags = .maskCommand
        modifierUp?.post(tap: .cghidEventTap)
        pump(2)
        guard windows.allSatisfy({ !$0.isMiniaturized }) else { finish("FAIL: Cmd-click minimized windows") }
        log("Cmd-click passed to the Dock")

        finish("PASS")
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 120) { finish("FAIL: timeout") }
let app = NSApplication.shared
let driver = Driver()
app.delegate = driver
app.setActivationPolicy(.regular)
app.run()
