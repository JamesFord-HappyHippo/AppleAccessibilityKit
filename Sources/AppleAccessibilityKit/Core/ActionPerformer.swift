import Foundation
import AppKit

// MARK: - Action Performer

/// Perform actions on UI elements via Accessibility API
/// Click buttons, type text, select items, etc.
@MainActor
public class ActionPerformer {

    public init() {}

    // MARK: - Click Actions

    /// Click a button by its title
    public func clickButton(title: String, in bundleId: String? = nil) async -> Bool {
        guard let element = findElement(role: "AXButton", title: title, bundleId: bundleId) else {
            return false
        }
        return performAction(element, action: kAXPressAction)
    }

    /// Click at a specific position
    public func click(at point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        upEvent?.post(tap: .cghidEventTap)
    }

    /// Double-click at a specific position
    public func doubleClick(at point: CGPoint) {
        click(at: point)
        click(at: point)
    }

    /// Right-click at a specific position
    public func rightClick(at point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
        event?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        upEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Text Actions

    /// Type text into the focused element
    public func typeText(_ text: String) {
        for char in text {
            let keyCode = keyCodeFor(char)
            let shift = char.isUppercase || shiftRequired(char)

            if shift {
                // Press shift
                let shiftDown = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true)
                shiftDown?.post(tap: .cghidEventTap)
            }

            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            keyUp?.post(tap: .cghidEventTap)

            if shift {
                let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false)
                shiftUp?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Set text value on a specific text field
    public func setText(_ text: String, in element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    /// Clear and set text in focused text field
    public func clearAndType(_ text: String) {
        // Select all
        pressKey(.a, modifiers: [.command])
        // Delete
        pressKey(.delete)
        // Type new text
        typeText(text)
    }

    // MARK: - Keyboard Actions

    /// Press a key with optional modifiers
    public func pressKey(_ key: KeyCode, modifiers: [Modifier] = []) {
        // Press modifiers
        for modifier in modifiers {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: modifier.rawValue, keyDown: true)
            down?.post(tap: .cghidEventTap)
        }

        // Press key
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true)
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)

        // Release modifiers
        for modifier in modifiers.reversed() {
            let up = CGEvent(keyboardEventSource: nil, virtualKey: modifier.rawValue, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Press Enter/Return
    public func pressEnter() {
        pressKey(.return)
    }

    /// Press Escape
    public func pressEscape() {
        pressKey(.escape)
    }

    /// Press Tab
    public func pressTab() {
        pressKey(.tab)
    }

    // MARK: - Focus Actions

    /// Focus a specific element
    public func focus(_ element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        return result == .success
    }

    /// Focus window
    public func focusWindow(_ element: AXUIElement) -> Bool {
        return performAction(element, action: kAXRaiseAction)
    }

    // MARK: - Menu Actions

    /// Select a menu item by path (e.g., ["File", "Save"])
    public func selectMenuItem(path: [String], in bundleId: String? = nil) async -> Bool {
        guard let app = getApplication(bundleId: bundleId) else { return false }

        var menuBar: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar)
        guard let menuBar = menuBar as! AXUIElement? else { return false }

        var currentElement: AXUIElement = menuBar

        for menuName in path {
            guard let menuItem = findChild(of: currentElement, title: menuName) else {
                return false
            }

            // Open the menu
            performAction(menuItem, action: kAXPressAction)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s for menu to open

            // Get the menu's children
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(menuItem, kAXChildrenAttribute as CFString, &children)
            if let children = children as? [AXUIElement], let first = children.first {
                currentElement = first
            }
        }

        return true
    }

    // MARK: - Scroll Actions

    /// Scroll in the focused element
    public func scroll(deltaX: Int32 = 0, deltaY: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    /// Scroll up
    public func scrollUp(amount: Int32 = 100) {
        scroll(deltaY: amount)
    }

    /// Scroll down
    public func scrollDown(amount: Int32 = 100) {
        scroll(deltaY: -amount)
    }

    // MARK: - Helper Methods

    @discardableResult
    private func performAction(_ element: AXUIElement, action: String) -> Bool {
        let result = AXUIElementPerformAction(element, action as CFString)
        return result == .success
    }

    private func getApplication(bundleId: String?) -> AXUIElement? {
        if let bundleId = bundleId {
            let apps = NSWorkspace.shared.runningApplications
            if let app = apps.first(where: { $0.bundleIdentifier == bundleId }) {
                return AXUIElementCreateApplication(app.processIdentifier)
            }
            return nil
        } else {
            // Get frontmost app
            let systemWide = AXUIElementCreateSystemWide()
            var focusedApp: CFTypeRef?
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
            return focusedApp as! AXUIElement?
        }
    }

    private func findElement(role: String, title: String, bundleId: String?) -> AXUIElement? {
        guard let app = getApplication(bundleId: bundleId) else { return nil }

        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)

        guard let windows = windows as? [AXUIElement] else { return nil }

        for window in windows {
            if let found = findInTree(window, role: role, title: title) {
                return found
            }
        }

        return nil
    }

    private func findInTree(_ element: AXUIElement, role: String, title: String, depth: Int = 0) -> AXUIElement? {
        guard depth < 30 else { return nil }

        var elementRole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &elementRole)

        var elementTitle: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &elementTitle)

        if let r = elementRole as? String, let t = elementTitle as? String {
            if r == role && t.localizedCaseInsensitiveContains(title) {
                return element
            }
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if let children = children as? [AXUIElement] {
            for child in children {
                if let found = findInTree(child, role: role, title: title, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func findChild(of element: AXUIElement, title: String) -> AXUIElement? {
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        guard let children = children as? [AXUIElement] else { return nil }

        for child in children {
            var childTitle: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &childTitle)

            if let t = childTitle as? String, t.localizedCaseInsensitiveContains(title) {
                return child
            }
        }

        return nil
    }

    private func keyCodeFor(_ char: Character) -> CGKeyCode {
        let lower = char.lowercased().first ?? char
        let mapping: [Character: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
            "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            " ": 49, "`": 50
        ]
        return mapping[lower] ?? 0
    }

    private func shiftRequired(_ char: Character) -> Bool {
        let shiftChars: Set<Character> = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}", "|", ":", "\"", "<", ">", "?", "~"]
        return shiftChars.contains(char)
    }

    // MARK: - Key Codes

    public enum KeyCode: CGKeyCode {
        case `return` = 36
        case tab = 48
        case space = 49
        case delete = 51
        case escape = 53
        case a = 0
        case c = 8
        case v = 9
        case x = 7
        case z = 6
        case left = 123
        case right = 124
        case down = 125
        case up = 126
    }

    public enum Modifier: CGKeyCode {
        case command = 55
        case shift = 56
        case option = 58
        case control = 59
    }
}
