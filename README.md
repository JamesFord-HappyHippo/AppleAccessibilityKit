# AppleAccessibilityKit

A Swift package for reading macOS application content via the Accessibility API. Extract text, UI elements, and semantic context from any application - 100x faster than OCR with perfect accuracy.

## Features

- **Universal Application Reading** - Read content from any macOS app
- **Specialized Readers** - Built-in support for Calendar, Mail, and IDEs
- **IDE Support** - Xcode, Unity, Godot, VS Code, Android Studio, and more
- **LLM-Ready Output** - Get context formatted for AI consumption
- **Zero Dependencies** - Pure Swift, uses only Apple frameworks

## Requirements

- macOS 13.0+
- Swift 5.9+
- Accessibility permission granted to your app

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/JamesFord-HappyHippo/AppleAccessibilityKit.git", from: "1.0.0")
]
```

## Usage

### Basic Reading

```swift
import AppleAccessibilityKit

// Read the focused window
if let content = await AppleAccessibilityKit.readFocusedWindow() {
    print(content.asPlainText())
}

// Read a specific application
let windows = await AppleAccessibilityKit.read(bundleId: "com.apple.Safari")

// Get LLM-ready context
let context = await AppleAccessibilityKit.llmContext()
```

### Calendar Reading

```swift
// Get visible calendar events
let events = await AppleAccessibilityKit.calendar.visibleEvents()

for event in events {
    print(event.summary)
}

// Check if event is a meeting
if AppleAccessibilityKit.calendar.isMeeting(event) {
    if let link = AppleAccessibilityKit.calendar.meetingLink(from: event) {
        print("Join: \(link)")
    }
}
```

### Mail Reading

```swift
// Get visible emails
let emails = await AppleAccessibilityKit.mail.visibleEmails()

// Get current email being viewed
if let email = await AppleAccessibilityKit.mail.currentEmail() {
    print(email.summary)
}
```

### IDE Reading

```swift
// Read Xcode content
if case .success(let windows) = await AppleAccessibilityKit.ide.read(ide: .xcode) {
    for window in windows {
        print(window.asPlainText())
    }
}

// Get compiler errors
let errors = await AppleAccessibilityKit.ide.compilerErrors(ide: .xcode)
for error in errors {
    print(error.summary)
}

// Get current file being edited
if let file = await AppleAccessibilityKit.ide.currentFile(ide: .unity) {
    print("Editing: \(file)")
}
```

### Permission Handling

```swift
// Check permission
if !AppleAccessibilityKit.hasPermission() {
    // Request permission (shows system prompt)
    AppleAccessibilityKit.requestPermission()

    // Or open System Settings directly
    AppleAccessibilityKit.openSettings()
}
```

### Text Extraction Utilities

```swift
import AppleAccessibilityKit

let text = "Meeting at 2:30 PM, join at https://zoom.us/j/123"

// Extract URLs
let urls = TextExtraction.extractURLs(from: text)

// Extract meeting links specifically
let meetingLinks = TextExtraction.extractMeetingURLs(from: text)

// Extract times
let times = TextExtraction.extractTimes(from: text)

// Extract error locations from compiler output
let errors = TextExtraction.extractErrorLocations(from: "/path/file.swift:42:10: error: msg")
```

## Supported IDEs

| IDE | Bundle ID | Notes |
|-----|-----------|-------|
| Xcode | com.apple.dt.Xcode | Full support |
| Unity | com.unity3d.UnityEditor | Full support |
| Godot | org.godotengine.godot | Full support |
| VS Code | com.microsoft.VSCode | Full support |
| Android Studio | com.google.android.studio | Full support |
| IntelliJ IDEA | com.jetbrains.intellij | Full support |
| JetBrains Fleet | com.jetbrains.fleet | Full support |

## Architecture

```
AppleAccessibilityKit/
├── Core/
│   ├── AccessibilityElement.swift      # Data structures
│   └── AccessibilityTreeWalker.swift   # Low-level AXUIElement API
├── Readers/
│   ├── ApplicationReader.swift         # Generic application reading
│   ├── CalendarReader.swift            # Calendar.app support
│   ├── MailReader.swift                # Mail.app support
│   └── IDEReader.swift                 # IDE support
└── Utilities/
    ├── BundleIdentifiers.swift         # Known app bundle IDs
    └── TextExtraction.swift            # Text parsing utilities
```

## Performance

The Accessibility API is **100x faster than OCR** because it reads the actual UI element data rather than performing image recognition:

| Method | Speed | Accuracy | Background Windows |
|--------|-------|----------|-------------------|
| Accessibility API | ~5ms | 100% | Yes |
| Vision OCR | ~500ms | 95-99% | No |

## Security & Privacy

- Requires **Accessibility permission** in System Settings
- Only reads publicly exposed UI element data
- No screen recording or screenshots needed
- Works even when windows are in background

## License

MIT License - See LICENSE file for details.

## Credits

Extracted from [Harvey Decision System](https://github.com/JamesFord-HappyHippo/EquilateralAgents-Personal) by Equilateral AI (Pareidolia LLC).
