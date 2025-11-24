# Node Editor Flow Verification

## ✅ Each Node Has Its Own Editor Instance

### 1. Node Creation
- **Location**: `ProjectManager.createNewNode()`
- **Process**:
  1. Creates new `Node` with unique `UUID` (node.id)
  2. Calls `getOrCreateMainFile()` which ensures main file exists
  3. Main file gets its own unique `UUID` (file.id)
  4. Node is added to `nodes` array
  5. Project structure is created in `~/.pioneer/Projects/{node.id}/`

### 2. Editor Instance Creation
- **Location**: `CodeEditorView` → `MonacoEditorView`
- **Unique ID**: `.id("\(node.id)-\(file.id)")`
- **Result**: SwiftUI creates a **new** `MonacoEditorView` instance for each node+file combination
- **WebView Storage**: Each editor instance stores its webView in `webViewStore["\(node.id)-\(file.id)"]`
- **Isolation**: Each editor instance is completely isolated

### 3. File Management
- **Each Node Has**:
  - `files: [ProjectFile]` - Array of all files in the node
  - `selectedFileId: UUID?` - Currently selected file
  - `projectPath: String?` - Path to node's project directory
  
- **Each File Has**:
  - `id: UUID` - Unique identifier
  - `path: String` - Relative path from project root
  - `content: String` - File content
  - `language: CodeLanguage` - File's language

### 4. Content Binding
- **Binding Source**: Always reads from `projectManager.nodes[nodeIndex].files[fileIndex].content`
- **Binding Target**: Updates `projectManager.nodes[nodeIndex].files[fileIndex].content`
- **No Cross-Contamination**: Each node's content is stored separately

### 5. Project Directory Structure
```
~/.pioneer/Projects/
  ├── {node1.id}/          # Node 1's project
  │   ├── Sources/
  │   │   └── app.swift     # Node 1's main file
  │   └── ...
  ├── {node2.id}/          # Node 2's project
  │   ├── src/
  │   │   └── main.py      # Node 2's main file
  │   └── ...
  └── {node3.id}/          # Node 3's project
      └── ...
```

## ✅ Flow Verification

### Scenario 1: Create New Node
1. User clicks "New Node"
2. `createNewNode()` called
3. New node created with unique ID
4. Main file created automatically (e.g., `app.swift` for Swift)
5. Node added to array
6. Project directory created: `~/.pioneer/Projects/{node.id}/`
7. Editor instance created with ID: `"{node.id}-{file.id}"`

### Scenario 2: Switch Between Nodes
1. User clicks Node A → Editor A shown (ID: `"{nodeA.id}-{fileA.id}"`)
2. User types in Editor A → Content saved to `nodes[nodeA].files[fileA].content`
3. User clicks Node B → 
   - Editor A's content saved from Monaco
   - Editor B shown (ID: `"{nodeB.id}-{fileB.id}"`)
   - Editor B loads `nodes[nodeB].files[fileB].content`
4. Each editor maintains its own state

### Scenario 3: Edit Multiple Nodes
1. Node A selected → Editor A shows Node A's code
2. User edits → Saved to Node A's file
3. Node B selected → Editor B shows Node B's code (different instance)
4. User edits → Saved to Node B's file
5. Switch back to Node A → Editor A shows Node A's code (preserved)

## ✅ Guarantees

1. **Every node has a main file** - Created automatically in `Node.init()`
2. **Each node has unique project directory** - By `node.id`
3. **Each editor instance is unique** - By `.id("\(node.id)-\(file.id)")`
4. **Content is isolated** - Each node's files array is separate
5. **No overwriting** - Each node maintains its own state

## ✅ Main File Names by Language

- Swift: `Sources/app.swift`
- Python: `src/main.py`
- JavaScript: `src/index.js`
- TypeScript: `src/index.ts`
- HTML: `index.html`
- CSS: `css/style.css`
- And more...

Each node gets its own main file based on its language!

