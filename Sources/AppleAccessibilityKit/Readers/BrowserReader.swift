import Foundation
import AppKit

// MARK: - Browser Reader

/// Specialized reader for Safari, Chrome, and other browsers
@MainActor
public class BrowserReader {
    private let walker = AccessibilityTreeWalker()

    public init() {}

    // MARK: - Supported Browsers

    public enum Browser: String, CaseIterable, Sendable {
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"
        case firefox = "org.mozilla.firefox"
        case edge = "com.microsoft.edgemac"
        case arc = "company.thebrowser.Browser"
        case brave = "com.brave.Browser"

        public var displayName: String {
            switch self {
            case .safari: return "Safari"
            case .chrome: return "Chrome"
            case .firefox: return "Firefox"
            case .edge: return "Edge"
            case .arc: return "Arc"
            case .brave: return "Brave"
            }
        }
    }

    // MARK: - Public API

    /// Get all open tabs from a browser
    public func tabs(browser: Browser) async -> [BrowserTab] {
        let windows = walker.readAllWindows(bundleIdentifier: browser.rawValue)
        var tabs: [BrowserTab] = []

        for window in windows {
            tabs.append(contentsOf: extractTabs(from: window, browser: browser))
        }

        return tabs
    }

    /// Get the currently active tab
    public func activeTab(browser: Browser? = nil) async -> BrowserTab? {
        let targetBrowser = browser ?? detectFrontmostBrowser()
        guard let browser = targetBrowser else { return nil }

        guard let content = walker.readFocusedWindow(),
              isBrowser(content.applicationName) else {
            return nil
        }

        return extractActiveTab(from: content, browser: browser)
    }

    /// Get page content from the current tab
    public func pageContent(browser: Browser? = nil) async -> String? {
        let targetBrowser = browser ?? detectFrontmostBrowser()
        guard let browser = targetBrowser else { return nil }

        let windows = walker.readAllWindows(bundleIdentifier: browser.rawValue)

        for window in windows {
            // Look for web content area
            let webContent = window.elements.filter { element in
                element.role == "AXWebArea" || element.role == "AXGroup"
            }

            if !webContent.isEmpty {
                return window.asPlainText()
            }
        }

        return nil
    }

    /// Get URL from address bar
    public func currentURL(browser: Browser? = nil) async -> String? {
        let targetBrowser = browser ?? detectFrontmostBrowser()
        guard let browser = targetBrowser else { return nil }

        let windows = walker.readAllWindows(bundleIdentifier: browser.rawValue)

        for window in windows {
            // Look for URL in text fields (address bar)
            for element in window.elements {
                if element.role == "AXTextField" || element.role == "AXComboBox" {
                    if let value = element.value,
                       (value.hasPrefix("http") || value.hasPrefix("www") || value.contains(".com") || value.contains(".org")) {
                        return value
                    }
                }
            }

            // Also check window title (often contains URL or page title)
            if window.windowTitle.contains("http") {
                return extractURL(from: window.windowTitle)
            }
        }

        return nil
    }

    /// Search for text in current page
    public func findInPage(_ searchText: String, browser: Browser? = nil) async -> Bool {
        if let content = await pageContent(browser: browser) {
            return content.localizedCaseInsensitiveContains(searchText)
        }
        return false
    }

    /// Get all links on current page
    public func links(browser: Browser? = nil) async -> [String] {
        let targetBrowser = browser ?? detectFrontmostBrowser()
        guard let browser = targetBrowser else { return [] }

        let windows = walker.readAllWindows(bundleIdentifier: browser.rawValue)
        var links: [String] = []

        for window in windows {
            for element in window.elements {
                if element.role == "AXLink" {
                    if let title = element.title {
                        links.append(title)
                    }
                    if let value = element.value {
                        links.append(value)
                    }
                }
            }
        }

        return links
    }

    /// Detect which browser is frontmost
    public func detectFrontmostBrowser() -> Browser? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }

        return Browser.allCases.first { $0.rawValue == frontApp }
    }

    /// Check if any browser is running
    public func runningBrowsers() -> [Browser] {
        let running = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier }
        return Browser.allCases.filter { running.contains($0.rawValue) }
    }

    // MARK: - Private Methods

    private func extractTabs(from window: AccessibilityWindowContent, browser: Browser) -> [BrowserTab] {
        var tabs: [BrowserTab] = []

        for element in window.elements {
            // Tabs are typically radio buttons or buttons in tab bar
            if element.role == "AXRadioButton" || element.role == "AXButton" {
                if let title = element.title, !title.isEmpty {
                    // Filter out non-tab buttons
                    let nonTabTitles = ["Close", "Minimize", "Zoom", "Back", "Forward", "Reload", "Home"]
                    if !nonTabTitles.contains(title) {
                        var tab = BrowserTab()
                        tab.title = title
                        tab.browser = browser
                        tabs.append(tab)
                    }
                }
            }
        }

        return tabs
    }

    private func extractActiveTab(from content: AccessibilityWindowContent, browser: Browser) -> BrowserTab? {
        var tab = BrowserTab()
        tab.browser = browser
        tab.title = content.windowTitle

        // Try to extract URL from window content
        for element in content.elements {
            if element.role == "AXTextField" || element.role == "AXComboBox" {
                if let value = element.value, looksLikeURL(value) {
                    tab.url = value
                    break
                }
            }
        }

        return tab.title.isEmpty ? nil : tab
    }

    private func isBrowser(_ appName: String) -> Bool {
        let browserNames = ["Safari", "Chrome", "Firefox", "Edge", "Arc", "Brave", "Opera"]
        return browserNames.contains { appName.localizedCaseInsensitiveContains($0) }
    }

    private func looksLikeURL(_ text: String) -> Bool {
        return text.hasPrefix("http") || text.hasPrefix("www") ||
               text.contains(".com") || text.contains(".org") ||
               text.contains(".io") || text.contains(".dev")
    }

    private func extractURL(from text: String) -> String? {
        let pattern = #"https?://[^\s]+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }
}

// MARK: - Data Structures

public struct BrowserTab: Sendable {
    public var title: String = ""
    public var url: String?
    public var browser: BrowserReader.Browser?
    public var isActive: Bool = false

    public init() {}

    public var summary: String {
        var parts = [title]
        if let url = url {
            parts.append(url)
        }
        if let browser = browser {
            parts.append("(\(browser.displayName))")
        }
        return parts.joined(separator: " - ")
    }
}
