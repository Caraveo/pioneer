import SwiftUI
import AppKit

struct SwiftCodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    let editorInstanceId: String
    
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    
    /// Get the effective color scheme (system-aware)
    private var effectiveColorScheme: ColorScheme {
        if appearance == .system {
            let isDark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
            return isDark ? .dark : .light
        } else {
            return appearance == .dark ? .dark : .light
        }
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Create text storage system
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        
        let textView = CodeTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.language = language
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        
        // Set font
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = effectiveColorScheme == .dark ? NSColor.white : NSColor.black
        
        // Set background
        textView.backgroundColor = effectiveColorScheme == .dark 
            ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
            : NSColor.white
        
        // Set text container
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        
        // Enable line wrapping
        textView.textContainer?.lineFragmentPadding = 0
        
        // Set initial text
        textView.string = text
        
        // Apply syntax highlighting
        context.coordinator.applySyntaxHighlighting(to: textView)
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.language = language
        context.coordinator.instanceId = editorInstanceId
        
        // Ensure text view can receive focus
        DispatchQueue.main.async {
            if let window = scrollView.window {
                window.makeFirstResponder(textView)
            }
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CodeTextView else { return }
        
        // Update language if changed
        if context.coordinator.language != language {
            context.coordinator.language = language
            textView.language = language
            context.coordinator.applySyntaxHighlighting(to: textView)
        }
        
        // Update text if changed (but not if we're the source of the change)
        if !context.coordinator.isUpdatingFromTextChange && textView.string != text {
            textView.string = text
            context.coordinator.applySyntaxHighlighting(to: textView)
        }
        
        // Update theme if changed
        let isDark = effectiveColorScheme == .dark
        textView.textColor = isDark ? .white : .black
        textView.backgroundColor = isDark 
            ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
            : NSColor.white
        context.coordinator.applySyntaxHighlighting(to: textView)
        
        // Ensure text view can receive keyboard input
        if textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SwiftCodeEditorView
        weak var textView: CodeTextView?
        var language: CodeLanguage
        var instanceId: String = ""
        var isUpdatingFromTextChange = false
        
        init(_ parent: SwiftCodeEditorView) {
            self.parent = parent
            self.language = parent.language
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            isUpdatingFromTextChange = true
            parent.text = textView.string
            isUpdatingFromTextChange = false
            
            // Re-apply syntax highlighting after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.applySyntaxHighlighting(to: textView)
            }
        }
        
        func applySyntaxHighlighting(to textView: NSTextView) {
            let text = textView.string
            let isDark = parent.effectiveColorScheme == .dark
            let storage = textView.textStorage!
            
            // Reset attributes
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            
            // Base attributes
            let baseColor = isDark ? NSColor.white : NSColor.black
            let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
            storage.addAttribute(.font, value: baseFont, range: fullRange)
            
            // Apply syntax highlighting based on language
            switch language {
            case .swift:
                highlightSwift(text: text, storage: storage, isDark: isDark)
            case .python:
                highlightPython(text: text, storage: storage, isDark: isDark)
            case .javascript, .typescript:
                highlightJavaScript(text: text, storage: storage, isDark: isDark)
            case .html:
                highlightHTML(text: text, storage: storage, isDark: isDark)
            case .css:
                highlightCSS(text: text, storage: storage, isDark: isDark)
            case .yaml, .kubernetes, .cloudformation:
                highlightYAML(text: text, storage: storage, isDark: isDark)
            case .json:
                highlightJSON(text: text, storage: storage, isDark: isDark)
            case .sql:
                highlightSQL(text: text, storage: storage, isDark: isDark)
            case .bash:
                highlightBash(text: text, storage: storage, isDark: isDark)
            case .markdown:
                highlightMarkdown(text: text, storage: storage, isDark: isDark)
            default:
                break
            }
        }
        
        // Swift syntax highlighting
        private func highlightSwift(text: String, storage: NSTextStorage, isDark: Bool) {
            let keywords = ["func", "var", "let", "if", "else", "for", "while", "return", "import", "struct", "class", "enum", "protocol", "extension", "private", "public", "internal", "static", "override", "init", "deinit", "guard", "switch", "case", "default", "break", "continue", "true", "false", "nil", "self", "super", "try", "catch", "throw", "throws", "async", "await", "inout", "mutating", "nonmutating", "convenience", "required", "final", "open", "weak", "unowned", "lazy", "optional", "some", "any", "where", "as", "is", "in"]
            let types = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Any", "AnyObject", "Void"]
            
            highlightKeywords(keywords, color: isDark ? NSColor.systemOrange : NSColor.systemPurple, in: text, storage: storage)
            highlightKeywords(types, color: isDark ? NSColor.systemBlue : NSColor.systemBlue, in: text, storage: storage)
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // Python syntax highlighting
        private func highlightPython(text: String, storage: NSTextStorage, isDark: Bool) {
            let keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "pass", "break", "continue", "yield", "lambda", "and", "or", "not", "in", "is", "None", "True", "False"]
            
            highlightKeywords(keywords, color: isDark ? NSColor.systemPurple : NSColor.systemPurple, in: text, storage: storage)
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // JavaScript/TypeScript syntax highlighting
        private func highlightJavaScript(text: String, storage: NSTextStorage, isDark: Bool) {
            let keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "return", "import", "export", "class", "extends", "super", "this", "new", "typeof", "instanceof", "try", "catch", "finally", "throw", "async", "await", "true", "false", "null", "undefined"]
            
            highlightKeywords(keywords, color: isDark ? NSColor.systemPurple : NSColor.systemPurple, in: text, storage: storage)
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // HTML syntax highlighting
        private func highlightHTML(text: String, storage: NSTextStorage, isDark: Bool) {
            let tagColor = isDark ? NSColor.systemBlue : NSColor.systemBlue
            let attributeColor = isDark ? NSColor.systemOrange : NSColor.systemOrange
            
            // Highlight tags
            let tagPattern = "<(/?)([a-zA-Z][a-zA-Z0-9]*)\\b"
            if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    storage.addAttribute(.foregroundColor, value: tagColor, range: match.range)
                }
            }
            
            // Highlight attributes
            let attrPattern = "\\b([a-zA-Z-]+)\\s*="
            if let regex = try? NSRegularExpression(pattern: attrPattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        storage.addAttribute(.foregroundColor, value: attributeColor, range: match.range(at: 1))
                    }
                }
            }
            
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // CSS syntax highlighting
        private func highlightCSS(text: String, storage: NSTextStorage, isDark: Bool) {
            let selectorColor = isDark ? NSColor.systemBlue : NSColor.systemBlue
            let propertyColor = isDark ? NSColor.systemOrange : NSColor.systemOrange
            
            // Highlight selectors
            let selectorPattern = "^([a-zA-Z0-9#.\\[\\]:\\s,]+)\\s*\\{"
            if let regex = try? NSRegularExpression(pattern: selectorPattern, options: [.anchorsMatchLines]) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        storage.addAttribute(.foregroundColor, value: selectorColor, range: match.range(at: 1))
                    }
                }
            }
            
            // Highlight properties
            let propertyPattern = "\\s*([a-zA-Z-]+)\\s*:"
            if let regex = try? NSRegularExpression(pattern: propertyPattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        storage.addAttribute(.foregroundColor, value: propertyColor, range: match.range(at: 1))
                    }
                }
            }
        }
        
        // YAML syntax highlighting
        private func highlightYAML(text: String, storage: NSTextStorage, isDark: Bool) {
            let keyColor = isDark ? NSColor.systemBlue : NSColor.systemBlue
            
            // Highlight keys
            let keyPattern = "^\\s*([a-zA-Z0-9_-]+)\\s*:"
            if let regex = try? NSRegularExpression(pattern: keyPattern, options: [.anchorsMatchLines]) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        storage.addAttribute(.foregroundColor, value: keyColor, range: match.range(at: 1))
                    }
                }
            }
            
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // JSON syntax highlighting
        private func highlightJSON(text: String, storage: NSTextStorage, isDark: Bool) {
            let keyColor = isDark ? NSColor.systemBlue : NSColor.systemBlue
            
            // Highlight keys
            let keyPattern = "\"([^\"]+)\"\\s*:"
            if let regex = try? NSRegularExpression(pattern: keyPattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    storage.addAttribute(.foregroundColor, value: keyColor, range: match.range)
                }
            }
            
            highlightStrings(in: text, storage: storage, isDark: isDark)
        }
        
        // SQL syntax highlighting
        private func highlightSQL(text: String, storage: NSTextStorage, isDark: Bool) {
            let keywords = ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "AS", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "IS", "NULL", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN"]
            
            highlightKeywords(keywords, color: isDark ? NSColor.systemPurple : NSColor.systemPurple, in: text, storage: storage)
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // Bash syntax highlighting
        private func highlightBash(text: String, storage: NSTextStorage, isDark: Bool) {
            let keywords = ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local"]
            
            highlightKeywords(keywords, color: isDark ? NSColor.systemPurple : NSColor.systemPurple, in: text, storage: storage)
            highlightStrings(in: text, storage: storage, isDark: isDark)
            highlightComments(in: text, storage: storage, isDark: isDark)
        }
        
        // Markdown syntax highlighting
        private func highlightMarkdown(text: String, storage: NSTextStorage, isDark: Bool) {
            let headingColor = isDark ? NSColor.systemBlue : NSColor.systemBlue
            let boldColor = isDark ? NSColor.systemOrange : NSColor.systemOrange
            
            // Headers
            let headerPattern = "^(#{1,6})\\s+(.+)$"
            if let regex = try? NSRegularExpression(pattern: headerPattern, options: [.anchorsMatchLines]) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    if match.numberOfRanges > 2 {
                        storage.addAttribute(.foregroundColor, value: headingColor, range: match.range(at: 2))
                        if let font = storage.attribute(.font, at: match.range(at: 2).location, effectiveRange: nil) as? NSFont {
                            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: font.pointSize), range: match.range(at: 2))
                        }
                    }
                }
            }
            
            // Bold
            let boldPattern = "\\*\\*([^*]+)\\*\\*"
            if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                for match in matches {
                    if match.numberOfRanges > 1 {
                        storage.addAttribute(.foregroundColor, value: boldColor, range: match.range(at: 1))
                    }
                }
            }
        }
        
        // Helper functions
        private func highlightKeywords(_ keywords: [String], color: NSColor, in text: String, storage: NSTextStorage) {
            for keyword in keywords {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                    for match in matches {
                        storage.addAttribute(.foregroundColor, value: color, range: match.range)
                    }
                }
            }
        }
        
        private func highlightStrings(in text: String, storage: NSTextStorage, isDark: Bool) {
            let stringColor = isDark ? NSColor.systemGreen : NSColor.systemGreen
            let patterns = [
                "\"([^\"]|\\\\.)*\"",  // Double quotes
                "'([^']|\\\\.)*'",     // Single quotes
                "`([^`]|\\\\.)*`"       // Backticks
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                    for match in matches {
                        storage.addAttribute(.foregroundColor, value: stringColor, range: match.range)
                    }
                }
            }
        }
        
        private func highlightComments(in text: String, storage: NSTextStorage, isDark: Bool) {
            let commentColor = isDark ? NSColor.systemGray : NSColor.systemGray
            let patterns = [
                "//.*$",           // Single line comments
                "/\\*[\\s\\S]*?\\*/" // Multi-line comments
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators]) {
                    let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
                    for match in matches {
                        storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                    }
                }
            }
        }
    }
}

// Custom NSTextView subclass for code editing
class CodeTextView: NSTextView {
    var language: CodeLanguage = .swift
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupCodeEditor()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCodeEditor()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupCodeEditor()
    }
    
    private func setupCodeEditor() {
        // Enable line numbers (basic)
        isVerticallyResizable = true
        isHorizontallyResizable = true
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Tab settings
        typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        
        // Use tabs
        usesFontPanel = false
        usesRuler = false
        
        // Enable keyboard input
        acceptsRichText = false
        isFieldEditor = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Ensure we can receive keyboard events
            window?.makeFirstResponder(self)
        }
        return result
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Become first responder when clicked
        window?.makeFirstResponder(self)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Try to become first responder when added to window
        DispatchQueue.main.async { [weak self] in
            if let window = self?.window {
                window.makeFirstResponder(self)
            }
        }
    }
    
    override func insertTab(_ sender: Any?) {
        insertText("    ", replacementRange: selectedRange())
    }
}

