import Foundation
import AppKit

// MARK: - Apple Notes Reader

/// Specialized reader for Apple Notes app
@MainActor
public class NotesReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.apple.Notes"

    public init() {}

    // MARK: - Public API

    /// Read currently visible/selected note
    public func currentNote() async -> Note? {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        return parseNote(from: content)
    }

    /// Get list of visible notes in sidebar
    public func notesList() async -> [NoteSummary] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var notes: [NoteSummary] = []

        for window in windows {
            for element in window.elements {
                // Notes list items are typically rows or cells
                if element.role == "AXRow" || element.role == "AXCell" {
                    if let title = element.title ?? element.value, !title.isEmpty {
                        var summary = NoteSummary()
                        summary.title = title
                        notes.append(summary)
                    }
                }
            }
        }

        return notes
    }

    /// Get all folders
    public func folders() async -> [String] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var folders: [String] = []

        for window in windows {
            for element in window.elements {
                // Folders are in outline/source list
                if element.role == "AXOutlineRow" || element.role == "AXStaticText" {
                    if let title = element.title, isFolderName(title) {
                        folders.append(title)
                    }
                }
            }
        }

        return folders
    }

    /// Search notes for text
    public func search(_ query: String) async -> [NoteSummary] {
        // Read all visible note titles and filter
        let notes = await notesList()
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
        }
    }

    /// Check if Notes is running
    public func isNotesRunning() -> Bool {
        ApplicationReader().isApplicationRunning(bundleID)
    }

    // MARK: - Parsing

    private func parseNote(from content: AccessibilityWindowContent) -> Note? {
        var note = Note()

        // Title is usually the first editable text or the window title
        if let firstEditable = content.editableText.first {
            note.title = firstEditable
        } else {
            // Extract title from window title (format: "Note Title - Notes")
            let windowTitle = content.windowTitle
            if let dashIndex = windowTitle.lastIndex(of: "-") {
                note.title = String(windowTitle[..<dashIndex]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Body is the remaining editable text
        if content.editableText.count > 1 {
            note.body = content.editableText.dropFirst().joined(separator: "\n")
        } else if !content.textContent.isEmpty {
            note.body = content.textContent.joined(separator: "\n")
        }

        // Look for attachments, checklists
        for element in content.elements {
            if element.role == "AXImage" {
                note.hasAttachments = true
            }
            if element.role == "AXCheckBox" {
                note.hasChecklist = true
            }
        }

        return note.title.isEmpty ? nil : note
    }

    private func isFolderName(_ text: String) -> Bool {
        let knownFolders = ["All iCloud", "Notes", "Recently Deleted", "Shared", "All"]
        return knownFolders.contains { text.localizedCaseInsensitiveContains($0) } ||
               !text.contains(".")  // Likely a folder if no extension
    }
}

// MARK: - Data Structures

public struct Note: Sendable {
    public var title: String = ""
    public var body: String?
    public var folder: String?
    public var hasAttachments: Bool = false
    public var hasChecklist: Bool = false
    public var modifiedDate: String?

    public init() {}

    public var summary: String {
        var lines = [title]
        if let body = body {
            let preview = String(body.prefix(100))
            lines.append(preview + (body.count > 100 ? "..." : ""))
        }
        return lines.joined(separator: "\n")
    }

    public var plainText: String {
        [title, body].compactMap { $0 }.joined(separator: "\n\n")
    }
}

public struct NoteSummary: Sendable {
    public var title: String = ""
    public var preview: String?
    public var folder: String?
    public var modifiedDate: String?

    public init() {}
}
