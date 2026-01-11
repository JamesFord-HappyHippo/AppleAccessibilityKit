import Foundation
import AppKit

// MARK: - Core Accessibility Tree Walker

/// Low-level AXUIElement tree walker
/// Extracts all content from any application's UI hierarchy
@MainActor
public class AccessibilityTreeWalker {

    public init() {}

    // MARK: - Public API

    /// Read the focused window of the frontmost application
    public func readFocusedWindow() -> AccessibilityWindowContent? {
        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard appResult == .success, let focusedApp = focusedApp else { return nil }

        let appElement = focusedApp as! AXUIElement

        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard windowResult == .success, let focusedWindow = focusedWindow else { return nil }

        let windowElement = focusedWindow as! AXUIElement
        var content = walkTree(windowElement)

        // Add app context
        content.applicationName = getApplicationName() ?? "Unknown"
        content.windowTitle = getWindowTitle(windowElement) ?? ""

        return content
    }

    /// Read all windows for a specific application
    public func readAllWindows(bundleIdentifier: String) -> [AccessibilityWindowContent] {
        var allContent: [AccessibilityWindowContent] = []

        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard app.bundleIdentifier == bundleIdentifier else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            var windowsRef: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

            if let windows = windowsRef as? [AXUIElement] {
                for window in windows {
                    var content = walkTree(window)
                    content.applicationName = app.localizedName ?? bundleIdentifier
                    content.windowTitle = getWindowTitle(window) ?? ""
                    allContent.append(content)
                }
            }
        }

        return allContent
    }

    /// Read a specific AXUIElement
    public func read(element: AXUIElement) -> AccessibilityWindowContent {
        return walkTree(element)
    }

    // MARK: - Tree Walking

    /// Recursive tree walker - extracts ALL content from UI hierarchy
    private func walkTree(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 50) -> AccessibilityWindowContent {
        var content = AccessibilityWindowContent()

        guard depth < maxDepth else { return content }

        let elementData = extractAttributes(element)
        content.elements.append(elementData)

        // Collect text content
        if let value = elementData.value, !value.isEmpty {
            content.textContent.append(value)
        }
        if let title = elementData.title, !title.isEmpty {
            content.labels.append(title)
        }
        if let description = elementData.description, !description.isEmpty {
            content.labels.append(description)
        }

        // Special handling for text areas
        if let role = elementData.role {
            if role == "AXTextArea" || role == "AXTextField" || role == "AXStaticText" {
                if let textValue = elementData.value {
                    content.editableText.append(textValue)
                }
            }
        }

        // Recursively walk children
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)

        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                let childContent = walkTree(child, depth: depth + 1, maxDepth: maxDepth)

                content.elements.append(contentsOf: childContent.elements)
                content.textContent.append(contentsOf: childContent.textContent)
                content.labels.append(contentsOf: childContent.labels)
                content.editableText.append(contentsOf: childContent.editableText)
            }
        }

        return content
    }

    // MARK: - Attribute Extraction

    /// Extract 40+ accessibility attributes from a single element
    private func extractAttributes(_ element: AXUIElement) -> AccessibilityElement {
        var data = AccessibilityElement()

        data.role = getString(element, kAXRoleAttribute)
        data.subrole = getString(element, kAXSubroleAttribute)
        data.roleDescription = getString(element, kAXRoleDescriptionAttribute)
        data.title = getString(element, kAXTitleAttribute)
        data.value = getValue(element)
        data.description = getString(element, kAXDescriptionAttribute)
        data.help = getString(element, kAXHelpAttribute)

        data.isFocused = getBool(element, kAXFocusedAttribute)
        data.isEnabled = getBool(element, kAXEnabledAttribute)
        data.isMainWindow = getBool(element, kAXMainAttribute)
        data.isMinimized = getBool(element, kAXMinimizedAttribute)
        data.isHidden = getBool(element, kAXHiddenAttribute)

        data.position = getPoint(element, kAXPositionAttribute)
        data.size = getSize(element, kAXSizeAttribute)

        data.selectedText = getString(element, kAXSelectedTextAttribute)
        data.childCount = getChildCount(element)

        return data
    }

    // MARK: - Attribute Helpers

    private func getString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    private func getValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else { return nil }

        if let stringValue = value as? String {
            return stringValue
        } else if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        } else if let value = value {
            return String(describing: value)
        }

        return nil
    }

    private func getBool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let boolValue = value as? Bool else { return false }
        return boolValue
    }

    private func getPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }

        var point = CGPoint.zero
        if let axValue = value, AXValueGetValue(axValue as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    private func getSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }

        var size = CGSize.zero
        if let axValue = value, AXValueGetValue(axValue as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    private func getChildCount(_ element: AXUIElement) -> Int {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let children = childrenRef as? [AXUIElement] else { return 0 }
        return children.count
    }

    private func getApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func getWindowTitle(_ window: AXUIElement) -> String? {
        getString(window, kAXTitleAttribute)
    }
}
