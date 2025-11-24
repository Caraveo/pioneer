import SwiftUI

struct AIPromptInput: View {
    @Binding var prompt: String
    @ObservedObject var aiService: AIService
    let isProcessing: Bool
    let onSubmit: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Template Selector
            if aiService.selectedTemplate != .custom {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Text("Template: \(aiService.selectedTemplate.rawValue)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        aiService.selectedTemplate = .custom
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            
            HStack(spacing: 12) {
                // Template Picker
                Menu {
                    ForEach(PromptTemplate.allCases) { template in
                        Button(action: {
                            aiService.selectedTemplate = template
                        }) {
                            HStack {
                                Text(template.rawValue)
                                if aiService.selectedTemplate == template {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                
                // AI Icon
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                    .font(.system(size: 18))
                
                // Input Field
                TextField(placeholderText, text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isFocused ? Color.blue : Color.gray.opacity(0.3), lineWidth: isFocused ? 2 : 1)
                            )
                    )
                    .focused($isFocused)
                    .lineLimit(1...4)
                    .onSubmit {
                        if !prompt.isEmpty && !isProcessing {
                            onSubmit()
                        }
                    }
                    .disabled(isProcessing)
                
                // Submit Button
                Button(action: {
                    if !prompt.isEmpty && !isProcessing {
                        onSubmit()
                    }
                }) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(prompt.isEmpty ? .gray : .blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(prompt.isEmpty || isProcessing)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        )
    }
    
    private var placeholderText: String {
        if aiService.selectedTemplate != .custom {
            return aiService.selectedTemplate.userPromptPrefix.isEmpty ? 
                "Ask AI to generate code..." : 
                aiService.selectedTemplate.userPromptPrefix
        }
        return "Ask AI to generate code..."
    }
}

struct AIResponseBubble: View {
    let message: String
    let onDismiss: () -> Void
    @State private var isVisible = true
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Success Icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 18))
            
            // Message
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Dismiss Button
            Button(action: {
                withAnimation {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        )
        .padding(.horizontal, 16)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .animation(.spring(response: 0.3), value: isVisible)
    }
}


