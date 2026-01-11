import Foundation
import AppKit

// MARK: - Microsoft Teams Reader

/// Specialized reader for Microsoft Teams
@MainActor
public class TeamsReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.microsoft.teams"
    private let newTeamsBundleID = "com.microsoft.teams2" // New Teams app

    public init() {}

    // MARK: - Public API

    /// Get current chat/channel messages
    public func currentMessages() async -> [TeamsMessage] {
        guard let content = walker.readFocusedWindow(),
              isTeamsActive() else {
            return []
        }

        return parseMessages(from: content)
    }

    /// Get list of recent chats
    public func recentChats() async -> [TeamsChat] {
        let windows = walker.readAllWindows(bundleIdentifier: activeBundleID())
        var chats: [TeamsChat] = []

        for window in windows {
            chats.append(contentsOf: parseChats(from: window))
        }

        return chats
    }

    /// Get list of teams and channels
    public func teamsAndChannels() async -> [TeamsChannel] {
        let windows = walker.readAllWindows(bundleIdentifier: activeBundleID())
        var channels: [TeamsChannel] = []

        for window in windows {
            channels.append(contentsOf: parseChannels(from: window))
        }

        return channels
    }

    /// Get current meeting info (if in a meeting)
    public func currentMeeting() async -> TeamsMeeting? {
        guard let content = walker.readFocusedWindow(),
              isTeamsActive() else {
            return nil
        }

        return parseMeeting(from: content)
    }

    /// Check if currently in a call/meeting
    public func isInMeeting() async -> Bool {
        guard let content = walker.readFocusedWindow(),
              isTeamsActive() else {
            return false
        }

        // Look for meeting indicators
        for element in content.elements {
            if let title = element.title ?? element.value {
                let lower = title.lowercased()
                if lower.contains("leave") || lower.contains("hang up") ||
                   lower.contains("mute") || lower.contains("camera") ||
                   lower.contains("share screen") || lower.contains("participants") {
                    return true
                }
            }
        }

        return false
    }

    /// Get unread message count (if visible)
    public func unreadCount() async -> Int? {
        let windows = walker.readAllWindows(bundleIdentifier: activeBundleID())

        for window in windows {
            for element in window.elements {
                // Look for badge/notification counts
                if let value = element.value,
                   let count = Int(value),
                   count > 0 && count < 1000 {
                    if element.role?.contains("Badge") == true ||
                       element.role?.contains("StaticText") == true {
                        return count
                    }
                }
            }
        }

        return nil
    }

    /// Get current chat/channel name
    public func currentChatName() async -> String? {
        guard let content = walker.readFocusedWindow(),
              isTeamsActive() else {
            return nil
        }

        // Often in window title or header
        let title = content.windowTitle
        if !title.isEmpty && title != "Microsoft Teams" {
            // Extract chat name from title like "Chat - Person Name - Microsoft Teams"
            let parts = title.components(separatedBy: " - ")
            if parts.count >= 2 {
                return parts[1]
            }
        }

        // Look for header element
        for element in content.elements {
            if element.role == "AXHeading" || element.role == "AXStaticText" {
                if let title = element.title, !title.isEmpty {
                    if !isUIElement(title) {
                        return title
                    }
                }
            }
        }

        return nil
    }

    /// Get participants in current chat/meeting
    public func participants() async -> [String] {
        guard let content = walker.readFocusedWindow(),
              isTeamsActive() else {
            return []
        }

        var participants: [String] = []

        for element in content.elements {
            if let value = element.value ?? element.title {
                // Look for names (often in participant list or chat header)
                if looksLikeName(value) && !isUIElement(value) {
                    participants.append(value)
                }
            }
        }

        return participants
    }

    // MARK: - Utilities

    /// Check if Teams is running
    public func isTeamsRunning() -> Bool {
        ApplicationReader().isApplicationRunning(bundleID) ||
        ApplicationReader().isApplicationRunning(newTeamsBundleID)
    }

    /// Check if Teams is the active app
    public func isTeamsActive() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return front == bundleID || front == newTeamsBundleID
    }

    private func activeBundleID() -> String {
        if ApplicationReader().isApplicationRunning(newTeamsBundleID) {
            return newTeamsBundleID
        }
        return bundleID
    }

    // MARK: - Parsing

    private func parseMessages(from content: AccessibilityWindowContent) -> [TeamsMessage] {
        var messages: [TeamsMessage] = []
        var currentMessage: TeamsMessage?

        for element in content.elements {
            // Messages are typically in list items or groups
            if element.role == "AXGroup" || element.role == "AXListItem" {
                if let msg = currentMessage, !msg.content.isEmpty {
                    messages.append(msg)
                }
                currentMessage = TeamsMessage()
            }

            if let value = element.value ?? element.title, !value.isEmpty {
                if currentMessage == nil {
                    currentMessage = TeamsMessage()
                }

                // Determine if this is sender, time, or content
                if looksLikeName(value) && currentMessage?.sender == nil {
                    currentMessage?.sender = value
                } else if looksLikeTime(value) {
                    currentMessage?.timestamp = value
                } else if !isUIElement(value) {
                    currentMessage?.content += value + " "
                }
            }
        }

        if let msg = currentMessage, !msg.content.isEmpty {
            messages.append(msg)
        }

        return messages
    }

    private func parseChats(from window: AccessibilityWindowContent) -> [TeamsChat] {
        var chats: [TeamsChat] = []

        for element in window.elements {
            if element.role == "AXCell" || element.role == "AXRow" {
                if let title = element.title ?? element.value {
                    if looksLikeName(title) || title.contains("Chat") {
                        var chat = TeamsChat()
                        chat.name = title
                        chats.append(chat)
                    }
                }
            }
        }

        return chats
    }

    private func parseChannels(from window: AccessibilityWindowContent) -> [TeamsChannel] {
        var channels: [TeamsChannel] = []
        var currentTeam: String?

        for element in window.elements {
            if let title = element.title ?? element.value {
                // Teams are usually in a tree/outline structure
                if element.role == "AXOutlineRow" || element.role == "AXDisclosureTriangle" {
                    currentTeam = title
                } else if element.role == "AXStaticText" || element.role == "AXCell" {
                    if title.hasPrefix("#") || title.contains("General") {
                        var channel = TeamsChannel()
                        channel.name = title.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                        channel.teamName = currentTeam
                        channels.append(channel)
                    }
                }
            }
        }

        return channels
    }

    private func parseMeeting(from content: AccessibilityWindowContent) -> TeamsMeeting? {
        var meeting = TeamsMeeting()
        var foundMeetingIndicator = false

        for element in content.elements {
            if let value = element.value ?? element.title {
                let lower = value.lowercased()

                // Meeting indicators
                if lower.contains("leave") || lower.contains("hang up") {
                    foundMeetingIndicator = true
                }

                // Meeting title
                if element.role == "AXHeading" && meeting.title == nil {
                    meeting.title = value
                }

                // Duration
                if lower.contains(":") && value.count < 10 {
                    let pattern = #"\d{1,2}:\d{2}(:\d{2})?"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
                        meeting.duration = value
                    }
                }

                // Participant count
                if lower.contains("participant") {
                    let numbers = value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    if let count = Int(numbers) {
                        meeting.participantCount = count
                    }
                }
            }
        }

        return foundMeetingIndicator ? meeting : nil
    }

    private func looksLikeName(_ text: String) -> Bool {
        // Names typically have 2-4 words, capitalized
        let words = text.components(separatedBy: " ")
        guard words.count >= 1 && words.count <= 5 else { return false }

        // Check if words are capitalized
        let capitalizedWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }

        return capitalizedWords.count >= 1 && !text.contains("@") && text.count < 50
    }

    private func looksLikeTime(_ text: String) -> Bool {
        let pattern = #"\d{1,2}:\d{2}\s*(AM|PM|am|pm)?|Yesterday|Today|\d{1,2}/\d{1,2}"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        return false
    }

    private func isUIElement(_ name: String) -> Bool {
        let uiElements = ["New chat", "Search", "Settings", "More", "Filter",
                         "Activity", "Chat", "Teams", "Calendar", "Calls", "Files",
                         "Mute", "Unmute", "Camera", "Share", "Leave", "Reactions"]
        return uiElements.contains { name.hasPrefix($0) || name == $0 }
    }
}

