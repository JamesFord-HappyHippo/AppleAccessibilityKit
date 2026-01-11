import Foundation
import AppKit

// MARK: - Mail.app Reader

/// Specialized reader for Apple Mail via Accessibility API
@MainActor
public class MailReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.apple.mail"

    public init() {}

    // MARK: - Public API

    /// Read visible emails from mailbox list
    public func visibleEmails() async -> [MailMessage] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var messages: [MailMessage] = []

        for window in windows {
            if let parsed = parseMessages(from: window) {
                messages.append(contentsOf: parsed)
            }
        }

        return messages
    }

    /// Get currently selected/viewed email
    public func currentEmail() async -> MailMessage? {
        guard let content = walker.readFocusedWindow() else {
            return nil
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        return parseCurrentMessage(from: content)
    }

    /// Get mailbox names
    public func mailboxes() async -> [String] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var boxes: [String] = []

        for window in windows {
            for element in window.elements {
                if element.role == "AXOutlineRow" || element.role == "AXStaticText" {
                    if let title = element.title, isMailboxName(title) {
                        boxes.append(title)
                    }
                }
            }
        }

        return boxes
    }

    /// Get unread count (if visible)
    public func unreadCount() async -> Int? {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)

        for window in windows {
            for element in window.elements {
                if let value = element.value,
                   let count = Int(value),
                   element.role?.contains("StaticText") ?? false {
                    // Likely an unread count badge
                    return count
                }
            }
        }

        return nil
    }

    /// Check if Mail.app is running
    public func isMailRunning() -> Bool {
        ApplicationReader().isApplicationRunning(bundleID)
    }

    // MARK: - Parsing

    private func parseMessages(from window: AccessibilityWindowContent) -> [MailMessage]? {
        var messages: [MailMessage] = []
        var current: MailMessage?

        for element in window.elements {
            guard let role = element.role else { continue }

            // Mail list rows
            if role.contains("Row") || role.contains("Cell") {
                if let msg = current, !msg.subject.isEmpty {
                    messages.append(msg)
                }
                current = nil
            }

            if let value = element.value, !value.isEmpty {
                if current == nil {
                    current = MailMessage()
                }

                // Heuristics for field type
                if value.contains("@") && !value.contains(" ") {
                    if current?.from == nil {
                        current?.from = value
                    } else {
                        current?.to = value
                    }
                } else if isDateString(value) {
                    current?.dateString = value
                } else if current?.subject.isEmpty ?? true {
                    current?.subject = value
                } else {
                    current?.preview = value
                }
            }
        }

        if let msg = current, !msg.subject.isEmpty {
            messages.append(msg)
        }

        return messages.isEmpty ? nil : messages
    }

    private func parseCurrentMessage(from content: AccessibilityWindowContent) -> MailMessage? {
        var message = MailMessage()

        // Extract from editable content (compose) or text content (view)
        let allText = content.editableText + content.textContent

        for (index, text) in allText.prefix(10).enumerated() {
            if text.contains("@") && !text.contains(" ") {
                if message.from == nil {
                    message.from = text
                } else if message.to == nil {
                    message.to = text
                }
            } else if text.lowercased().contains("subject:") {
                message.subject = text.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces)
            } else if message.subject.isEmpty && index < 3 {
                message.subject = text
            } else {
                message.body = (message.body ?? "") + text + "\n"
            }
        }

        return message.subject.isEmpty ? nil : message
    }

    private func isMailboxName(_ text: String) -> Bool {
        let knownMailboxes = ["Inbox", "Sent", "Drafts", "Junk", "Trash", "Archive", "All Mail"]
        return knownMailboxes.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func isDateString(_ text: String) -> Bool {
        let datePatterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,  // MM/DD/YYYY
            #"\d{1,2}:\d{2}\s*(AM|PM)?"#,  // HH:MM AM/PM
            #"(Today|Yesterday)"#,
            #"(Mon|Tue|Wed|Thu|Fri|Sat|Sun)"#
        ]

        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }

        return false
    }
}

// MARK: - Data Structures

public struct MailMessage: Sendable {
    public var subject: String = ""
    public var from: String?
    public var to: String?
    public var dateString: String?
    public var preview: String?
    public var body: String?
    public var isRead: Bool = true
    public var hasAttachments: Bool = false

    public init() {}

    public var summary: String {
        var lines: [String] = []
        if let from = from { lines.append("From: \(from)") }
        if let to = to { lines.append("To: \(to)") }
        lines.append("Subject: \(subject)")
        if let date = dateString { lines.append("Date: \(date)") }
        if let preview = preview { lines.append("Preview: \(preview)") }
        return lines.joined(separator: "\n")
    }
}
