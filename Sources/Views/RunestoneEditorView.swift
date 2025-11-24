import SwiftUI
import AppKit
import TreeSitter

struct RunestoneEditorView: NSViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    
    func makeNSView(context: Context) -> CodeEditorTextView {
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        
        let textView = CodeEditorTextView(frame: .zero, textContainer: textContainer)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.language = language
        textView.isEditable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // Set up text change handler
        textView.delegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ nsView: CodeEditorTextView, context: Context) {
        // Only update if text actually changed (to avoid cursor jumping)
        if nsView.string != text {
            let selectedRange = nsView.selectedRange()
            nsView.string = text
            // Restore cursor position if possible
            if selectedRange.location <= text.count {
                nsView.setSelectedRange(selectedRange)
            }
        }
        
        // Update language if changed
        if nsView.language != language {
            nsView.language = language
            nsView.applySyntaxHighlighting()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RunestoneEditorView
        
        init(_ parent: RunestoneEditorView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
    }
}

class CodeEditorTextView: NSTextView {
    var language: CodeLanguage = .swift {
        didSet {
            if language != oldValue {
                applySyntaxHighlighting()
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupEditor()
    }
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupEditor()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEditor()
    }
    
    private func setupEditor() {
        // Configure text view
        font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textColor = .labelColor
        backgroundColor = .textBackgroundColor
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        
        // Enable line numbers
        if let scrollView = enclosingScrollView {
            let rulerView = LineNumberRulerView(textView: self)
            scrollView.verticalRulerView = rulerView
            scrollView.rulersVisible = true
            scrollView.hasVerticalRuler = true
        }
        
        // Set up text container
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        isHorizontallyResizable = false
        isVerticallyResizable = true
        
        // Apply initial syntax highlighting
        applySyntaxHighlighting()
    }
    
    func applySyntaxHighlighting() {
        guard let textStorage = textStorage else { return }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        
        // Remove existing attributes
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.removeAttribute(.font, range: fullRange)
        
        // Apply base font and color
        textStorage.addAttribute(.font, value: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        
        // Apply syntax highlighting based on language
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.highlight(text: string, in: textStorage)
    }
    
    override func didChangeText() {
        super.didChangeText()
        // Re-apply syntax highlighting on text change
        DispatchQueue.main.async { [weak self] in
            self?.applySyntaxHighlighting()
        }
    }
}

// Simple syntax highlighter using regex patterns
class SyntaxHighlighter {
    let language: CodeLanguage
    
    init(language: CodeLanguage) {
        self.language = language
    }
    
    func highlight(text: String, in textStorage: NSTextStorage) {
        let patterns = getPatternsForLanguage(language)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        
        for (pattern, color) in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let matches = regex.matches(in: text, options: [], range: fullRange)
                
                for match in matches {
                    textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            } catch {
                // Invalid regex, skip
            }
        }
    }
    
    private func getPatternsForLanguage(_ language: CodeLanguage) -> [(String, NSColor)] {
        switch language {
        case .swift:
            return [
                (#"\b(func|class|struct|enum|protocol|extension|import|let|var|if|else|for|while|return|guard|switch|case|default|break|continue|try|catch|throw|async|await|public|private|internal|static|final|override|init|deinit|self|super)\b"#, .systemPurple),
                (#""[^"]*""#, .systemGreen),
                (#"//.*"#, .systemGray),
                (#"/\*[\s\S]*?\*/"#, .systemGray),
                (#"\b\d+\.?\d*\b"#, .systemOrange),
            ]
        case .python:
            return [
                (#"\b(def|class|import|from|if|elif|else|for|while|return|try|except|finally|raise|async|await|pass|break|continue|lambda|yield|True|False|None)\b"#, .systemPurple),
                (#""[^"]*"|'[^']*'"#, .systemGreen),
                (#"#.*"#, .systemGray),
                (#"\b\d+\.?\d*\b"#, .systemOrange),
            ]
        case .javascript, .typescript:
            return [
                (#"\b(function|class|const|let|var|if|else|for|while|return|try|catch|finally|throw|async|await|import|export|default|extends|super|this|new|typeof|instanceof)\b"#, .systemPurple),
                (#""[^"]*"|'[^']*'|`[^`]*`"#, .systemGreen),
                (#"//.*|/\*[\s\S]*?\*/"#, .systemGray),
                (#"\b\d+\.?\d*\b"#, .systemOrange),
            ]
        case .html:
            return [
                (#"<[^>]+>"#, .systemBlue),
                (#""[^"]*""#, .systemGreen),
            ]
        case .css:
            return [
                (#"[^{}]+(?=\{)"#, .systemBlue),
                (#"\{[^}]*\}"#, .systemBlue),
                (#"#[0-9a-fA-F]{3,6}|\b\d+px\b"#, .systemOrange),
            ]
        case .yaml, .kubernetes, .cloudformation:
            return [
                (#"^[\w-]+:"#, .systemPurple),
                (#""[^"]*"|'[^']*'"#, .systemGreen),
                (#"#.*"#, .systemGray),
            ]
        case .json:
            return [
                (#""[^"]*"(?=\s*:)"#, .systemPurple),
                (#""[^"]*""#, .systemGreen),
                (#"\b(true|false|null)\b"#, .systemOrange),
            ]
        case .bash:
            return [
                (#"\b(if|then|else|fi|for|while|do|done|case|esac|function|return|exit|echo|export|read)\b"#, .systemPurple),
                (#""[^"]*"|'[^']*'"#, .systemGreen),
                (#"#.*"#, .systemGray),
            ]
        case .sql:
            return [
                (#"\b(SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|JOIN|INNER|LEFT|RIGHT|OUTER|ON|GROUP|BY|ORDER|HAVING|AS|AND|OR|NOT|NULL|DEFAULT|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|CONSTRAINT)\b"#, .systemPurple),
                (#"'[^']*'"#, .systemGreen),
                (#"--.*|/\*[\s\S]*?\*/"#, .systemGray),
            ]
        case .markdown:
            return [
                (#"^#+\s+.*"#, .systemPurple),
                (#"\*\*[^\*]+\*\*|\*[^\*]+\*"#, .systemBlue),
                (#"`[^`]+`"#, .systemOrange),
            ]
        default:
            return []
        }
    }
}

// Line number ruler view
class LineNumberRulerView: NSRulerView {
    var textView: NSTextView?
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        ruleThickness = 40
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        
        let lineNumberColor = NSColor.secondaryLabelColor
        lineNumberColor.set()
        
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: lineNumberColor
        ]
        
        var lineNumber = 1
        var charIndex = 0
        
        while charIndex < visibleCharRange.location + visibleCharRange.length {
            let lineRange = (textView.string as NSString).lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            
            let lineNumberString = "\(lineNumber)"
            let stringSize = lineNumberString.size(withAttributes: attributes)
            let point = NSPoint(
                x: ruleThickness - stringSize.width - 5,
                y: rect.origin.y + (rect.height - stringSize.height) / 2
            )
            
            lineNumberString.draw(at: point, withAttributes: attributes)
            
            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
}
