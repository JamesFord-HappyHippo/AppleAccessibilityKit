import Foundation
import AppKit

// MARK: - AppleAccessibilityKit

/// High-level facade for Apple Accessibility API
/// Use this as the primary entry point
@MainActor
public struct AppleAccessibilityKit {

    // MARK: - Quick Access

    /// Read the currently focused window
    public static func readFocusedWindow() async -> AccessibilityWindowContent? {
        let reader = ApplicationReader()
        if case .success(let content) = await reader.readFocusedWindow() {
            return content
        }
        return nil
    }

    /// Read all windows for a specific application
    public static func read(bundleId: String) async -> [AccessibilityWindowContent] {
        let reader = ApplicationReader()
        if case .success(let content) = await reader.read(bundleIdentifier: bundleId) {
            return content
        }
        return []
    }

    /// Get LLM-ready context from current screen
    public static func llmContext() async -> String {
        await ApplicationReader().getLLMContext()
    }

    // MARK: - Specialized Readers

    /// Calendar.app reader
    public static var calendar: CalendarReader { CalendarReader() }

    /// Mail.app reader
    public static var mail: MailReader { MailReader() }

    /// IDE reader (Xcode, Unity, Godot, etc.)
    public static var ide: IDEReader { IDEReader() }

    /// Browser reader (Safari, Chrome, Firefox, etc.)
    public static var browser: BrowserReader { BrowserReader() }

    /// Terminal reader (Terminal, iTerm, Warp, etc.)
    public static var terminal: TerminalReader { TerminalReader() }

    /// Apple Notes reader
    public static var notes: NotesReader { NotesReader() }

    /// Finder reader
    public static var finder: FinderReader { FinderReader() }

    /// Action performer (click, type, etc.)
    public static var actions: ActionPerformer { ActionPerformer() }

    /// Photos.app reader (time correction, travel logs)
    public static var photos: PhotosReader { PhotosReader() }

    // MARK: - Permissions

    /// Check if accessibility permission is granted
    public static func hasPermission() -> Bool {
        ApplicationReader().checkPermission()
    }

    /// Request accessibility permission
    public static func requestPermission() -> Bool {
        ApplicationReader().requestPermission()
    }

    /// Open System Settings to Accessibility pane
    public static func openSettings() {
        ApplicationReader().openAccessibilitySettings()
    }

    // MARK: - Utilities

    /// Check if an application is running
    public static func isRunning(_ bundleId: String) -> Bool {
        ApplicationReader().isApplicationRunning(bundleId)
    }

    /// Get frontmost application's bundle identifier
    public static func frontmostApp() -> String? {
        ApplicationReader().frontmostApplication()
    }
}

// MARK: - Convenience Extensions

extension AccessibilityWindowContent {
    /// Check if window contains specific text
    public func contains(_ text: String, caseSensitive: Bool = false) -> Bool {
        let searchText = caseSensitive ? text : text.lowercased()
        let allText = (textContent + labels + editableText)
            .joined(separator: " ")

        let compareText = caseSensitive ? allText : allText.lowercased()
        return compareText.contains(searchText)
    }

    /// Find elements matching a role
    public func elements(withRole role: String) -> [AccessibilityElement] {
        elements.filter { $0.role == role }
    }

    /// Get all buttons
    public var buttons: [AccessibilityElement] {
        elements.filter { $0.role == "AXButton" }
    }

    /// Get all text fields
    public var textFields: [AccessibilityElement] {
        elements.filter { $0.role == "AXTextField" || $0.role == "AXTextArea" }
    }

    /// Get all static text
    public var staticText: [AccessibilityElement] {
        elements.filter { $0.role == "AXStaticText" }
    }
}
