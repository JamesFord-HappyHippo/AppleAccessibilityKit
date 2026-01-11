import Foundation
import AppKit

// MARK: - Microsoft Outlook Reader

/// Specialized reader for Microsoft Outlook
@MainActor
public class OutlookReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.microsoft.Outlook"

    public init() {}

    // MARK: - Mail

    /// Get visible emails in current folder
    public func visibleEmails() async -> [OutlookEmail] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var emails: [OutlookEmail] = []

        for window in windows {
            emails.append(contentsOf: parseEmails(from: window))
        }

        return emails
    }

    /// Get currently selected/viewed email
    public func currentEmail() async -> OutlookEmail? {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        return parseCurrentEmail(from: content)
    }

    /// Get mail folders
    public func folders() async -> [String] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var folders: [String] = []

        for window in windows {
            for element in window.elements {
                if element.role == "AXOutlineRow" || element.role == "AXCell" {
                    if let title = element.title, isMailFolder(title) {
                        folders.append(title)
                    }
                }
            }
        }

        return folders
    }

    /// Get unread count
    public func unreadCount() async -> Int? {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)

        for window in windows {
            for element in window.elements {
                // Look for Inbox with count
                if let title = element.title, title.contains("Inbox") {
                    if let value = element.value, let count = Int(value) {
                        return count
                    }
                    // Or extract from title like "Inbox (5)"
                    let pattern = #"\((\d+)\)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                       let range = Range(match.range(at: 1), in: title),
                       let count = Int(title[range]) {
                        return count
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Calendar

    /// Get today's events from Outlook Calendar
    public func todaysEvents() async -> [OutlookEvent] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var events: [OutlookEvent] = []

        for window in windows {
            // Check if in calendar view
            if isCalendarView(window) {
                events.append(contentsOf: parseEvents(from: window))
            }
        }

        return events
    }

    /// Get current/next meeting
    public func upcomingMeeting() async -> OutlookEvent? {
        let events = await todaysEvents()

        // Find next event (simplified - would need actual time comparison)
        return events.first
    }

    /// Check if currently in calendar view
    public func isInCalendarView() async -> Bool {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return false
        }

        return isCalendarView(content)
    }

    // MARK: - Compose

    /// Check if composing a new message
    public func isComposing() async -> Bool {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return false
        }

        for element in content.elements {
            if let title = element.title {
                if title.contains("New Message") || title.contains("Reply") ||
                   title.contains("Forward") || title.contains("Compose") {
                    return true
                }
            }
            // Look for To/Cc/Subject fields
            if element.role == "AXTextField" {
                if let label = element.title {
                    if label == "To" || label == "Cc" || label == "Subject" {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Get compose window fields
    public func composeFields() async -> OutlookCompose? {
        guard await isComposing(),
              let content = walker.readFocusedWindow() else {
            return nil
        }

        var compose = OutlookCompose()

        for element in content.elements {
            if element.role == "AXTextField" || element.role == "AXTextArea" {
                if let label = element.title, let value = element.value {
                    switch label.lowercased() {
                    case "to": compose.to = value
                    case "cc": compose.cc = value
                    case "bcc": compose.bcc = value
                    case "subject": compose.subject = value
                    default: break
                    }
                }
            }
        }

        // Body is usually the main text area
        if !content.editableText.isEmpty {
            compose.body = content.editableText.joined(separator: "\n")
        }

        return compose
    }

    // MARK: - Utilities

    /// Check if Outlook is running
    public func isOutlookRunning() -> Bool {
        ApplicationReader().isApplicationRunning(bundleID)
    }

    /// Get current view (mail, calendar, contacts, etc.)
    public func currentView() async -> OutlookView {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return .unknown
        }

        let title = content.windowTitle.lowercased()
        let allText = content.labels.joined(separator: " ").lowercased()

        if title.contains("calendar") || allText.contains("calendar") {
            return .calendar
        }
        if title.contains("contacts") || title.contains("people") || allText.contains("contacts") {
            return .contacts
        }
        if title.contains("tasks") || allText.contains("to do") {
            return .tasks
        }

        return .mail
    }

    // MARK: - Private Parsing

    private func parseEmails(from window: AccessibilityWindowContent) -> [OutlookEmail] {
        var emails: [OutlookEmail] = []
        var currentEmail: OutlookEmail?

        for element in window.elements {
            if element.role == "AXRow" || element.role == "AXCell" {
                if let email = currentEmail, !email.subject.isEmpty {
                    emails.append(email)
                }
                currentEmail = OutlookEmail()
            }

            if let value = element.value ?? element.title, !value.isEmpty {
                if currentEmail == nil {
                    currentEmail = OutlookEmail()
                }

                // Parse email fields
                if value.contains("@") && !value.contains(" ") {
                    if currentEmail?.from == nil {
                        currentEmail?.from = value
                    }
                } else if looksLikeDate(value) {
                    currentEmail?.dateString = value
                } else if currentEmail?.subject.isEmpty == true && value.count > 5 {
                    currentEmail?.subject = value
                } else if !isUIElement(value) {
                    currentEmail?.preview = value
                }
            }
        }

        if let email = currentEmail, !email.subject.isEmpty {
            emails.append(email)
        }

        return emails
    }

    private func parseCurrentEmail(from content: AccessibilityWindowContent) -> OutlookEmail? {
        var email = OutlookEmail()

        // Parse from editable/static text
        let allText = content.editableText + content.textContent

        for (index, text) in allText.prefix(20).enumerated() {
            if text.contains("@") && !text.contains(" ") {
                if email.from == nil {
                    email.from = text
                }
            } else if text.lowercased().contains("subject:") {
                email.subject = text.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces)
            } else if email.subject.isEmpty && index < 5 && text.count > 5 {
                email.subject = text
            } else if index > 5 {
                email.body = (email.body ?? "") + text + "\n"
            }
        }

        return email.subject.isEmpty ? nil : email
    }

    private func parseEvents(from window: AccessibilityWindowContent) -> [OutlookEvent] {
        var events: [OutlookEvent] = []

        for element in window.elements {
            if element.role == "AXCell" || element.role == "AXGroup" {
                if let title = element.title ?? element.value {
                    if !isUIElement(title) && title.count > 2 {
                        var event = OutlookEvent()
                        event.title = title

                        // Try to extract time
                        if let time = extractTime(from: title) {
                            event.startTime = time
                        }

                        events.append(event)
                    }
                }
            }
        }

        return events
    }

    private func isCalendarView(_ content: AccessibilityWindowContent) -> Bool {
        let indicators = ["Today", "Week", "Month", "Day", "Work Week",
                         "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                         "Saturday", "Sunday", "Calendar"]

        for element in content.elements {
            if let title = element.title {
                if indicators.contains(where: { title.contains($0) }) {
                    return true
                }
            }
        }

        return content.windowTitle.contains("Calendar")
    }

    private func isMailFolder(_ text: String) -> Bool {
        let folders = ["Inbox", "Sent", "Drafts", "Junk", "Trash", "Deleted",
                      "Archive", "Outbox", "Focused", "Other"]
        return folders.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func looksLikeDate(_ text: String) -> Bool {
        let patterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,
            #"(Today|Yesterday)"#,
            #"(Mon|Tue|Wed|Thu|Fri|Sat|Sun)"#,
            #"\d{1,2}:\d{2}\s*(AM|PM)?"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    private func extractTime(from text: String) -> String? {
        let pattern = #"\d{1,2}:\d{2}\s*(AM|PM|am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }

    private func isUIElement(_ name: String) -> Bool {
        let uiElements = ["New Email", "Reply", "Forward", "Delete", "Archive",
                         "Flag", "Move", "More", "Filter", "Search", "Sync",
                         "Inbox", "Sent", "Drafts", "Calendar", "Contacts"]
        return uiElements.contains { name == $0 }
    }
}

// MARK: - Data Structures

public enum OutlookView: String, Sendable {
    case mail
    case calendar
    case contacts
    case tasks
    case unknown
}

public struct OutlookEmail: Sendable {
    public var subject: String = ""
    public var from: String?
    public var to: String?
    public var dateString: String?
    public var preview: String?
    public var body: String?
    public var isRead: Bool = true
    public var hasAttachments: Bool = false
    public var isFlagged: Bool = false

    public init() {}

    public var summary: String {
        var parts: [String] = []
        if let from = from { parts.append("From: \(from)") }
        parts.append("Subject: \(subject)")
        if let date = dateString { parts.append("Date: \(date)") }
        if let preview = preview { parts.append(preview) }
        return parts.joined(separator: "\n")
    }
}

public struct OutlookEvent: Sendable {
    public var title: String = ""
    public var startTime: String?
    public var endTime: String?
    public var location: String?
    public var organizer: String?
    public var isAllDay: Bool = false
    public var isMeeting: Bool = false
    public var attendees: [String] = []

    public init() {}

    public var summary: String {
        var parts = [title]
        if let start = startTime {
            if let end = endTime {
                parts.append("\(start) - \(end)")
            } else {
                parts.append(start)
            }
        }
        if let location = location {
            parts.append("@ \(location)")
        }
        return parts.joined(separator: " ")
    }
}

public struct OutlookCompose: Sendable {
    public var to: String?
    public var cc: String?
    public var bcc: String?
    public var subject: String?
    public var body: String?

    public init() {}
}
