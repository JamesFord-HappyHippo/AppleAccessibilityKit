import Foundation
import AppKit

// MARK: - Calendar.app Reader

/// Specialized reader for Apple Calendar via Accessibility API
@MainActor
public class CalendarReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.apple.iCal"

    public init() {}

    // MARK: - Public API

    /// Read currently visible calendar events
    public func visibleEvents() async -> [CalendarEvent] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var events: [CalendarEvent] = []

        for window in windows {
            if let parsed = parseEvents(from: window) {
                events.append(contentsOf: parsed)
            }
        }

        return events
    }

    /// Get event currently being viewed/edited
    public func currentEvent() async -> CalendarEvent? {
        guard let content = walker.readFocusedWindow() else {
            return nil
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        return parseEvent(from: content)
    }

    /// Search for events containing specific text
    public func searchEvents(containing query: String) async -> [CalendarEvent] {
        let allEvents = await visibleEvents()
        return allEvents.filter { event in
            event.title.localizedCaseInsensitiveContains(query) ||
            event.location?.localizedCaseInsensitiveContains(query) ?? false ||
            event.notes?.localizedCaseInsensitiveContains(query) ?? false
        }
    }

    /// Detect if an event is a meeting
    public func isMeeting(_ event: CalendarEvent) -> Bool {
        if let attendees = event.attendees, !attendees.isEmpty {
            return true
        }

        if let notes = event.notes, containsMeetingLink(notes) {
            return true
        }

        if let url = event.url, containsMeetingLink(url) {
            return true
        }

        return false
    }

    /// Extract meeting link from event
    public func meetingLink(from event: CalendarEvent) -> String? {
        if let url = event.url, containsMeetingLink(url) {
            return url
        }

        if let notes = event.notes {
            return extractMeetingURL(from: notes)
        }

        return nil
    }

    /// Check if Calendar.app is running
    public func isCalendarRunning() -> Bool {
        ApplicationReader().isApplicationRunning(bundleID)
    }

    // MARK: - Parsing

    private func parseEvents(from window: AccessibilityWindowContent) -> [CalendarEvent]? {
        var events: [CalendarEvent] = []
        var current: CalendarEvent?

        for element in window.elements {
            guard let role = element.role else { continue }

            if role.contains("Cell") || role.contains("Row") || role.contains("Group") {
                if let event = current {
                    events.append(event)
                }
                current = nil
            }

            if let value = element.value, !value.isEmpty {
                if current == nil {
                    current = CalendarEvent()
                }

                if value.contains(":") && value.count < 20 {
                    current?.timeString = value
                } else if value.count < 100 {
                    if current?.title.isEmpty ?? true {
                        current?.title = value
                    } else {
                        current?.location = value
                    }
                } else {
                    current?.notes = value
                }
            }
        }

        if let event = current {
            events.append(event)
        }

        return events.isEmpty ? nil : events
    }

    private func parseEvent(from content: AccessibilityWindowContent) -> CalendarEvent? {
        var event = CalendarEvent()

        if !content.editableText.isEmpty {
            for (index, text) in content.editableText.enumerated() {
                switch index {
                case 0: event.title = text
                case 1: event.location = text
                default: event.notes = (event.notes ?? "") + text + "\n"
                }
            }
        }

        for element in content.elements {
            if let value = element.value, !value.isEmpty {
                if value.contains(":") && value.count < 20 {
                    event.timeString = value
                } else if value.contains("@") {
                    if event.attendees == nil {
                        event.attendees = []
                    }
                    event.attendees?.append(value)
                } else if containsMeetingLink(value) {
                    event.url = value
                }
            }
        }

        return event.title.isEmpty ? nil : event
    }

    private func containsMeetingLink(_ text: String) -> Bool {
        let platforms = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "gotomeeting.com"]
        return platforms.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func extractMeetingURL(from text: String) -> String? {
        let platforms = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"]
        for platform in platforms {
            let pattern = "https?://[^\\s]*\(platform)[^\\s]*"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }
}

// MARK: - Data Structures

public struct CalendarEvent: Sendable {
    public var title: String = ""
    public var location: String?
    public var url: String?
    public var notes: String?
    public var timeString: String?
    public var attendees: [String]?
    public var calendar: String?
    public var isAllDay: Bool = false

    public init() {}

    public var summary: String {
        var lines = [title]
        if let time = timeString { lines.append("Time: \(time)") }
        if let location = location { lines.append("Location: \(location)") }
        if let attendees = attendees, !attendees.isEmpty {
            lines.append("Attendees: \(attendees.joined(separator: ", "))")
        }
        if let url = url { lines.append("URL: \(url)") }
        return lines.joined(separator: "\n")
    }
}
