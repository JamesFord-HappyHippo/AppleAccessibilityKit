import Foundation
import AppKit

// MARK: - Photos.app Reader

/// Specialized reader for Apple Photos app
/// Supports time correction workflows and travel log generation
@MainActor
public class PhotosReader {
    private let walker = AccessibilityTreeWalker()
    private let bundleID = "com.apple.Photos"

    public init() {}

    // MARK: - Public API

    /// Get currently selected photos
    public func selectedPhotos() async -> [PhotoItem] {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return []
        }

        return parseSelectedPhotos(from: content)
    }

    /// Get visible photos in current view
    public func visiblePhotos() async -> [PhotoItem] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var photos: [PhotoItem] = []

        for window in windows {
            photos.append(contentsOf: parsePhotos(from: window))
        }

        return photos
    }

    /// Get photo metadata from info panel (if visible)
    public func currentPhotoInfo() async -> PhotoMetadata? {
        guard let content = walker.readFocusedWindow(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            return nil
        }

        return parseMetadata(from: content)
    }

    /// Get albums list
    public func albums() async -> [String] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var albums: [String] = []

        for window in windows {
            for element in window.elements {
                // Albums are in sidebar outline
                if element.role == "AXOutlineRow" || element.role == "AXCell" {
                    if let title = element.title, isAlbumName(title) {
                        albums.append(title)
                    }
                }
            }
        }

        return albums
    }

    /// Get current album/view name
    public func currentAlbum() async -> String? {
        guard let content = walker.readFocusedWindow() else { return nil }

        // Often in window title or toolbar
        let title = content.windowTitle
        if !title.isEmpty && title != "Photos" {
            return title
        }

        // Check for selected sidebar item
        for element in content.elements {
            if element.role == "AXOutlineRow" && element.isFocused {
                return element.title
            }
        }

        return nil
    }

    // MARK: - Time Correction Support

    /// Extract date/time from visible photo info for correction workflows
    public func extractPhotoDateTime() async -> PhotoDateTime? {
        guard let metadata = await currentPhotoInfo() else { return nil }

        var dateTime = PhotoDateTime()
        dateTime.originalDateString = metadata.dateString
        dateTime.originalTimeString = metadata.timeString
        dateTime.timezone = metadata.timezone
        dateTime.cameraModel = metadata.cameraModel

        // Parse into components if possible
        if let dateStr = metadata.dateString {
            dateTime.parsedDate = parseDate(dateStr)
        }

        return dateTime
    }

    /// Get photos grouped by date (for batch time correction)
    public func photosByDate() async -> [String: [PhotoItem]] {
        let photos = await visiblePhotos()
        var grouped: [String: [PhotoItem]] = [:]

        for photo in photos {
            let dateKey = photo.dateString ?? "Unknown"
            if grouped[dateKey] == nil {
                grouped[dateKey] = []
            }
            grouped[dateKey]?.append(photo)
        }

        return grouped
    }

    // MARK: - Travel Log Support

    /// Extract location data for travel log generation
    public func extractLocations() async -> [PhotoLocation] {
        let windows = walker.readAllWindows(bundleIdentifier: bundleID)
        var locations: [PhotoLocation] = []

        for window in windows {
            // Look for location text in photo info
            for element in window.elements {
                if let value = element.value ?? element.title {
                    if looksLikeLocation(value) {
                        var location = PhotoLocation()
                        location.name = value
                        location.source = .photoMetadata
                        locations.append(location)
                    }
                }
            }
        }

        return locations
    }

    /// Get photos with location data for mapping
    public func photosWithLocations() async -> [PhotoItem] {
        let photos = await visiblePhotos()
        return photos.filter { $0.location != nil }
    }

    /// Generate travel log summary from visible photos
    public func travelLogSummary() async -> TravelLog {
        var log = TravelLog()

        let photos = await visiblePhotos()
        let locations = await extractLocations()

        log.photoCount = photos.count
        log.uniqueLocations = Array(Set(locations.map { $0.name }))

        // Group by date for timeline
        let byDate = await photosByDate()
        log.dateRange = byDate.keys.sorted()

        // Extract camera info
        if let metadata = await currentPhotoInfo() {
            log.cameras.insert(metadata.cameraModel ?? "Unknown")
        }

        return log
    }

    /// Check if Photos is showing Places view
    public func isInPlacesView() async -> Bool {
        guard let content = walker.readFocusedWindow() else { return false }

        // Places view has map elements
        for element in content.elements {
            if element.role == "AXMap" || element.role?.contains("Map") == true {
                return true
            }
            if let title = element.title, title.contains("Places") {
                return true
            }
        }

        return false
    }

    // MARK: - Utilities

    /// Check if Photos.app is running
    public func isPhotosRunning() -> Bool {
        ApplicationReader().isApplicationRunning(bundleID)
    }

    /// Check if in edit mode
    public func isEditing() async -> Bool {
        guard let content = walker.readFocusedWindow() else { return false }

        for element in content.elements {
            if let title = element.title {
                if title.contains("Adjust") || title.contains("Edit") ||
                   title.contains("Filters") || title.contains("Crop") {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Private Parsing

    private func parseSelectedPhotos(from content: AccessibilityWindowContent) -> [PhotoItem] {
        var photos: [PhotoItem] = []

        for element in content.elements {
            if element.isFocused || element.role == "AXImage" {
                if let title = element.title ?? element.description {
                    var photo = PhotoItem()
                    photo.title = title
                    photo.isSelected = element.isFocused
                    photos.append(photo)
                }
            }
        }

        return photos
    }

    private func parsePhotos(from window: AccessibilityWindowContent) -> [PhotoItem] {
        var photos: [PhotoItem] = []

        for element in window.elements {
            if element.role == "AXImage" || element.role == "AXButton" {
                if let title = element.title ?? element.description {
                    // Filter out UI elements
                    if !isUIElement(title) {
                        var photo = PhotoItem()
                        photo.title = title

                        // Try to extract date from title
                        if let date = extractDate(from: title) {
                            photo.dateString = date
                        }

                        photos.append(photo)
                    }
                }
            }
        }

        return photos
    }

    private func parseMetadata(from content: AccessibilityWindowContent) -> PhotoMetadata? {
        var metadata = PhotoMetadata()
        var foundData = false

        for element in content.elements {
            guard let value = element.value ?? element.title else { continue }

            // Date patterns
            if containsDate(value) {
                metadata.dateString = value
                foundData = true
            }

            // Time patterns
            if containsTime(value) {
                metadata.timeString = value
                foundData = true
            }

            // Camera model
            if value.contains("iPhone") || value.contains("Canon") ||
               value.contains("Nikon") || value.contains("Sony") ||
               value.contains("Camera") || value.contains("DSLR") {
                metadata.cameraModel = value
                foundData = true
            }

            // Location
            if looksLikeLocation(value) {
                metadata.location = value
                foundData = true
            }

            // Dimensions
            if value.contains("×") || value.contains("x") {
                let pattern = #"\d+\s*[×x]\s*\d+"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
                    metadata.dimensions = value
                    foundData = true
                }
            }

            // File size
            if value.contains("MB") || value.contains("KB") || value.contains("GB") {
                metadata.fileSize = value
                foundData = true
            }

            // Timezone
            if value.contains("GMT") || value.contains("UTC") ||
               value.contains("EST") || value.contains("PST") ||
               value.contains("Time Zone") {
                metadata.timezone = value
                foundData = true
            }
        }

        return foundData ? metadata : nil
    }

    private func isAlbumName(_ text: String) -> Bool {
        let systemAlbums = ["Recents", "Favorites", "People", "Places", "Imports",
                           "Hidden", "Recently Deleted", "Screenshots", "Selfies",
                           "Portrait", "Panoramas", "Videos", "Slo-mo", "Time-lapse",
                           "Bursts", "Live Photos", "Depth Effect", "Long Exposure"]
        return systemAlbums.contains(text) || !text.contains(".")
    }

    private func isUIElement(_ name: String) -> Bool {
        let uiElements = ["Close", "Zoom", "Minimize", "Share", "Edit", "Info",
                         "Rotate", "Favorite", "Delete", "Add to", "More"]
        return uiElements.contains { name.hasPrefix($0) }
    }

    private func containsDate(_ text: String) -> Bool {
        let patterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,
            #"\d{4}-\d{2}-\d{2}"#,
            #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    private func containsTime(_ text: String) -> Bool {
        let pattern = #"\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM|am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        return false
    }

    private func extractDate(from text: String) -> String? {
        let patterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,
            #"\d{4}-\d{2}-\d{2}"#,
            #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s*\d{4}"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    private func parseDate(_ text: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy", "yyyy-MM-dd", "MMM d, yyyy", "MMMM d, yyyy"
        ]

        let formatter = DateFormatter()
        for format in formatters {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    private func looksLikeLocation(_ text: String) -> Bool {
        // Common location indicators
        let locationKeywords = ["Street", "Ave", "Road", "Rd", "Boulevard", "Blvd",
                                "Drive", "Dr", "Lane", "Ln", "Way", "Court", "Ct",
                                "City", "Town", "County", "State", "Country",
                                "Airport", "Beach", "Park", "Mountain", "Lake",
                                "Restaurant", "Hotel", "Museum", "Store"]

        // Check for GPS coordinates
        let coordPattern = #"-?\d{1,3}\.\d+,\s*-?\d{1,3}\.\d+"#
        if let regex = try? NSRegularExpression(pattern: coordPattern),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }

        // Check for location keywords
        return locationKeywords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}

// MARK: - Data Structures

public struct PhotoItem: Sendable {
    public var title: String = ""
    public var dateString: String?
    public var timeString: String?
    public var location: String?
    public var isSelected: Bool = false
    public var isFavorite: Bool = false

    public init() {}

    public var summary: String {
        var parts = [title]
        if let date = dateString { parts.append(date) }
        if let location = location { parts.append(location) }
        return parts.joined(separator: " - ")
    }
}

public struct PhotoMetadata: Sendable {
    public var dateString: String?
    public var timeString: String?
    public var timezone: String?
    public var location: String?
    public var cameraModel: String?
    public var dimensions: String?
    public var fileSize: String?
    public var aperture: String?
    public var shutterSpeed: String?
    public var iso: String?
    public var focalLength: String?

    public init() {}

    public var summary: String {
        var lines: [String] = []
        if let date = dateString { lines.append("Date: \(date)") }
        if let time = timeString { lines.append("Time: \(time)") }
        if let tz = timezone { lines.append("Timezone: \(tz)") }
        if let loc = location { lines.append("Location: \(loc)") }
        if let cam = cameraModel { lines.append("Camera: \(cam)") }
        if let dim = dimensions { lines.append("Size: \(dim)") }
        return lines.joined(separator: "\n")
    }
}

public struct PhotoDateTime: Sendable {
    public var originalDateString: String?
    public var originalTimeString: String?
    public var timezone: String?
    public var cameraModel: String?
    public var parsedDate: Date?

    public init() {}

    /// Suggested corrected date/time (for time zone issues)
    public func correctedForTimezone(_ targetTimezone: TimeZone) -> Date? {
        guard let date = parsedDate else { return nil }
        // Would apply timezone correction logic here
        return date
    }
}

public struct PhotoLocation: Sendable, Hashable {
    public var name: String = ""
    public var latitude: Double?
    public var longitude: Double?
    public var source: LocationSource = .photoMetadata

    public enum LocationSource: String, Sendable {
        case photoMetadata
        case gps
        case manual
        case inferred
    }

    public init() {}

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    public static func == (lhs: PhotoLocation, rhs: PhotoLocation) -> Bool {
        lhs.name == rhs.name
    }
}

public struct TravelLog: Sendable {
    public var photoCount: Int = 0
    public var uniqueLocations: [String] = []
    public var dateRange: [String] = []
    public var cameras: Set<String> = []

    public init() {}

    public var summary: String {
        """
        Travel Log Summary
        ==================
        Photos: \(photoCount)
        Locations: \(uniqueLocations.count)
        Date Range: \(dateRange.first ?? "?") to \(dateRange.last ?? "?")
        Cameras: \(cameras.joined(separator: ", "))

        Locations visited:
        \(uniqueLocations.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    /// Generate markdown travel log
    public func asMarkdown() -> String {
        """
        # Travel Log

        **\(photoCount) photos** across **\(uniqueLocations.count) locations**

        ## Timeline
        - Start: \(dateRange.first ?? "Unknown")
        - End: \(dateRange.last ?? "Unknown")

        ## Locations
        \(uniqueLocations.map { "- \($0)" }.joined(separator: "\n"))

        ## Equipment
        \(cameras.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}
