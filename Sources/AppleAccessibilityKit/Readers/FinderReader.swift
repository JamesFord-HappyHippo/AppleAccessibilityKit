import Foundation
import AppKit

// MARK: - Finder Reader

/// Specialized reader for macOS Finder
@MainActor
public class FinderReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.apple.finder"

    public init() {}

    // MARK: - Public API

    /// Get currently selected files/folders
    public func selectedItems() async -> [FinderItem] {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return []
        }

        return parseSelectedItems(from: content)
    }

    /// Get current directory path
    public func currentPath() async -> String? {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        // Window title often contains path
        let title = content.windowTitle

        // Check for path in toolbar/path bar
        for element in content.elements {
            if element.role == "AXStaticText" || element.role == "AXButton" {
                if let value = element.value ?? element.title {
                    if value.hasPrefix("/") || value.hasPrefix("~") {
                        return value
                    }
                }
            }
        }

        // Fall back to window title
        return title.isEmpty ? nil : title
    }

    /// Get all visible items in current directory
    public func visibleItems() async -> [FinderItem] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var items: [FinderItem] = []

        for window in windows {
            items.append(contentsOf: parseItems(from: window))
        }

        return items
    }

    /// Get sidebar favorites
    public func sidebarItems() async -> [String] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var sidebar: [String] = []

        for window in windows {
            for element in window.elements {
                // Sidebar items are in outline/source list
                if element.role == "AXOutlineRow" || element.role == "AXCell" {
                    if let title = element.title, !title.isEmpty {
                        sidebar.append(title)
                    }
                }
            }
        }

        return sidebar
    }

    /// Check if a file/folder is visible
    public func isVisible(_ name: String) async -> Bool {
        let items = await visibleItems()
        return items.contains { $0.name.localizedCaseInsensitiveContains(name) }
    }

    /// Get info about currently focused item
    public func focusedItem() async -> FinderItem? {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        for element in content.elements {
            if element.isFocused {
                var item = FinderItem()
                item.name = element.title ?? element.value ?? ""
                item.isSelected = true
                return item.name.isEmpty ? nil : item
            }
        }

        return nil
    }

    /// Check if Finder is frontmost
    public func isFinderActive() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    // MARK: - Parsing

    private func parseSelectedItems(from content: AccessibilityWindowContent) -> [FinderItem] {
        var items: [FinderItem] = []

        for element in content.elements {
            // Selected items have focus or selected state
            if element.isFocused || element.role == "AXCell" {
                if let name = element.title ?? element.value, !name.isEmpty {
                    var item = FinderItem()
                    item.name = name
                    item.isSelected = true
                    item.isDirectory = determineIfDirectory(element)
                    items.append(item)
                }
            }
        }

        return items
    }

    private func parseItems(from window: AccessibilityWindowContent) -> [FinderItem] {
        var items: [FinderItem] = []

        for element in window.elements {
            // Files/folders are typically cells, icons, or rows
            if element.role == "AXCell" || element.role == "AXIcon" || element.role == "AXRow" {
                if let name = element.title ?? element.value, !name.isEmpty {
                    // Filter out UI elements that aren't files
                    if !isUIElement(name) {
                        var item = FinderItem()
                        item.name = name
                        item.isDirectory = determineIfDirectory(element)
                        items.append(item)
                    }
                }
            }
        }

        return items
    }

    private func determineIfDirectory(_ element: AccessibilityElement) -> Bool {
        // Directories typically have no extension
        if let name = element.title ?? element.value {
            // If has extension, likely a file
            if name.contains(".") && !name.hasPrefix(".") {
                let ext = name.components(separatedBy: ".").last ?? ""
                // Known file extensions
                let fileExtensions = ["txt", "pdf", "doc", "docx", "xls", "xlsx", "jpg", "png", "gif", "mp3", "mp4", "mov", "zip", "dmg", "app"]
                if fileExtensions.contains(ext.lowercased()) {
                    return false
                }
            }
            return true // Assume directory if no obvious extension
        }
        return false
    }

    private func isUIElement(_ name: String) -> Bool {
        let uiElements = ["Back", "Forward", "View", "Action", "Share", "Tags", "Search", "Sort", "Group"]
        return uiElements.contains(name)
    }
}

// MARK: - Data Structures

public struct FinderItem: Sendable {
    public var name: String = ""
    public var path: String?
    public var isDirectory: Bool = false
    public var isSelected: Bool = false
    public var size: String?
    public var modifiedDate: String?
    public var kind: String?

    public init() {}

    public var summary: String {
        var parts = [name]
        if isDirectory {
            parts.append("(folder)")
        }
        if let path = path {
            parts.append(path)
        }
        return parts.joined(separator: " ")
    }
}
