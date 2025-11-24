import SwiftUI
import AppKit
import WebKit

struct MonacoEditorView: NSViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    var onWebViewReady: ((WKWebView) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> NSView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "pioneer")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Enable keyboard input
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        
        // Configure for keyboard input
        if #available(macOS 11.0, *) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        
        // Critical: Make webView accept first responder for keyboard input
        webView.setValue(true, forKey: "acceptsFirstResponder")
        
        // Enable keyboard input in webView
        let acceptsFirstResponderSelector = NSSelectorFromString("setAcceptsFirstResponder:")
        if webView.responds(to: acceptsFirstResponderSelector) {
            webView.perform(acceptsFirstResponderSelector, with: true)
        }
        
        // Set custom user agent to help with keyboard handling
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Safari/605.1.15"
        
        // Create a container view that can become first responder
        let containerView = FocusableWebViewContainer(webView: webView)
        
        // Load Monaco Editor
        let html = generateMonacoHTML(language: language, initialText: text, theme: colorScheme == .dark ? "vs-dark" : "vs")
        webView.loadHTMLString(html, baseURL: nil)
        
        context.coordinator.webView = webView
        context.coordinator.onWebViewReady = onWebViewReady
        
        // Notify when webView is ready
        DispatchQueue.main.async {
            onWebViewReady?(webView)
        }
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let containerView = nsView as? FocusableWebViewContainer else {
            return
        }
        let webView = containerView.webView
        // Update theme if changed
        let currentTheme = context.coordinator.currentTheme
        let newTheme = colorScheme == .dark ? "vs-dark" : "vs"
        if currentTheme != newTheme {
            context.coordinator.currentTheme = newTheme
            updateTheme(webView: webView, theme: newTheme)
        }
        
        // Update language if changed
        if context.coordinator.currentLanguage != language {
            context.coordinator.currentLanguage = language
            updateLanguage(webView: webView, language: language)
        }
        
        // Update text if changed (but not if we're the source of the change)
        if !context.coordinator.isUpdatingFromJS && webView.url != nil {
            updateText(webView: webView, text: text)
        }
    }
    
    private func updateTheme(webView: WKWebView, theme: String) {
        let backgroundColor = theme == "vs-dark" ? "#1e1e1e" : "#ffffff"
        let script = """
        if (window.monacoEditor) {
            monaco.editor.setTheme('\(theme)');
            // Update body background
            document.body.style.backgroundColor = '\(backgroundColor)';
        }
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateLanguage(webView: WKWebView, language: CodeLanguage) {
        let monacoLanguage = languageToMonacoLanguage(language)
        let script = """
        if (window.monacoEditor) {
            monaco.editor.setModelLanguage(window.monacoEditor.getModel(), '\(monacoLanguage)');
        }
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func updateText(webView: WKWebView, text: String) {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        
        let script = """
        if (window.monacoEditor) {
            window.monacoEditor.setValue(`\(escapedText)`);
        }
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func languageToMonacoLanguage(_ language: CodeLanguage) -> String {
        switch language {
        case .swift: return "swift"
        case .python: return "python"
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .html: return "html"
        case .css: return "css"
        case .yaml: return "yaml"
        case .json: return "json"
        case .bash: return "shell"
        case .sql: return "sql"
        case .markdown: return "markdown"
        case .dockerfile: return "dockerfile"
        case .kubernetes: return "yaml"
        case .terraform: return "hcl"
        case .cloudformation: return "yaml"
        case .scaffolding: return "plaintext"
        }
    }
    
    private func generateMonacoHTML(language: CodeLanguage, initialText: String, theme: String) -> String {
        let monacoLanguage = languageToMonacoLanguage(language)
        let escapedText = initialText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        // Set background color based on theme
        let backgroundColor = theme == "vs-dark" ? "#1e1e1e" : "#ffffff"
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    overflow: hidden;
                    background-color: \(backgroundColor);
                }
                #container {
                    width: 100vw;
                    height: 100vh;
                }
            </style>
        </head>
        <body>
            <div id="container"></div>
            
            <script src="https://cdn.jsdelivr.net/npm/monaco-editor@latest/min/vs/loader.js"></script>
            <script>
                require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@latest/min/vs' } });
                
                require(['vs/editor/editor.main'], function () {
                    // Create editor
                    window.monacoEditor = monaco.editor.create(document.getElementById('container'), {
                        value: `\(escapedText)`,
                        language: '\(monacoLanguage)',
                        theme: '\(theme)',
                        automaticLayout: true,
                        fontSize: 12,
                        fontFamily: 'Menlo, Monaco, "Courier New", monospace',
                        minimap: { enabled: true },
                        scrollBeyondLastLine: false,
                        wordWrap: 'on',
                        lineNumbers: 'on',
                        folding: true,
                        formatOnPaste: true,
                        formatOnType: true,
                        suggestOnTriggerCharacters: true,
                        quickSuggestions: true,
                        parameterHints: { enabled: true },
                        tabSize: 4,
                        insertSpaces: true,
                        detectIndentation: false,
                        readOnly: false,
                        domReadOnly: false
                    });
                    
                    // Ensure editor can receive focus and keyboard input
                    window.monacoEditor.focus();
                    
                    // Make container focusable and ensure it can receive input
                    const container = document.getElementById('container');
                    container.setAttribute('tabindex', '0');
                    container.style.outline = 'none';
                    
                    // Listen for clicks to ensure focus
                    document.addEventListener('click', function(e) {
                        if (window.monacoEditor) {
                            window.monacoEditor.focus();
                        }
                    }, true);
                    
                    // Listen for keydown to ensure editor receives input
                    document.addEventListener('keydown', function(e) {
                        if (window.monacoEditor) {
                            if (!window.monacoEditor.hasTextFocus()) {
                                window.monacoEditor.focus();
                            }
                            // Don't prevent default - let Monaco handle it
                        }
                    }, false); // Use capture: false so Monaco can handle it
                    
                    // Ensure editor is always editable
                    window.monacoEditor.updateOptions({
                        readOnly: false,
                        domReadOnly: false
                    });
                    
                    // Listen for content changes
                    window.monacoEditor.onDidChangeModelContent(function() {
                        const value = window.monacoEditor.getValue();
                        window.webkit.messageHandlers.pioneer.postMessage({
                            type: 'contentChanged',
                            value: value
                        });
                    });
                    
                    // Listen for cursor position changes
                    window.monacoEditor.onDidChangeCursorPosition(function(e) {
                        window.webkit.messageHandlers.pioneer.postMessage({
                            type: 'cursorChanged',
                            lineNumber: e.position.lineNumber,
                            column: e.position.column
                        });
                    });
                    
                    // Notify that editor is ready
                    window.webkit.messageHandlers.pioneer.postMessage({
                        type: 'editorReady'
                    });
                });
            </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MonacoEditorView
        weak var webView: WKWebView?
        var currentLanguage: CodeLanguage
        var currentTheme: String = "vs-dark"
        var isUpdatingFromJS: Bool = false
        var onWebViewReady: ((WKWebView) -> Void)?
        var lastKnownContent: String = ""
        
        init(_ parent: MonacoEditorView) {
            self.parent = parent
            self.currentLanguage = parent.language
            self.currentTheme = parent.colorScheme == .dark ? "vs-dark" : "vs"
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Editor loaded, ensure it has focus and can receive keyboard input
            DispatchQueue.main.async {
                // Make webView first responder
                webView.window?.makeFirstResponder(webView)
                
                // Force focus on Monaco editor and ensure it's editable
                let focusScript = """
                if (window.monacoEditor) {
                    window.monacoEditor.focus();
                    window.monacoEditor.updateOptions({
                        readOnly: false,
                        domReadOnly: false
                    });
                    // Ensure the editor container can receive focus
                    const container = document.getElementById('container');
                    if (container) {
                        container.focus();
                    }
                }
                """
                webView.evaluateJavaScript(focusScript, completionHandler: nil)
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            
            switch type {
            case "contentChanged":
                if let value = body["value"] as? String {
                    lastKnownContent = value
                    isUpdatingFromJS = true
                    DispatchQueue.main.async {
                        self.parent.text = value
                        self.isUpdatingFromJS = false
                    }
                }
                
            case "editorReady":
                // Editor is ready, ensure focus and keyboard input
                DispatchQueue.main.async {
                    if let webView = self.webView {
                        // Make webView first responder with delay to ensure it works
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            webView.window?.makeFirstResponder(webView)
                            
                            // Force focus on Monaco editor
                            let focusScript = """
                            if (window.monacoEditor) {
                                window.monacoEditor.focus();
                                window.monacoEditor.updateOptions({ readOnly: false });
                                // Also focus the container
                                document.getElementById('container').focus();
                            }
                            """
                            webView.evaluateJavaScript(focusScript, completionHandler: nil)
                        }
                    }
                }
                
            case "cursorChanged":
                // Could track cursor position if needed
                break
                
            default:
                break
            }
        }
    }
}

// Wrapper to ensure WKWebView can receive keyboard input
class FocusableWebViewContainer: NSView {
    let webView: WKWebView
    
    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Track mouse events to ensure focus
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func becomeFirstResponder() -> Bool {
        // Forward focus to webView and Monaco editor
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.webView)
            // Also focus Monaco editor
            let focusScript = """
            if (window.monacoEditor) {
                window.monacoEditor.focus();
            }
            """
            self.webView.evaluateJavaScript(focusScript, completionHandler: nil)
        }
        return super.becomeFirstResponder()
    }
    
    override func mouseDown(with event: NSEvent) {
        // Ensure webView gets focus on click
        window?.makeFirstResponder(webView)
        
        // Also focus Monaco editor immediately
        let focusScript = """
        if (window.monacoEditor) {
            window.monacoEditor.focus();
            window.monacoEditor.updateOptions({ readOnly: false });
        }
        """
        webView.evaluateJavaScript(focusScript, completionHandler: nil)
        
        // Forward mouse event to webView
        webView.mouseDown(with: event)
    }
    
    override func mouseEntered(with event: NSEvent) {
        // Focus when mouse enters
        window?.makeFirstResponder(webView)
        let focusScript = """
        if (window.monacoEditor) {
            window.monacoEditor.focus();
        }
        """
        webView.evaluateJavaScript(focusScript, completionHandler: nil)
    }
    
    override func keyDown(with event: NSEvent) {
        // Ensure webView is first responder, then let it handle the event
        if window?.firstResponder !== webView {
            window?.makeFirstResponder(webView)
            // After making first responder, forward the event
            DispatchQueue.main.async {
                self.webView.keyDown(with: event)
            }
        } else {
            // Already first responder, forward directly
            webView.keyDown(with: event)
        }
    }
    
    override func keyUp(with event: NSEvent) {
        if window?.firstResponder === webView {
            webView.keyUp(with: event)
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        if window?.firstResponder === webView {
            webView.flagsChanged(with: event)
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Ensure webView has focus
        if window?.firstResponder !== webView {
            window?.makeFirstResponder(webView)
        }
        // Let webView handle it
        return webView.performKeyEquivalent(with: event)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
}

