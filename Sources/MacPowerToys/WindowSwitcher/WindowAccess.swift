import AppKit
import ApplicationServices

/// AX references are only messaged on WindowAccess's serial queue.
struct SwitchableWindow: Identifiable, @unchecked Sendable {
    let id: String
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String
    let title: String
    let element: AXUIElement
    let stackingOrder: Int
}

struct WindowApplication: Sendable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String
}

struct WindowInventory: Sendable {
    var windows: [SwitchableWindow]
    var focusedID: String?
    var timedOut: Bool
}

final class WindowAccess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.macpowertoys.windows.accessibility", qos: .userInitiated)

    static func identity(_ window: AXUIElement, pid: pid_t) -> String { "\(pid):\(CFHash(window))" }

    func inventory(applications: [WindowApplication], frontPID: pid_t?) async -> WindowInventory {
        await withCheckedContinuation { continuation in
            queue.async {
                let deadline = ProcessInfo.processInfo.systemUptime + 2
                let visible = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
                var result: [SwitchableWindow] = []
                var focusedID: String?
                for app in applications {
                    if ProcessInfo.processInfo.systemUptime > deadline { break }
                    var candidates = visible.enumerated().compactMap { index, info -> (Int, CGRect)? in
                        guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.pid,
                              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                              let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 1, rect.height > 1 else { return nil }
                        return (index, rect)
                    }
                    guard !candidates.isEmpty else { continue }
                    let axApp = AXUIElementCreateApplication(app.pid)
                    AXUIElementSetMessagingTimeout(axApp, 0.15)
                    if app.pid == frontPID, let focused = Self.element(axApp, kAXFocusedWindowAttribute) {
                        focusedID = Self.identity(focused, pid: app.pid)
                    }
                    let windows = Self.value(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []
                    for window in windows {
                        if ProcessInfo.processInfo.systemUptime > deadline { break }
                        guard Self.value(window, kAXMinimizedAttribute) as? Bool != true,
                              let subrole = Self.value(window, kAXSubroleAttribute) as? String,
                              [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole),
                              let rect = Self.bounds(window),
                              let match = candidates.firstIndex(where: { Self.matches(rect, $0.1) }) else { continue }
                        let rank = candidates.remove(at: match).0
                        let title = Self.value(window, kAXTitleAttribute) as? String ?? ""
                        result.append(SwitchableWindow(id: Self.identity(window, pid: app.pid), pid: app.pid,
                            appName: app.name, bundleIdentifier: app.bundleIdentifier,
                            title: title.isEmpty ? "제목 없는 창" : title, element: window, stackingOrder: rank))
                    }
                }
                result.sort { $0.stackingOrder < $1.stackingOrder }
                continuation.resume(returning: WindowInventory(windows: result, focusedID: focusedID,
                    timedOut: ProcessInfo.processInfo.systemUptime > deadline))
            }
        }
    }

    func focusedID(pid: pid_t) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                let id = Self.element(app, kAXFocusedWindowAttribute).map { Self.identity($0, pid: pid) }
                continuation.resume(returning: id)
            }
        }
    }

    func raise(_ window: SwitchableWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                AXUIElementSetMessagingTimeout(window.element, 0.2)
                // A closed window must fail here rather than reopening its app.
                guard Self.value(window.element, kAXRoleAttribute) as? String == kAXWindowRole else {
                    continuation.resume(returning: false); return
                }
                let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
                if result == .success {
                    _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                }
                continuation.resume(returning: result == .success)
            }
        }
    }

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ app: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(app, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func bounds(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 3 && abs(lhs.minY - rhs.minY) < 3 &&
        abs(lhs.width - rhs.width) < 3 && abs(lhs.height - rhs.height) < 3
    }
}
