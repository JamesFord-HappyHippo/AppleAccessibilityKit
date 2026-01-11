import Foundation
import AppKit

// MARK: - Generic Application Reader

/// High-level API for reading any application's content
@MainActor
public class ApplicationReader {
    private let walker = AccessibilityTreeWalker()

    public init() {}

    // MARK: - Public API

    /// Read the currently focused window
    public func readFocusedWindow() async -> AccessibilityResult<AccessibilityWindowContent> {
        guard checkPermission() else {
            return .permissionDenied
        }

        if let content = walker.readFocusedWindow() {
            return .success(content)
        }

        return .windowNotFound
    }

    /// Read all windows for a specific application
    public func read(bundleIdentifier: String) async -> AccessibilityResult<[AccessibilityWindowContent]> {
        guard checkPermission() else {
            return .permissionDenied
        }

        guard isApplicationRunning(bundleIdentifier) else {
            return .applicationNotRunning
        }

        let content = walker.readAllWindows(bundleIdentifier: bundleIdentifier)
        return .success(content)
    }

    /// Read focused window and return as plain text for LLM
    public func readAsText() async -> String? {
        if case .success(let content) = await readFocusedWindow() {
            return content.asPlainText()
        }
        return nil
    }

    /// Get LLM-ready context from current screen
    public func getLLMContext() async -> String {
        var context = "=== Current Screen Context ===\n\n"

        if case .success(let content) = await readFocusedWindow() {
            context += "Application: \(content.applicationName)\n"
            context += "Window: \(content.windowTitle)\n"
            context += content.semanticSummary()
            context += "\n\n"
            context += content.asPlainText()
        }

        return context
    }

    // MARK: - Permission Handling

    /// Check if accessibility permissions are granted
    public func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Request accessibility permission (shows system prompt)
    public func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Open System Settings to Accessibility pane
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Utilities

    /// Check if an application is currently running
    public func isApplicationRunning(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Get the frontmost application's bundle identifier
    public func frontmostApplication() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Launch an application if not running
    public func launchIfNeeded(_ bundleIdentifier: String) async -> Bool {
        if isApplicationRunning(bundleIdentifier) {
            return true
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        do {
            _ = try NSWorkspace.shared.launchApplication(at: url, options: [], configuration: [:])
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return isApplicationRunning(bundleIdentifier)
        } catch {
            return false
        }
    }
}
