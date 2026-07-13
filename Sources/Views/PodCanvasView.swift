import SwiftUI

struct PodCanvasView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var draggedPodId: UUID?
    @State private var initialDragPosition: CGPoint = .zero
    @State private var isPanning: Bool = false
    @State private var initialPanOffset: CGSize = .zero
    @State private var connectingToPoint: CGPoint?
    @State private var hoveredPodId: UUID?
    @State private var mouseLocation: CGPoint = .zero
    @State private var aiPrompt: String = ""
    @State private var showAIResponse: Bool = false
    @State private var aiResponseMessage: String = ""
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid background
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                }
                
                // Pods and connections
                ZStack {
                    // Draw active connection being created
                    if let connectingFromId = projectManager.connectingFromPodId,
                       let fromPod = projectManager.pods.first(where: { $0.id == connectingFromId }) {
                        let fromPoint = getConnectionPoint(for: fromPod, isOutput: true)
                        // Use mouse location or hovered connection point
                        let toPoint = connectingToPoint ?? mouseLocation
                        ConnectionView(
                            from: fromPoint,
                            to: toPoint,
                            color: fromPod.framework.color,
                            isTemporary: true
                        )
                    }
                    
                    // Draw connections first (behind pods)
                    ForEach(projectManager.pods) { pod in
                        ForEach(pod.connections, id: \.self) { targetId in
                            if let targetPod = projectManager.pods.first(where: { $0.id == targetId }) {
                                ConnectionView(
                                    from: getConnectionPoint(for: pod, isOutput: true),
                                    to: getConnectionPoint(for: targetPod, isOutput: false),
                                    color: pod.framework.color
                                )
                            }
                        }
                    }
                    
                    // Draw pods
                    ForEach(projectManager.pods) { pod in
                        PodView(
                            pod: pod,
                            hoveredConnectionPoint: projectManager.hoveredConnectionPoint
                        )
                            .position(
                                x: pod.position.x + projectManager.canvasOffset.width,
                                y: pod.position.y + projectManager.canvasOffset.height
                            )
                            .scaleEffect(projectManager.canvasScale)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if let index = projectManager.pods.firstIndex(where: { $0.id == pod.id }) {
                                            if !isDragging || draggedPodId != pod.id {
                                                // Start of drag - store initial position
                                                isDragging = true
                                                draggedPodId = pod.id
                                                initialDragPosition = pod.position
                                            }
                                            
                                            // Calculate new position based on initial position and translation
                                            // Divide by canvas scale to account for zoom level
                                            let newX = initialDragPosition.x + (value.translation.width / projectManager.canvasScale)
                                            let newY = initialDragPosition.y + (value.translation.height / projectManager.canvasScale)
                                            
                                            projectManager.pods[index].position = CGPoint(x: newX, y: newY)
                                        }
                                    }
                                    .onEnded { _ in
                                        if draggedPodId == pod.id {
                                            isDragging = false
                                            draggedPodId = nil
                                            initialDragPosition = .zero
                                        }
                                    }
                            )
                            .onTapGesture {
                                // IMMEDIATE SAVE before switching
                                projectManager.saveCurrentPodFiles()
                                
                                // Small delay to ensure save completes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    projectManager.selectedPod = pod
                                }
                            }
                            .onHover { hovering in
                                hoveredPodId = hovering ? pod.id : nil
                            }
                    }
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        projectManager.canvasScale = max(0.5, min(2.0, value))
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 5)
                    .modifiers(.command)
                    .onChanged { value in
                        // Only pan if not dragging a pod and not connecting
                        if !isDragging && projectManager.connectingFromPodId == nil {
                            if !isPanning {
                                isPanning = true
                                initialPanOffset = projectManager.canvasOffset
                            }
                            
                            // Calculate new offset based on initial offset and translation
                            projectManager.canvasOffset = CGSize(
                                width: initialPanOffset.width + value.translation.width,
                                height: initialPanOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        isPanning = false
                        initialPanOffset = .zero
                    }
            )
            .background(
                // Track mouse location for connection preview
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if projectManager.connectingFromPodId != nil {
                                        // Convert to canvas coordinates
                                        mouseLocation = CGPoint(
                                            x: value.location.x - projectManager.canvasOffset.width,
                                            y: value.location.y - projectManager.canvasOffset.height
                                        )
                                    }
                                }
                        )
                }
            )
            
            // AI Prompt Input at the bottom
            VStack(spacing: 0) {
                Spacer()
                
                // AI Response Bubble
                if showAIResponse {
                    AIResponseBubble(message: aiResponseMessage) {
                        withAnimation {
                            showAIResponse = false
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                }
                
                // AI Prompt Input
                AIPromptInput(
                    prompt: $aiPrompt,
                    aiService: projectManager.aiService,
                    isProcessing: projectManager.aiService.isProcessing,
                    onSubmit: {
                        handleAIPrompt()
                    }
                )
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private func handleAIPrompt() {
        guard !aiPrompt.isEmpty else { return }
        guard !projectManager.aiService.isProcessing else { return } // Prevent spam
        
        // Set loading state immediately to prevent spam clicks
        projectManager.aiService.isProcessing = true
        
        guard let selectedPod = projectManager.selectedPod else {
            // Show error - no pod selected
            projectManager.aiService.isProcessing = false // Reset on error
            withAnimation {
                aiResponseMessage = "Please select a pod first — AI writes CODE + YAML for the selected pod."
                showAIResponse = true
            }
            return
        }
        
        Task {
            // Always use the live pod from the array (latest files/framework/type)
            let livePod: Pod = await MainActor.run {
                if let idx = projectManager.pods.firstIndex(where: { $0.id == selectedPod.id }) {
                    if let sel = projectManager.selectedPod, sel.id == selectedPod.id {
                        projectManager.pods[idx] = sel
                    }
                    return projectManager.pods[idx]
                }
                return selectedPod
            }
            
            // Connected pods = context only (generation targets livePod alone)
            let connectedPods: [Pod] = await MainActor.run {
                let ids = livePod.connections
                return projectManager.pods.filter { ids.contains($0.id) }
            }
            let allPods: [Pod] = await MainActor.run { projectManager.pods }
            
            // Ensure project structure exists
            do {
                try await projectManager.podProjectService.createProjectStructure(for: livePod)
            } catch {
                print("Failed to create project structure: \(error)")
            }
            
            // One prompt → CODE (launch file) + YAML, scoped to this pod’s language/context
            let result = await projectManager.aiService.generateForPod(
                prompt: aiPrompt,
                framework: livePod.framework,
                podContext: livePod,
                connectedPods: connectedPods,
                allPods: allPods
            )
            
            guard let result, result.hasCode || result.hasYAML else {
                await MainActor.run {
                    withAnimation {
                        aiResponseMessage = "Failed to generate CODE + YAML. Please try again."
                        showAIResponse = true
                    }
                }
                return
            }
            
            let projectPath = projectManager.podProjectService.getProjectPath(
                for: livePod,
                projectName: projectManager.projectName
            )
            
            if let index = projectManager.pods.firstIndex(where: { $0.id == livePod.id }) {
                // --- Apply CODE to launch file (already language-normalized) ---
                if result.hasCode {
                    let codeOnly = extractCodeFromResponse(result.code)
                    // Keep language metadata aligned with framework
                    let mainFile = projectManager.pods[index].getOrCreateMainFile()
                    if let fileIndex = projectManager.pods[index].files.firstIndex(where: { $0.id == mainFile.id }) {
                        projectManager.pods[index].files[fileIndex].content = codeOnly
                        projectManager.pods[index].files[fileIndex].language = projectManager.pods[index].framework.primaryLanguage
                        projectManager.pods[index].code = codeOnly
                        projectManager.pods[index].selectedFileId = mainFile.id
                    }
                }
                
                // --- Apply YAML to this pod’s own K8s manifest ---
                if result.hasYAML {
                    var yaml = extractCodeFromResponse(result.yaml)
                    // Keep hostPath pointed at this pod’s project directory
                    if !yaml.contains(projectPath.path) {
                        yaml = Self.injectHostPath(into: yaml, path: projectPath.path)
                            ?? yaml
                    }
                    projectManager.pods[index].kubernetesYAML = yaml
                } else if projectManager.pods[index].kubernetesYAML.isEmpty {
                    projectManager.pods[index].regenerateKubernetesYAML()
                }
                
                projectManager.pods[index].projectPath = projectPath.path
                
                // Persist CODE files + YAML
                do {
                    try await projectManager.podProjectService.saveAllFiles(
                        pod: projectManager.pods[index],
                        projectPath: projectPath
                    )
                    try KubernetesManifestService.writeYAML(
                        projectManager.pods[index].kubernetesYAML,
                        to: projectPath
                    )
                } catch {
                    print("Failed to save pod artifacts: \(error)")
                }
                
                projectManager.selectedPod = projectManager.pods[index]
            }
            
            let parts: [String] = [
                result.hasCode ? "CODE" : nil,
                result.hasYAML ? "YAML" : nil
            ].compactMap { $0 }
            
            await MainActor.run {
                withAnimation {
                    let fw = livePod.framework.rawValue
                    aiResponseMessage = "Generated \(parts.joined(separator: " + ")) for “\(livePod.name)” (\(fw)) — syntax matched to pod context"
                    showAIResponse = true
                    aiPrompt = ""
                }
            }
        }
    }
    
    /// Best-effort: set hostPath.path in Pod YAML to the on-disk project path.
    private static func injectHostPath(into yaml: String, path: String) -> String? {
        // Replace an existing hostPath path: line if present
        let lines = yaml.components(separatedBy: "\n")
        var result: [String] = []
        var replaced = false
        var inHostPath = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("hostPath:") {
                inHostPath = true
                result.append(line)
                continue
            }
            if inHostPath && trimmed.hasPrefix("path:") {
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                result.append("\(indent)path: \(path)")
                replaced = true
                inHostPath = false
                continue
            }
            if inHostPath && !trimmed.isEmpty && !trimmed.hasPrefix("path:") && !trimmed.hasPrefix("type:") {
                inHostPath = false
            }
            result.append(line)
        }
        return replaced ? result.joined(separator: "\n") : nil
    }
    
    
    private func extractCodeFromResponse(_ response: String) -> String {
        // Extract ONLY code from markdown code blocks, removing all explanations
        let code = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First, try to find code blocks
        var searchStart = code.startIndex
        var foundCodeBlocks: [String] = []
        
        while let codeRange = code.range(of: "```", range: searchStart..<code.endIndex) {
            let start = code.index(codeRange.upperBound, offsetBy: 0)
            
            // Skip language identifier if present (swift, python, etc.)
            var codeStart = start
            if let newlineRange = code[start...].range(of: "\n") {
                codeStart = code.index(newlineRange.upperBound, offsetBy: 0)
            }
            
            // Find the closing ```
            if let endRange = code[codeStart...].range(of: "```") {
                let extractedCode = String(code[codeStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extractedCode.isEmpty {
                    foundCodeBlocks.append(extractedCode)
                }
                // Continue searching after this code block
                searchStart = code.index(endRange.upperBound, offsetBy: 0)
            } else {
                break
            }
        }
        
        // If we found code blocks, return the first one (or combine if multiple)
        if !foundCodeBlocks.isEmpty {
            return foundCodeBlocks.joined(separator: "\n\n")
        }
        
        // If no code blocks, check if the response is pure code (starts with code-like keywords)
        let codeIndicators = ["import ", "struct ", "class ", "func ", "def ", "function ", "const ", "let ", "var ", "public ", "private ", "<?php", "<!DOCTYPE", "#include", "@", "package "]
        if codeIndicators.contains(where: { code.hasPrefix($0) }) {
            return code
        }
        
        // Check for explanatory text patterns - if found, try to extract code after them
        let explanatoryPatterns = ["here is", "you can", "this code", "example", "note:", "please note", "remember", "in swiftui", "you might", "here's", "this is"]
        let lowerCode = code.lowercased()
        
        for pattern in explanatoryPatterns {
            if let patternRange = lowerCode.range(of: pattern) {
                // Try to find code after the explanation
                let afterExplanation = String(code[patternRange.upperBound...])
                // Look for code blocks in the remaining text
                if let codeBlockStart = afterExplanation.range(of: "```") {
                    let codeAfter = String(afterExplanation[codeBlockStart.upperBound...])
                    if let codeBlockEnd = codeAfter.range(of: "```") {
                        let extracted = String(codeAfter[..<codeBlockEnd.lowerBound])
                        // Skip language identifier
                        if let newlineRange = extracted.range(of: "\n") {
                            return String(extracted[newlineRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        // If we still have explanatory text, try to remove everything before the first code block
        // Look for common patterns like "In SwiftUI," or "Here is an example:"
        if let firstCodeBlock = code.range(of: "```") {
            // Check if there's text before the code block
            let beforeCode = String(code[..<firstCodeBlock.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeCode.count > 50 { // Likely has explanation
                // Extract just the code block
                let afterStart = String(code[firstCodeBlock.upperBound...])
                if let codeBlockEnd = afterStart.range(of: "```") {
                    let extracted = String(afterStart[..<codeBlockEnd.lowerBound])
                    // Skip language identifier
                    if let newlineRange = extracted.range(of: "\n") {
                        return String(extracted[newlineRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Fallback: return trimmed code (might be pure code without markdown)
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridSize: CGFloat = 20
        let offset = projectManager.canvasOffset
        
        context.stroke(
            Path { path in
                for x in stride(from: 0, through: size.width, by: gridSize) {
                    path.move(to: CGPoint(x: x + offset.width, y: 0))
                    path.addLine(to: CGPoint(x: x + offset.width, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: gridSize) {
                    path.move(to: CGPoint(x: 0, y: y + offset.height))
                    path.addLine(to: CGPoint(x: size.width, y: y + offset.height))
                }
            },
            with: .color(.secondary.opacity(0.2)),
            lineWidth: 0.5
        )
    }
    
    private func getConnectionPoint(for pod: Pod, isOutput: Bool) -> CGPoint {
        let podWidth: CGFloat = 200
        let connectionY = pod.position.y + 140 // Bottom of pod
        let x = isOutput ? pod.position.x + podWidth - 20 : pod.position.x + 20
        return CGPoint(x: x, y: connectionY)
    }
}

struct PodView: View {
    let pod: Pod
    let hoveredConnectionPoint: (podId: UUID, isOutput: Bool)?
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isRenaming = false
    @State private var renameText = ""
    
    var isSelected: Bool {
        projectManager.selectedPod?.id == pod.id
    }
    
    var hasInputConnections: Bool {
        projectManager.pods.contains { $0.connections.contains(pod.id) }
    }
    
    var hasOutputConnections: Bool {
        !pod.connections.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: pod.type.icon)
                    .foregroundColor(pod.framework.color)
                
                if isRenaming {
                    TextField("Pod name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .onSubmit {
                            finishRenaming()
                        }
                        .onAppear {
                            renameText = pod.name
                        }
                } else {
                    Text(pod.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .primary : .primary)
                        .onTapGesture(count: 2) {
                            startRenaming()
                        }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(pod.framework.color)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            Divider()
            
            // Content preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: pod.framework.icon)
                        .font(.system(size: 10))
                        .foregroundColor(pod.framework.color)
                    Text(pod.framework.rawValue)
                        .font(.system(size: 10))
                        .foregroundColor(pod.framework.color)
                }
                .padding(.horizontal, 12)
                
                if let mainFile = pod.selectedFile, !mainFile.content.isEmpty {
                    Text(mainFile.content.prefix(50) + (mainFile.content.count > 50 ? "..." : ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .lineLimit(2)
                } else if !pod.code.isEmpty {
                    Text(pod.code.prefix(50) + (pod.code.count > 50 ? "..." : ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 8)
            
            // Connection points
            HStack {
                // Input connection point (left side)
                ConnectionPointView(
                    pod: pod,
                    isOutput: false,
                    isConnected: hasInputConnections,
                    isHovered: hoveredConnectionPoint?.podId == pod.id && hoveredConnectionPoint?.isOutput == false,
                    color: pod.framework.color
                )
                
                Spacer()
                
                // Output connection point (right side)
                ConnectionPointView(
                    pod: pod,
                    isOutput: true,
                    isConnected: hasOutputConnections,
                    isHovered: hoveredConnectionPoint?.podId == pod.id && hoveredConnectionPoint?.isOutput == true,
                    color: pod.framework.color
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? pod.language.color : Color.clear,
                            lineWidth: isSelected ? 3 : 0
                        )
                )
                .shadow(
                    color: isSelected ? pod.language.color.opacity(0.4) : .black.opacity(0.1),
                    radius: isSelected ? 8 : 5,
                    y: 2
                )
        )
        .onChange(of: isRenaming) { newValue in
            if !newValue && !renameText.isEmpty && renameText != pod.name {
                finishRenaming()
            }
        }
    }
    
    private func startRenaming() {
        renameText = pod.name
        isRenaming = true
    }
    
    private func finishRenaming() {
        guard let index = projectManager.pods.firstIndex(where: { $0.id == pod.id }) else { return }
        
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty && newName != pod.name else {
            isRenaming = false
            return
        }
        
        let oldName = projectManager.pods[index].name
        projectManager.pods[index].name = newName
        
        // Rename directory in file system if it exists
        if let oldProjectPath = projectManager.pods[index].projectPath {
            let oldURL = URL(fileURLWithPath: oldProjectPath)
            let parentDir = oldURL.deletingLastPathComponent()
            let newDirName = sanitizeDirectoryName(newName)
            let newURL = parentDir.appendingPathComponent(newDirName)
            
            // Only rename if the directory name would actually change
            if oldURL.lastPathComponent != newDirName {
                do {
                    if FileManager.default.fileExists(atPath: oldURL.path) {
                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                        projectManager.pods[index].projectPath = newURL.path
                    }
                } catch {
                    print("Failed to rename pod directory: \(error)")
                    // Revert name change on error
                    projectManager.pods[index].name = oldName
                }
            }
        }
        
        projectManager.selectedPod = projectManager.pods[index]
        isRenaming = false
    }
    
    private func sanitizeDirectoryName(_ name: String) -> String {
        return name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}

struct ConnectionPointView: View {
    let pod: Pod
    let isOutput: Bool
    let isConnected: Bool
    let isHovered: Bool
    let color: Color
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isDragging: Bool = false
    
    var isConnecting: Bool {
        projectManager.connectingFromPodId != nil
    }
    
    var body: some View {
        Circle()
            .fill(isConnected ? color : Color.clear)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(isConnected ? color : color.opacity(0.5), lineWidth: isHovered ? 3 : 2)
            )
            .scaleEffect(isHovered ? 1.3 : 1.0)
            .animation(.spring(response: 0.2), value: isHovered)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !isDragging && isOutput {
                            isDragging = true
                            projectManager.startConnection(from: pod.id)
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        // Connection will be completed on tap of input point
                        // Or cancel if not connected
                        if projectManager.connectingFromPodId == pod.id {
                            // Check if we're over an input point
                            // This would be handled by the canvas detecting the drop
                        }
                    }
            )
            .onTapGesture {
                if !isOutput && isConnecting {
                    // Complete connection to this input
                    if let connectingFrom = projectManager.connectingFromPodId, connectingFrom != pod.id {
                        projectManager.connectPods(from: connectingFrom, to: pod.id)
                        projectManager.endConnection()
                    } else {
                        // Cancel connection if clicking same pod
                        projectManager.endConnection()
                    }
                } else if isOutput && !isConnecting {
                    // Start new connection from output
                    projectManager.startConnection(from: pod.id)
                } else if isOutput && isConnecting && projectManager.connectingFromPodId == pod.id {
                    // Cancel connection if clicking output again
                    projectManager.endConnection()
                }
            }
            .contextMenu {
                if isConnected {
                    Button("Disconnect") {
                        if isOutput {
                            // Remove all connections from this pod
                            if let index = projectManager.pods.firstIndex(where: { $0.id == pod.id }) {
                                projectManager.pods[index].connections.removeAll()
                            }
                        } else {
                            // Remove connections to this pod
                            for i in projectManager.pods.indices {
                                projectManager.pods[i].connections.removeAll { $0 == pod.id }
                            }
                        }
                    }
                }
            }
            .onHover { hovering in
                if hovering {
                    projectManager.hoverConnectionPoint(podId: pod.id, isOutput: isOutput)
                } else if projectManager.hoveredConnectionPoint?.podId == pod.id {
                    projectManager.hoverConnectionPoint(podId: nil, isOutput: false)
                }
            }
    }
}

struct ConnectionView: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var isTemporary: Bool = false
    
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        Path { path in
            let adjustedFrom = CGPoint(
                x: from.x + projectManager.canvasOffset.width,
                y: from.y + projectManager.canvasOffset.height
            )
            let adjustedTo = CGPoint(
                x: to.x + projectManager.canvasOffset.width,
                y: to.y + projectManager.canvasOffset.height
            )
            
            path.move(to: adjustedFrom)
            
            // Bezier curve for connection
            let controlPoint1 = CGPoint(
                x: adjustedFrom.x + (adjustedTo.x - adjustedFrom.x) * 0.5,
                y: adjustedFrom.y
            )
            let controlPoint2 = CGPoint(
                x: adjustedTo.x - (adjustedTo.x - adjustedFrom.x) * 0.5,
                y: adjustedTo.y
            )
            
            path.addCurve(
                to: adjustedTo,
                control1: controlPoint1,
                control2: controlPoint2
            )
        }
        .stroke(
            isTemporary ? color.opacity(0.4) : color.opacity(0.6),
            style: StrokeStyle(
                lineWidth: isTemporary ? 2 : 2,
                lineCap: .round,
                dash: isTemporary ? [5, 5] : []
            )
        )
    }
}

