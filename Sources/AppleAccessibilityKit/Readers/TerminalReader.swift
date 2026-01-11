import Foundation
import AppKit

// MARK: - Terminal Reader

/// Specialized reader for Terminal, iTerm2, Warp, and other terminal emulators
@MainActor
public class TerminalReader {
    private let walker = AccessibilityTreeWalker()

    public init() {}

    // MARK: - Supported Terminals

    public enum Terminal: String, CaseIterable, Sendable {
        case terminal = "com.apple.Terminal"
        case iterm = "com.googlecode.iterm2"
        case warp = "dev.warp.Warp-Stable"
        case alacritty = "org.alacritty"
        case kitty = "net.kovidgoyal.kitty"
        case hyper = "co.zeit.hyper"

        public var displayName: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm: return "iTerm2"
            case .warp: return "Warp"
            case .alacritty: return "Alacritty"
            case .kitty: return "Kitty"
            case .hyper: return "Hyper"
            }
        }
    }

    // MARK: - Public API

    /// Read visible terminal output
    public func output(terminal: Terminal? = nil) async -> String? {
        let target = terminal ?? detectFrontmostTerminal()
        guard let term = target else { return nil }

        let windows = walker.readAllWindows(bundleIdentifier: term.rawValue)

        for window in windows {
            // Terminal content is usually in text areas or static text
            let content = window.editableText + window.textContent

            if !content.isEmpty {
                return content.joined(separator: "\n")
            }
        }

        return nil
    }

    /// Get the current working directory (if visible in prompt)
    public func currentDirectory(terminal: Terminal? = nil) async -> String? {
        guard let output = await output(terminal: terminal) else { return nil }

        // Look for common prompt patterns that include path
        let patterns = [
            #"(?:~|/[^\s:$#%>]+)"#,  // Unix paths
            #"\w+@\w+:([^\s$#]+)"#,  // user@host:path format
            #"(?:pwd|PWD):\s*([^\n]+)"#  // After pwd command
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range, in: output) {
                let path = String(output[range])
                if path.contains("/") || path.starts(with: "~") {
                    return path
                }
            }
        }

        return nil
    }

    /// Get the last command executed (if visible)
    public func lastCommand(terminal: Terminal? = nil) async -> String? {
        guard let output = await output(terminal: terminal) else { return nil }

        let lines = output.components(separatedBy: "\n")

        // Look for lines that look like commands (start with $ or > or have prompt patterns)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty { continue }

            // Look for common prompt endings
            if let commandStart = trimmed.firstIndex(of: "$") ??
                                  trimmed.firstIndex(of: ">") ??
                                  trimmed.firstIndex(of: "%") {
                let afterPrompt = trimmed[trimmed.index(after: commandStart)...]
                    .trimmingCharacters(in: .whitespaces)
                if !afterPrompt.isEmpty {
                    return afterPrompt
                }
            }
        }

        return nil
    }

    /// Check if there's an error in recent output
    public func hasError(terminal: Terminal? = nil) async -> Bool {
        guard let output = await output(terminal: terminal) else { return false }

        let errorIndicators = [
            "error:", "Error:", "ERROR:",
            "failed", "Failed", "FAILED",
            "fatal:", "Fatal:", "FATAL:",
            "exception", "Exception", "EXCEPTION",
            "permission denied",
            "command not found",
            "No such file or directory"
        ]

        return errorIndicators.contains { output.contains($0) }
    }

    /// Extract error messages from output
    public func errors(terminal: Terminal? = nil) async -> [String] {
        guard let output = await output(terminal: terminal) else { return [] }

        var errors: [String] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error") || lower.contains("failed") ||
               lower.contains("fatal") || lower.contains("exception") {
                errors.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        return errors
    }

    /// Get all terminal windows/tabs
    public func sessions(terminal: Terminal? = nil) async -> [TerminalSession] {
        var sessions: [TerminalSession] = []

        let terminals = terminal.map { [$0] } ?? runningTerminals()

        for term in terminals {
            let windows = walker.readAllWindows(bundleIdentifier: term.rawValue)

            for (index, window) in windows.enumerated() {
                var session = TerminalSession()
                session.terminal = term
                session.windowIndex = index
                session.title = window.windowTitle

                // Extract content
                let content = window.editableText + window.textContent
                session.lastLines = content.suffix(50).map { String($0) }

                sessions.append(session)
            }
        }

        return sessions
    }

    /// Check if a process appears to be running (based on output patterns)
    public func isProcessRunning(terminal: Terminal? = nil) async -> Bool {
        guard let output = await output(terminal: terminal) else { return false }

        let lines = output.components(separatedBy: "\n")
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespaces) else {
            return false
        }

        // If last line ends with prompt character, no process is running
        let promptEndings: [Character] = ["$", ">", "%", "#"]
        if let lastChar = lastLine.last, promptEndings.contains(lastChar) {
            return false
        }

        // If there's a spinner or progress indicator
        let progressIndicators = ["...", "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        if progressIndicators.contains(where: { lastLine.contains($0) }) {
            return true
        }

        return true // Assume running if no prompt visible
    }

    // MARK: - Detection

    /// Detect which terminal is frontmost
    public func detectFrontmostTerminal() -> Terminal? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }

        return Terminal.allCases.first { $0.rawValue == frontApp }
    }

    /// Get all running terminals
    public func runningTerminals() -> [Terminal] {
        let running = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier }
        return Terminal.allCases.filter { running.contains($0.rawValue) }
    }
}

// MARK: - Data Structures

public struct TerminalSession: Sendable {
    public var terminal: TerminalReader.Terminal?
    public var windowIndex: Int = 0
    public var title: String = ""
    public var lastLines: [String] = []
    public var currentDirectory: String?

    public init() {}

    public var summary: String {
        var parts: [String] = []
        if let term = terminal {
            parts.append(term.displayName)
        }
        if !title.isEmpty {
            parts.append(title)
        }
        return parts.joined(separator: " - ")
    }

    public var recentOutput: String {
        lastLines.joined(separator: "\n")
    }
}
