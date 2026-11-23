import AppKit
import ApplicationServices

let BUNDLE_ID = "io.github.vdasus.Dockus"
let DOCK_BUNDLE_ID = "com.apple.dock"
let DISABLED_KEY = "disabled"

// MARK: - Single instance

/// Takes an exclusive lock that the OS releases when the process ends, even after a crash.
func acquireInstanceLock() -> Bool {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(BUNDLE_ID)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fd = open(dir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return true } // cannot create the lock file: run rather than refuse to start
    return flock(fd, LOCK_EX | LOCK_NB) == 0 // fd stays open for the process lifetime to hold the lock
}

guard acquireInstanceLock() else { exit(0) }

let DEBUG = ProcessInfo.processInfo.environment["DOCKUS_DEBUG"] != nil

func debugLog(_ message: @autoclosure () -> String) {
    if DEBUG { FileHandle.standardError.write((message() + "\n").data(using: .utf8)!) }
}

// MARK: - Accessibility helpers

let systemWide = AXUIElementCreateSystemWide()

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func isMinimized(_ window: AXUIElement) -> Bool {
    (attribute(window, kAXMinimizedAttribute) as? Bool) == true
}

func setMinimized(_ window: AXUIElement, _ minimized: Bool) -> Bool {
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                 minimized ? kCFBooleanTrue : kCFBooleanFalse) == .success
}

func standardWindows(of pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return windows.filter { (attribute($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole }
}

/// The running application behind a Dock item, or nil if the item is not a running application.
func runningApplication(forDockItem item: AXUIElement) -> NSRunningApplication? {
    let apps = NSWorkspace.shared.runningApplications
    if let url = attribute(item, kAXURLAttribute) as? URL {
        let path = url.resolvingSymlinksInPath().path
        if let app = apps.first(where: { $0.bundleURL?.resolvingSymlinksInPath().path == path }) { return app }
    }
    // Fallback for apps whose bundle path differs from the Dock's URL (for example, Safari in a cryptex).
    guard let title = attribute(item, kAXTitleAttribute) as? String else { return nil }
    return apps.first { $0.activationPolicy == .regular && $0.localizedName == title }
}

// MARK: - Dock click handling

/// Returns true if Dockus handled the click and the Dock must not receive it.
func handleClick(at point: CGPoint) -> Bool {
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
          let item = hit else { return false }
    var pid: pid_t = 0
    guard AXUIElementGetPid(item, &pid) == .success,
          NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == DOCK_BUNDLE_ID,
          (attribute(item, kAXSubroleAttribute) as? String) == "AXApplicationDockItem",
          let app = runningApplication(forDockItem: item) else { return false }

    let windows = standardWindows(of: app.processIdentifier)
    let visible = windows.filter { !isMinimized($0) }
    debugLog("click: \(app.bundleIdentifier ?? "?") active=\(app.isActive) windows=\(windows.count) visible=\(visible.count)")
    guard !windows.isEmpty else { return false } // no windows: let the Dock open one

    if app.isActive && !visible.isEmpty {
        return visible.map { setMinimized($0, true) }.contains(true)
    }
    if visible.isEmpty {
        // Restore every window, then pass the click on so the Dock activates the app:
        // since macOS 14 one app cannot reliably activate another.
        windows.forEach { _ = setMinimized($0, false) }
        return false
    }
    return false // inactive app with visible windows: the Dock activates it
}

var eventTap: CFMachPort?
var swallowMouseUp = false
var isEnabled = !UserDefaults.standard.bool(forKey: DISABLED_KEY)

let eventCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .leftMouseDown:
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        if isEnabled, event.flags.intersection(modifiers).isEmpty, handleClick(at: event.location) {
            swallowMouseUp = true
            return nil
        }
    case .leftMouseUp:
        if swallowMouseUp {
            swallowMouseUp = false
            return nil
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

func installEventTap() -> Bool {
    let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask, callback: eventCallback, userInfo: nil) else { return false }
    eventTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
    return true
}

// MARK: - Launch at login

// shortcut: the LaunchAgent stores the current app path; moving the app breaks it until the toggle is set again.
let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(BUNDLE_ID).plist")

func isLaunchAtLoginEnabled() -> Bool { FileManager.default.fileExists(atPath: launchAgentURL.path) }

func setLaunchAtLogin(_ enabled: Bool) {
    if !enabled {
        try? FileManager.default.removeItem(at: launchAgentURL)
        return
    }
    let plist: [String: Any] = [
        "Label": BUNDLE_ID,
        "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
        "RunAtLoad": true,
    ]
    try? FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    (plist as NSDictionary).write(to: launchAgentURL, atomically: true)
}

// MARK: - Menu bar

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "dock.arrow.down.rectangle", accessibilityDescription: "Dockus") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "D"
            }
        }
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !(AXIsProcessTrustedWithOptions(options) && installEventTap()) {
            // Polls only until access is granted, then stops.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() && installEventTap() {
                    timer.invalidate()
                    self?.permissionTimer = nil
                }
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if eventTap == nil {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Enabled", #selector(toggleEnabled), state: isEnabled))
        menu.addItem(item("Launch at Login", #selector(toggleLaunchAtLogin), state: isLaunchAtLoginEnabled()))
        menu.addItem(.separator())
        menu.addItem(item("Quit Dockus", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, state: Bool? = nil, key: String = "",
                      target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let state { item.state = state ? .on : .off }
        return item
    }

    private func updateIcon() { statusItem.button?.appearsDisabled = !isEnabled }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        UserDefaults.standard.set(!isEnabled, forKey: DISABLED_KEY)
        updateIcon()
    }

    @objc private func toggleLaunchAtLogin() { setLaunchAtLogin(!isLaunchAtLoginEnabled()) }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

AXUIElementSetMessagingTimeout(systemWide, 0.5) // a hung app must not stall mouse input for long

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
