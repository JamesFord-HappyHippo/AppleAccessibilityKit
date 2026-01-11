import Foundation

// MARK: - Text Extraction Utilities

public struct TextExtraction {

    // MARK: - URL Extraction

    /// Extract URLs from text
    public static func extractURLs(from text: String) -> [String] {
        let pattern = #"https?://[^\s<>\"\']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    /// Extract meeting URLs (Zoom, Google Meet, Teams, etc.)
    public static func extractMeetingURLs(from text: String) -> [String] {
        let meetingDomains = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "gotomeeting.com"]

        return extractURLs(from: text).filter { url in
            meetingDomains.contains { url.lowercased().contains($0) }
        }
    }

    // MARK: - Email Extraction

    /// Extract email addresses from text
    public static func extractEmails(from text: String) -> [String] {
        let pattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    // MARK: - Time Extraction

    /// Extract time strings from text
    public static func extractTimes(from text: String) -> [String] {
        let patterns = [
            #"\d{1,2}:\d{2}\s*(AM|PM|am|pm)?"#,  // 2:30 PM
            #"\d{1,2}\s*(AM|PM|am|pm)"#           // 2 PM
        ]

        var times: [String] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let range = Range(match.range, in: text) {
                    times.append(String(text[range]))
                }
            }
        }

        return times
    }

    /// Extract date strings from text
    public static func extractDates(from text: String) -> [String] {
        let patterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,                    // MM/DD/YYYY
            #"\d{4}-\d{2}-\d{2}"#,                          // YYYY-MM-DD
            #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4}"#,  // Jan 15, 2024
            #"(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"#,
            #"(Today|Tomorrow|Yesterday)"#
        ]

        var dates: [String] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let range = Range(match.range, in: text) {
                    dates.append(String(text[range]))
                }
            }
        }

        return dates
    }

    // MARK: - Code Extraction

    /// Extract file paths from text
    public static func extractFilePaths(from text: String) -> [String] {
        let patterns = [
            #"/[^\s:]+\.[a-zA-Z]+"#,                       // Unix paths
            #"[A-Za-z]:\\[^\s:]+"#,                        // Windows paths
            #"[^\s/]+\.(swift|js|ts|py|rb|go|rs|java|kt|cpp|c|h|m|mm|cs)"#  // Filenames
        ]

        var paths: [String] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let range = Range(match.range, in: text) {
                    paths.append(String(text[range]))
                }
            }
        }

        return paths
    }

    /// Extract error locations (file:line:col format)
    public static func extractErrorLocations(from text: String) -> [(file: String, line: Int, column: Int?)] {
        // Pattern: /path/file.swift:42:10 or file.cs(42,10)
        let patterns = [
            #"([^\s:]+):(\d+):(\d+)"#,           // file:line:col
            #"([^\s(]+)\((\d+),(\d+)\)"#         // file(line,col)
        ]

        var locations: [(file: String, line: Int, column: Int?)] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let fileRange = Range(match.range(at: 1), in: text),
                      let lineRange = Range(match.range(at: 2), in: text),
                      let line = Int(text[lineRange]) else { continue }

                let file = String(text[fileRange])
                var column: Int? = nil

                if match.numberOfRanges >= 4,
                   let colRange = Range(match.range(at: 3), in: text) {
                    column = Int(text[colRange])
                }

                locations.append((file: file, line: line, column: column))
            }
        }

        return locations
    }

    // MARK: - Semantic Analysis

    /// Determine the likely type of content
    public static func analyzeContentType(_ text: String) -> ContentType {
        let lowercased = text.lowercased()

        if lowercased.contains("error") || lowercased.contains("exception") || lowercased.contains("failed") {
            return .error
        }
        if lowercased.contains("warning") {
            return .warning
        }
        if !extractURLs(from: text).isEmpty {
            return .url
        }
        if !extractEmails(from: text).isEmpty {
            return .email
        }
        if !extractFilePaths(from: text).isEmpty {
            return .code
        }

        return .text
    }

    public enum ContentType {
        case text
        case error
        case warning
        case url
        case email
        case code
    }
}
