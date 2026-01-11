import XCTest
@testable import AppleAccessibilityKit

final class TextExtractionTests: XCTestCase {

    func testExtractURLs() {
        let text = "Visit https://example.com and http://test.org/path for more info"
        let urls = TextExtraction.extractURLs(from: text)

        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls.contains("https://example.com"))
        XCTAssertTrue(urls.contains("http://test.org/path"))
    }

    func testExtractMeetingURLs() {
        let text = """
        Join us at https://zoom.us/j/123456789
        or https://meet.google.com/abc-defg-hij
        regular link: https://example.com
        """

        let meetingLinks = TextExtraction.extractMeetingURLs(from: text)

        XCTAssertEqual(meetingLinks.count, 2)
        XCTAssertTrue(meetingLinks.contains { $0.contains("zoom.us") })
        XCTAssertTrue(meetingLinks.contains { $0.contains("meet.google.com") })
    }

    func testExtractEmails() {
        let text = "Contact john@example.com or jane.doe@company.co.uk"
        let emails = TextExtraction.extractEmails(from: text)

        XCTAssertEqual(emails.count, 2)
        XCTAssertTrue(emails.contains("john@example.com"))
        XCTAssertTrue(emails.contains("jane.doe@company.co.uk"))
    }

    func testExtractTimes() {
        let text = "Meeting at 2:30 PM, ends at 3:00 pm, reminder at 14:00"
        let times = TextExtraction.extractTimes(from: text)

        XCTAssertGreaterThanOrEqual(times.count, 2)
        XCTAssertTrue(times.contains { $0.contains("2:30") })
    }

    func testExtractFilePaths() {
        let text = """
        Error in /Users/dev/project/file.swift
        Also check main.ts and utils.py
        """

        let paths = TextExtraction.extractFilePaths(from: text)

        XCTAssertGreaterThanOrEqual(paths.count, 1)
    }

    func testExtractErrorLocations() {
        let text = "/path/to/file.swift:42:10: error: unexpected token"
        let locations = TextExtraction.extractErrorLocations(from: text)

        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations[0].line, 42)
        XCTAssertEqual(locations[0].column, 10)
    }

    func testAnalyzeContentType() {
        XCTAssertEqual(TextExtraction.analyzeContentType("Error: Something failed"), .error)
        XCTAssertEqual(TextExtraction.analyzeContentType("Warning: Check this"), .warning)
        XCTAssertEqual(TextExtraction.analyzeContentType("Visit https://example.com"), .url)
        XCTAssertEqual(TextExtraction.analyzeContentType("Contact test@email.com"), .email)
        XCTAssertEqual(TextExtraction.analyzeContentType("Hello world"), .text)
    }
}