// MARK: - Data Structures

public struct TeamsMessage: Sendable {
    public var sender: String?
    public var content: String = ""
    public var timestamp: String?
    public var isRead: Bool = true

    public init() {}

    public var summary: String {
        var parts: [String] = []
        if let sender = sender { parts.append(sender) }
        parts.append(content.trimmingCharacters(in: .whitespaces))
        if let time = timestamp { parts.append("(\(time))") }
        return parts.joined(separator: ": ")
    }
}

public struct TeamsChat: Sendable {
    public var name: String = ""
    public var lastMessage: String?
    public var lastMessageTime: String?
    public var unreadCount: Int = 0
    public var isGroup: Bool = false

    public init() {}
}

public struct TeamsChannel: Sendable {
    public var name: String = ""
    public var teamName: String?
    public var unreadCount: Int = 0

    public init() {}

    public var fullName: String {
        if let team = teamName {
            return "\(team) > \(name)"
        }
        return name
    }
}

public struct TeamsMeeting: Sendable {
    public var title: String?
    public var duration: String?
    public var participantCount: Int?
    public var isMuted: Bool = false
    public var isCameraOn: Bool = false
    public var isScreenSharing: Bool = false

    public init() {}

    public var summary: String {
        var parts: [String] = []
        if let title = title { parts.append(title) }
        if let duration = duration { parts.append("Duration: \(duration)") }
        if let count = participantCount { parts.append("\(count) participants") }
        return parts.joined(separator: " - ")
    }
}
