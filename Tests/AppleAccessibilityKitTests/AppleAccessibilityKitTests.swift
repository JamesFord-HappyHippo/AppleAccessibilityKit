import XCTest
@testable import AppleAccessibilityKit

final class AppleAccessibilityKitTests: XCTestCase {

    // MARK: - Data Structure Tests

    func testAccessibilityWindowContentInit() {
        let content = AccessibilityWindowContent()
        XCTAssertTrue(content.textContent.isEmpty)
        XCTAssertTrue(content.labels.isEmpty)
        XCTAssertTrue(content.editableText.isEmpty)
        XCTAssertTrue(content.elements.isEmpty)
    }

    func testAccessibilityWindowContentAsPlainText() {
        var content = AccessibilityWindowContent()
        content.editableText = ["Hello", "World"]
        content.textContent = ["Label 1"]
        content.labels = ["Button"]

        let text = content.asPlainText()

        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("World"))
        XCTAssertTrue(text.contains("Label 1"))
        XCTAssertTrue(text.contains("Button"))
    }

    func testAccessibilityWindowContentContains() {
        var content = AccessibilityWindowContent()
        content.textContent = ["Error: Something went wrong"]

        XCTAssertTrue(content.contains("error", caseSensitive: false))
        XCTAssertFalse(content.contains("error", caseSensitive: true))
        XCTAssertTrue(content.contains("Error", caseSensitive: true))
    }

    func testAccessibilityElementInit() {
        let element = AccessibilityElement()
        XCTAssertNil(element.role)
        XCTAssertNil(element.title)
        XCTAssertNil(element.value)
        XCTAssertFalse(element.isFocused)
        XCTAssertEqual(element.childCount, 0)
    }

    // MARK: - Calendar Event Tests

    func testCalendarEventSummary() {
        var event = CalendarEvent()
        event.title = "Team Meeting"
        event.timeString = "2:00 PM"
        event.location = "Conference Room"
        event.attendees = ["alice@example.com", "bob@example.com"]

        let summary = event.summary

        XCTAssertTrue(summary.contains("Team Meeting"))
        XCTAssertTrue(summary.contains("2:00 PM"))
        XCTAssertTrue(summary.contains("Conference Room"))
        XCTAssertTrue(summary.contains("alice@example.com"))
    }

    // MARK: - Mail Message Tests

    func testMailMessageSummary() {
        var message = MailMessage()
        message.subject = "Re: Project Update"
        message.from = "sender@example.com"
        message.to = "receiver@example.com"
        message.dateString = "Today"

        let summary = message.summary

        XCTAssertTrue(summary.contains("Re: Project Update"))
        XCTAssertTrue(summary.contains("sender@example.com"))
        XCTAssertTrue(summary.contains("Today"))
    }

    // MARK: - Compiler Error Tests

    func testCompilerErrorSummary() {
        var error = CompilerError()
        error.file = "ViewController.swift"
        error.line = 42
        error.message = "Cannot find type 'Foo'"
        error.severity = .error

        let summary = error.summary

        XCTAssertTrue(summary.contains("ViewController.swift"))
        XCTAssertTrue(summary.contains("42"))
        XCTAssertTrue(summary.contains("Cannot find type"))
    }

    // MARK: - IDE Tests

    func testIDEDisplayNames() {
        XCTAssertEqual(IDEReader.IDE.xcode.displayName, "Xcode")
        XCTAssertEqual(IDEReader.IDE.unity.displayName, "Unity")
        XCTAssertEqual(IDEReader.IDE.godot.displayName, "Godot")
        XCTAssertEqual(IDEReader.IDE.vsCode.displayName, "VS Code")
    }

    func testIDEBundleIdentifiers() {
        XCTAssertEqual(IDEReader.IDE.xcode.rawValue, "com.apple.dt.Xcode")
        XCTAssertEqual(IDEReader.IDE.unity.rawValue, "com.unity3d.UnityEditor")
    }

    // MARK: - Bundle Identifiers Tests

    func testAppleBundleIdentifiers() {
        XCTAssertEqual(AppBundle.xcode, "com.apple.dt.Xcode")
        XCTAssertEqual(AppBundle.calendar, "com.apple.iCal")
        XCTAssertEqual(AppBundle.mail, "com.apple.mail")
        XCTAssertEqual(AppBundle.safari, "com.apple.Safari")
    }

    func testIDEBundleIdentifiersFromAppBundle() {
        XCTAssertEqual(AppBundle.vsCode, "com.microsoft.VSCode")
        XCTAssertEqual(AppBundle.unity, "com.unity3d.UnityEditor")
        XCTAssertEqual(AppBundle.godot, "org.godotengine.godot")
    }

    // MARK: - Permission Tests (Non-destructive)

    @MainActor
    func testPermissionCheckDoesNotPrompt() {
        // This should NOT trigger a permission prompt
        let reader = ApplicationReader()
        _ = reader.checkPermission() // Just verify it doesn't crash
    }
}
