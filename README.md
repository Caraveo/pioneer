# Pioneer

A macOS-native SwiftUI application for visual, node-based AI code editing and systems architecture.

## Features

- **Visual Node Editor**: Create and connect nodes representing different project types
- **Multiple Project Types**: Support for macOS apps, iPhone apps, websites, and AWS backends
- **Code Editing**: Edit node code in Swift or Python
- **Generation Tools**: Generate complete projects from nodes
- **AWS Integration**: Deploy backends to AWS (stub implementation)
- **Theme Support**: Light, Dark, and System appearance modes

## Project Structure

```
Pioneer/
├── Sources/
│   ├── PioneerApp.swift          # Main app entry point
│   ├── Models/
│   │   ├── Node.swift             # Node data model
│   │   └── ProjectManager.swift   # Project state management
│   ├── Views/
│   │   ├── ContentView.swift      # Main content view
│   │   ├── SidebarView.swift      # Node list sidebar
│   │   ├── ToolbarView.swift      # Toolbar with actions
│   │   ├── NodeCanvasView.swift   # Visual node editor canvas
│   │   └── CodeEditorView.swift   # Code editing panel
│   └── Services/
│       └── PythonBridge.swift     # Python integration layer
├── Package.swift                  # Swift Package Manager manifest
└── README.md                      # This file
```

## Building and Running

### Prerequisites

- macOS 13.0 or later
- Swift 5.9 or later
- Python 3 (for code generation features)

### Build

```bash
swift build
```

### Run

```bash
swift run Pioneer
```

Or build and run in one command:

```bash
swift run
```

### Build App Bundle with Icon

To create a proper macOS app bundle with the Pioneer.png icon:

1. Place your `Pioneer.png` icon file in the project root directory
2. Run the build script:

```bash
./build-app.sh
```

This will create a `Pioneer.app` bundle in the current directory with the icon properly configured. You can then run it with:

```bash
open Pioneer.app
```

The script will automatically:
- Build the app in release mode
- Create the app bundle structure
- Convert the PNG icon to ICNS format (if `iconutil` is available)
- Set up the Info.plist with the icon reference

## Usage

1. **Create Nodes**: Click the "+" button in the sidebar or use Cmd+N to create a new node
2. **Edit Nodes**: Select a node to edit its code in the code editor panel
3. **Connect Nodes**: Nodes can be connected to represent dependencies (visual connections)
4. **Generate Projects**: Use the "Generate" menu in the toolbar to:
   - Generate iPhone App
   - Generate Website
   - Deploy Backend to AWS

## Node Types

- **macOS App**: Native macOS applications
- **iPhone App**: iOS applications using SwiftUI
- **Website**: Web projects (HTML/CSS/JS)
- **AWS Backend**: Backend infrastructure for AWS
- **Custom**: Custom project types

## Code Languages

Nodes support editing code in:
- **Swift**: For macOS and iOS apps
- **Python**: For backend services and automation

## Architecture

The app is built with a clean architecture that separates:
- **Models**: Data structures and business logic
- **Views**: SwiftUI views for the UI
- **Services**: External integrations (Python bridge)

This architecture makes it easy to plug in future LLM/autogen features into the node system.

## Python Integration

Python scripts are located in the `PythonScripts` directory (created at runtime). The `PythonBridge` class handles:
- Code generation for different project types
- AWS deployment (stub implementation)
- Communication between Swift and Python

## Future Enhancements

- LLM integration for automatic code generation
- Autogen features for autonomous project creation
- Real AWS deployment integration
- Export/import project functionality
- Version control integration
- Collaborative editing

## License

This project is provided as-is for development purposes.

