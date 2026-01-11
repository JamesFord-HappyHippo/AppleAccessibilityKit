# AppleAccessibilityKit

A Swift package for reading AND interacting with macOS applications via the Accessibility API. Extract text, UI elements, and semantic context from any application - 100x faster than OCR with perfect accuracy. Now with full automation support.

## Features

- **Universal Application Reading** - Read content from any macOS app
- **UI Automation** - Click buttons, type text, navigate menus, scroll
- **Specialized Readers** - Calendar, Mail, IDEs, Browsers, Terminal, Notes, Finder
- **IDE Support** - Xcode, Unity, Godot, VS Code, Android Studio, and more
- **Browser Support** - Safari, Chrome, Firefox, Arc, Edge, Brave
- **Terminal Support** - Terminal.app, iTerm2, Warp, Alacritty, Kitty
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
    .package(url: "https://github.com/JamesFord-HappyHippo/AppleAccessibilityKit.git", from: "1.1.0")
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

### UI Automation (NEW in v1.1.0)

```swift
// Click a button by title
await AppleAccessibilityKit.actions.clickButton(title: "Save")

// Type text
AppleAccessibilityKit.actions.typeText("Hello World")

// Keyboard shortcuts
AppleAccessibilityKit.actions.pressKey(.s, modifiers: [.command])  // Cmd+S

// Navigate menus
await AppleAccessibilityKit.actions.selectMenuItem(path: ["File", "Save As..."])

// Scroll
AppleAccessibilityKit.actions.scrollDown(amount: 100)
```

### Browser Reading (NEW in v1.1.0)

```swift
// Get all tabs from Chrome
let tabs = await AppleAccessibilityKit.browser.tabs(browser: .chrome)

// Get current URL
if let url = await AppleAccessibilityKit.browser.currentURL() {
    print("Current page: \(url)")
}

// Get page content
if let content = await AppleAccessibilityKit.browser.pageContent() {
    print(content)
}

// Detect frontmost browser
if let browser = AppleAccessibilityKit.browser.detectFrontmostBrowser() {
    print("Using: \(browser.displayName)")
}
```

### Terminal Reading (NEW in v1.1.0)

```swift
// Read terminal output
if let output = await AppleAccessibilityKit.terminal.output() {
    print(output)
}

// Check for errors
if await AppleAccessibilityKit.terminal.hasError() {
    let errors = await AppleAccessibilityKit.terminal.errors()
    for error in errors {
        print("Error: \(error)")
    }
}

// Get last command
if let cmd = await AppleAccessibilityKit.terminal.lastCommand() {
    print("Last command: \(cmd)")
}

// Check if process is running
let running = await AppleAccessibilityKit.terminal.isProcessRunning()
```

### Notes Reading (NEW in v1.1.0)

```swift
// Get current note
if let note = await AppleAccessibilityKit.notes.currentNote() {
    print(note.plainText)
}

// List visible notes
let notes = await AppleAccessibilityKit.notes.notesList()

// Get folders
let folders = await AppleAccessibilityKit.notes.folders()
```

### Finder Reading (NEW in v1.1.0)

```swift
// Get selected files
let selected = await AppleAccessibilityKit.finder.selectedItems()

// Get current path
if let path = await AppleAccessibilityKit.finder.currentPath() {
    print("In: \(path)")
}

// Get visible items
let items = await AppleAccessibilityKit.finder.visibleItems()
```

### Calendar Reading

```swift
// Get visible calendar events
let events = await AppleAccessibilityKit.calendar.visibleEvents()

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
let text = "Meeting at 2:30 PM, join at https://zoom.us/j/123"

// Extract URLs
let urls = TextExtraction.extractURLs(from: text)

// Extract meeting links
let meetingLinks = TextExtraction.extractMeetingURLs(from: text)

// Extract times
let times = TextExtraction.extractTimes(from: text)

// Extract error locations from compiler output
let errors = TextExtraction.extractErrorLocations(from: "/path/file.swift:42:10: error: msg")
```

## Supported Applications

### IDEs

| IDE | Bundle ID | Notes |
|-----|-----------|-------|
| Xcode | com.apple.dt.Xcode | Full support |
| Unity | com.unity3d.UnityEditor | Full support |
| Godot | org.godotengine.godot | Full support |
| VS Code | com.microsoft.VSCode | Full support |
| Android Studio | com.google.android.studio | Full support |
| IntelliJ IDEA | com.jetbrains.intellij | Full support |
| JetBrains Fleet | com.jetbrains.fleet | Full support |

### Browsers

| Browser | Bundle ID |
|---------|-----------|
| Safari | com.apple.Safari |
| Chrome | com.google.Chrome |
| Firefox | org.mozilla.firefox |
| Edge | com.microsoft.edgemac |
| Arc | company.thebrowser.Browser |
| Brave | com.brave.Browser |

### Terminals

| Terminal | Bundle ID |
|----------|-----------|
| Terminal | com.apple.Terminal |
| iTerm2 | com.googlecode.iterm2 |
| Warp | dev.warp.Warp-Stable |
| Alacritty | org.alacritty |
| Kitty | net.kovidgoyal.kitty |

## Architecture

```
AppleAccessibilityKit/
├── Core/
│   ├── AccessibilityElement.swift      # Data structures
│   ├── AccessibilityTreeWalker.swift   # Low-level AXUIElement API
│   └── ActionPerformer.swift           # UI automation (click, type, etc.)
├── Readers/
│   ├── ApplicationReader.swift         # Generic application reading
│   ├── BrowserReader.swift             # Safari, Chrome, Firefox, etc.
│   ├── CalendarReader.swift            # Calendar.app
│   ├── FinderReader.swift              # Finder
│   ├── IDEReader.swift                 # Xcode, Unity, Godot, etc.
│   ├── MailReader.swift                # Mail.app
│   ├── NotesReader.swift               # Notes.app
│   └── TerminalReader.swift            # Terminal, iTerm, Warp
└── Utilities/
    ├── BundleIdentifiers.swift         # 79+ known app bundle IDs
    └── TextExtraction.swift            # URL, email, time parsing
```

## Performance

The Accessibility API is **100x faster than OCR** because it reads the actual UI element data:

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

## Changelog

### v1.1.0
- Added ActionPerformer for UI automation
- Added BrowserReader (Safari, Chrome, Firefox, Arc, Edge, Brave)
- Added TerminalReader (Terminal, iTerm, Warp, Alacritty, Kitty)
- Added NotesReader (Apple Notes)
- Added FinderReader
- Fixed Sendable conformance warnings

### v1.0.0
- Initial release
- Core accessibility tree walking
- Calendar, Mail, IDE readers
- Text extraction utilities
- 79 known bundle identifiers
