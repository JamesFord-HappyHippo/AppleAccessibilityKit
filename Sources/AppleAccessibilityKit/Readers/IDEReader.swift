import Foundation
import AppKit

// MARK: - IDE Reader for Xcode, Unity, Godot

/// Specialized reader for IDE applications
@MainActor
public class IDEReader {
    private let walker = AccessibilityTreeWalker()

    public init() {}

    // MARK: - Supported IDEs

    public enum IDE: String, CaseIterable {
        case xcode = "com.apple.dt.Xcode"
        case unity = "com.unity3d.UnityEditor"
        case godot = "org.godotengine.godot"
        case vsCode = "com.microsoft.VSCode"
        case androidStudio = "com.google.android.studio"
        case intellij = "com.jetbrains.intellij"
        case fleet = "com.jetbrains.fleet"

        public var displayName: String {
            switch self {
            case .xcode: return "Xcode"
            case .unity: return "Unity"
            case .godot: return "Godot"
            case .vsCode: return "VS Code"
            case .androidStudio: return "Android Studio"
            case .intellij: return "IntelliJ IDEA"
            case .fleet: return "JetBrains Fleet"
            }
        }
    }

    // MARK: - Public API

    /// Read all content from a specific IDE
    public func read(ide: IDE) async -> AccessibilityResult<[AccessibilityWindowContent]> {
        guard ApplicationReader().checkPermission() else {
            return .permissionDenied
        }

        guard ApplicationReader().isApplicationRunning(ide.rawValue) else {
            return .applicationNotRunning
        }

        let content = walker.readAllWindows(bundleIdentifier: ide.rawValue)
        return .success(content)
    }

    /// Extract compiler errors from IDE output
    public func compilerErrors(ide: IDE) async -> [CompilerError] {
        guard case .success(let windows) = await read(ide: ide) else {
            return []
        }

        var errors: [CompilerError] = []

        for window in windows {
            // Look for error patterns in text content
            for text in window.textContent {
                if let error = parseError(text, ide: ide) {
                    errors.append(error)
                }
            }

            // Also check labels (often used for issue navigator)
            for label in window.labels {
                if let error = parseError(label, ide: ide) {
                    errors.append(error)
                }
            }
        }

        return errors
    }

    /// Get the current file being edited
    public func currentFile(ide: IDE) async -> String? {
        guard case .success(let windows) = await read(ide: ide) else {
            return nil
        }

        // Window title often contains filename
        for window in windows {
            if !window.windowTitle.isEmpty {
                // Extract filename from window title
                let title = window.windowTitle

                // Xcode format: "FileName.swift - ProjectName"
                if let filename = title.components(separatedBy: " - ").first,
                   filename.contains(".") {
                    return filename
                }

                // VS Code format: "FileName.ts - FolderName - Visual Studio Code"
                if let filename = title.components(separatedBy: " - ").first,
                   filename.contains(".") {
                    return filename
                }
            }
        }

        return nil
    }

    /// Get project name from IDE
    public func projectName(ide: IDE) async -> String? {
        guard case .success(let windows) = await read(ide: ide) else {
            return nil
        }

        for window in windows {
            let title = window.windowTitle

            switch ide {
            case .xcode:
                // "FileName.swift - ProjectName"
                let parts = title.components(separatedBy: " - ")
                if parts.count >= 2 {
                    return parts[1]
                }
            case .unity:
                // "Unity - ProjectName - Scene.unity"
                let parts = title.components(separatedBy: " - ")
                if parts.count >= 2 {
                    return parts[1]
                }
            default:
                break
            }
        }

        return nil
    }

    /// Get all open files/tabs
    public func openFiles(ide: IDE) async -> [String] {
        guard case .success(let windows) = await read(ide: ide) else {
            return []
        }

        var files: [String] = []

        for window in windows {
            for element in window.elements {
                // Look for tab bar items
                if element.role == "AXRadioButton" || element.role == "AXButton" {
                    if let title = element.title, title.contains(".") {
                        files.append(title)
                    }
                }
            }
        }

        return files
    }

    // MARK: - Error Parsing

    private func parseError(_ text: String, ide: IDE) -> CompilerError? {
        let lowercased = text.lowercased()

        // Check if this looks like an error
        guard lowercased.contains("error") ||
              lowercased.contains("warning") ||
              lowercased.contains("failed") else {
            return nil
        }

        var error = CompilerError()
        error.rawText = text

        // Determine severity
        if lowercased.contains("error") || lowercased.contains("failed") {
            error.severity = .error
        } else if lowercased.contains("warning") {
            error.severity = .warning
        } else {
            error.severity = .info
        }

        // Try to extract file path and line number
        switch ide {
        case .xcode:
            // Format: "/path/file.swift:42:10: error: message"
            let pattern = #"([^:]+\.swift):(\d+):(\d+):\s*(error|warning):\s*(.+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let fileRange = Range(match.range(at: 1), in: text) {
                    error.file = String(text[fileRange])
                }
                if let lineRange = Range(match.range(at: 2), in: text),
                   let line = Int(text[lineRange]) {
                    error.line = line
                }
                if let colRange = Range(match.range(at: 3), in: text),
                   let col = Int(text[colRange]) {
                    error.column = col
                }
                if let msgRange = Range(match.range(at: 5), in: text) {
                    error.message = String(text[msgRange])
                }
            }

        case .unity:
            // Format: "Assets/Scripts/File.cs(42,10): error CS0103: message"
            let pattern = #"([^(]+)\((\d+),(\d+)\):\s*(error|warning)\s*\w+:\s*(.+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let fileRange = Range(match.range(at: 1), in: text) {
                    error.file = String(text[fileRange])
                }
                if let lineRange = Range(match.range(at: 2), in: text),
                   let line = Int(text[lineRange]) {
                    error.line = line
                }
                if let colRange = Range(match.range(at: 3), in: text),
                   let col = Int(text[colRange]) {
                    error.column = col
                }
                if let msgRange = Range(match.range(at: 5), in: text) {
                    error.message = String(text[msgRange])
                }
            }

        default:
            error.message = text
        }

        return error.message != nil ? error : nil
    }
}

// MARK: - Data Structures

public struct CompilerError: Sendable {
    public var file: String?
    public var line: Int?
    public var column: Int?
    public var message: String?
    public var severity: Severity = .error
    public var rawText: String = ""

    public enum Severity: String, Sendable {
        case error
        case warning
        case info
    }

    public init() {}

    public var summary: String {
        var parts: [String] = []
        if let file = file {
            parts.append(file)
        }
        if let line = line {
            parts.append("line \(line)")
        }
        if let message = message {
            parts.append(message)
        }
        return parts.joined(separator: ": ")
    }
}
