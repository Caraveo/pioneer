import SwiftUI
import AppKit

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
                // ── Background: click empty area to deselect, drag to pan ──
                // Full-size hit target sits under pods so empty space receives gestures.
                ZStack {
                    Color(NSColor.textBackgroundColor)
                    Canvas { context, size in
                        drawGrid(context: context, size: size)
                    }
                }
                .contentShape(Rectangle())
                .gesture(canvasPanGesture)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        handleCanvasTap()
                    }
                )
                .onHover { hovering in
                    if hovering && !isDragging {
                        NSCursor.openHand.push()
                    } else if !hovering {
                        NSCursor.pop()
                    }
                }
                
                // Empty canvas hint (doesn't block pan when transparent areas hit through)
                if projectManager.pods.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No pods")
                            .font(.headline)
                        Text("Add a pod from the sidebar, or use INFER → Inference Wizard.\nDrag the canvas to pan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                        Button("New Pod") {
                            projectManager.createNewPod()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(true)
                }
                
                // Links don't steal clicks from canvas / pods
                ForEach(projectManager.pods) { pod in
                    ForEach(pod.connections, id: \.self) { targetId in
                        if let targetPod = projectManager.pods.first(where: { $0.id == targetId }) {
                            ConnectionView(
                                from: canvasPort(for: pod, isOutput: true),
                                to: canvasPort(for: targetPod, isOutput: false),
                                color: pod.framework.color,
                                isTemporary: false
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }
                
                // Live wire while dragging from an output port
                if let connectingFromId = projectManager.connectingFromPodId,
                   let fromPod = projectManager.pods.first(where: { $0.id == connectingFromId }),
                   let wireTo = connectingToPoint {
                    ConnectionView(
                        from: canvasPort(for: fromPod, isOutput: true),
                        to: wireTo,
                        color: fromPod.framework.color,
                        isTemporary: true
                    )
                    .allowsHitTesting(false)
                }
                
                // Pods — click to select, drag to move (on top of canvas)
                ForEach(projectManager.pods) { pod in
                    PodView(
                        pod: pod,
                        hoveredConnectionPoint: projectManager.hoveredConnectionPoint,
                        isBeingDragged: draggedPodId == pod.id,
                        onSelect: {
                            selectPod(id: pod.id)
                        },
                        onConnectionDragChanged: { canvasLocation in
                            projectManager.startConnection(from: pod.id)
                            connectingToPoint = canvasLocation
                            if let target = nearestInputPod(atCanvas: canvasLocation, excluding: pod.id) {
                                projectManager.hoverConnectionPoint(podId: target.id, isOutput: false)
                            } else {
                                projectManager.hoverConnectionPoint(podId: nil, isOutput: false)
                            }
                        },
                        onConnectionDragEnded: { canvasLocation in
                            if let target = nearestInputPod(atCanvas: canvasLocation, excluding: pod.id) {
                                projectManager.connectPods(from: pod.id, to: target.id)
                            }
                            projectManager.endConnection()
                            projectManager.hoverConnectionPoint(podId: nil, isOutput: false)
                            connectingToPoint = nil
                        },
                        onConnectionCancel: {
                            projectManager.endConnection()
                            projectManager.hoverConnectionPoint(podId: nil, isOutput: false)
                            connectingToPoint = nil
                        },
                        onBodyDragChanged: { translation in
                            guard projectManager.connectingFromPodId == nil else { return }
                            if !isDragging || draggedPodId != pod.id {
                                isDragging = true
                                draggedPodId = pod.id
                                if let current = projectManager.pods.first(where: { $0.id == pod.id }) {
                                    initialDragPosition = current.position
                                } else {
                                    initialDragPosition = pod.position
                                }
                                selectPod(id: pod.id)
                            }
                            let scale = max(projectManager.canvasScale, 0.01)
                            let newPos = CGPoint(
                                x: initialDragPosition.x + translation.width / scale,
                                y: initialDragPosition.y + translation.height / scale
                            )
                            projectManager.movePod(id: pod.id, to: newPos)
                        },
                        onBodyDragEnded: {
                            if draggedPodId == pod.id {
                                isDragging = false
                                draggedPodId = nil
                                initialDragPosition = .zero
                            }
                        }
                    )
                    .frame(width: PodCanvasView.podCardWidth, height: PodCanvasView.podCardHeight)
                    .position(
                        x: pod.position.x + projectManager.canvasOffset.width,
                        y: pod.position.y + projectManager.canvasOffset.height
                    )
                    .scaleEffect(projectManager.canvasScale)
                    .zIndex(draggedPodId == pod.id ? 100 : (projectManager.selectedPod?.id == pod.id ? 10 : 1))
                    .onHover { hovering in
                        hoveredPodId = hovering ? pod.id : nil
                    }
                }
            }
            .coordinateSpace(name: "podCanvas")
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        projectManager.canvasScale = max(0.5, min(2.0, value))
                    }
            )
            // AI chrome sits on top but only the bar itself takes hits (not the full height)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if showAIResponse {
                        AIResponseBubble(message: aiResponseMessage) {
                            withAnimation { showAIResponse = false }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                    }
                    AIPromptInput(
                        prompt: $aiPrompt,
                        aiService: projectManager.aiService,
                        isProcessing: projectManager.aiService.isProcessing,
                        onSubmit: { handleAIPrompt() }
                    )
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    /// Drag empty canvas (or ⌘-drag anywhere) to pan the view.
    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // Don't pan while moving a pod or drawing a connection
                guard !isDragging, projectManager.connectingFromPodId == nil else { return }
                if !isPanning {
                    isPanning = true
                    initialPanOffset = projectManager.canvasOffset
                    NSCursor.closedHand.push()
                }
                projectManager.canvasOffset = CGSize(
                    width: initialPanOffset.width + value.translation.width,
                    height: initialPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                if isPanning {
                    NSCursor.pop()
                }
                isPanning = false
                initialPanOffset = .zero
            }
    }
    
    private func handleCanvasTap() {
        // Cancel in-progress connection, or clear selection
        if projectManager.connectingFromPodId != nil {
            projectManager.endConnection()
            projectManager.hoverConnectionPoint(podId: nil, isOutput: false)
            connectingToPoint = nil
            return
        }
        projectManager.saveCurrentPodFiles()
        projectManager.selectedPod = nil
    }
    
    private func selectPod(id: UUID) {
        projectManager.saveCurrentPodFiles()
        if let live = projectManager.pods.first(where: { $0.id == id }) {
            projectManager.selectedPod = live
        }
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
    
    /// Pod card size used for port geometry (`pod.position` is the card center).
    static let podCardWidth: CGFloat = 200
    static let podCardHeight: CGFloat = 150
    
    /// Port position in view/canvas space (accounts for pan + zoom around pod center).
    private func canvasPort(for pod: Pod, isOutput: Bool) -> CGPoint {
        let halfW = Self.podCardWidth / 2
        let halfH = Self.podCardHeight / 2
        let relX = isOutput ? (halfW - 18) : -(halfW - 18)
        let relY = halfH - 16
        let scale = projectManager.canvasScale
        return CGPoint(
            x: pod.position.x + projectManager.canvasOffset.width + relX * scale,
            y: pod.position.y + projectManager.canvasOffset.height + relY * scale
        )
    }
    
    private func nearestInputPod(atCanvas point: CGPoint, excluding sourceId: UUID, threshold: CGFloat = 56) -> Pod? {
        var best: Pod?
        var bestDist = threshold
        for pod in projectManager.pods where pod.id != sourceId {
            let input = canvasPort(for: pod, isOutput: false)
            let dx = input.x - point.x
            let dy = input.y - point.y
            let d = sqrt(dx * dx + dy * dy)
            if d < bestDist {
                bestDist = d
                best = pod
            }
        }
        return best
    }
}

struct PodView: View {
    let pod: Pod
    let hoveredConnectionPoint: (podId: UUID, isOutput: Bool)?
    var isBeingDragged: Bool = false
    var onSelect: () -> Void
    var onConnectionDragChanged: (CGPoint) -> Void
    var onConnectionDragEnded: (CGPoint) -> Void
    var onConnectionCancel: () -> Void
    var onBodyDragChanged: (CGSize) -> Void
    var onBodyDragEnded: () -> Void
    
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showEnvEditor = false
    /// Tracks whether the current pointer interaction has already selected this pod.
    @State private var didSelectThisGesture = false
    /// True once movement exceeds the drag threshold (vs a plain click).
    @State private var isActivelyMoving = false
    
    private let moveThreshold: CGFloat = 4
    
    var isSelected: Bool {
        projectManager.selectedPod?.id == pod.id
    }
    
    private var isInference: Bool {
        pod.type == .inference || pod.isVirtual
    }
    
    var hasInputConnections: Bool {
        projectManager.pods.contains { $0.connections.contains(pod.id) }
    }
    
    var hasOutputConnections: Bool {
        !pod.connections.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header — type icon + name + status (no grab handle / selection checkmark)
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
                        .foregroundColor(.primary)
                        .onTapGesture(count: 2) {
                            if isInference {
                                openEnvEditor()
                            } else {
                                startRenaming()
                            }
                        }
                        .help(isInference ? "Double-click to edit environment" : "Double-click to rename")
                }
                
                Spacer()
                
                // Runtime status: green = running, red = stopped (click to toggle)
                Button {
                    projectManager.togglePodRunning(id: pod.id)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(pod.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: (pod.isRunning ? Color.green : Color.red).opacity(0.45), radius: pod.isRunning ? 3 : 0)
                        Text(pod.isRunning ? "ON" : "OFF")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(pod.isRunning ? Color.green : Color.red.opacity(0.9))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((pod.isRunning ? Color.green : Color.red).opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .help(pod.isRunning
                      ? "Running — click to stop (red)"
                      : "Stopped — click to start (green)")
                
                if isInference {
                    Button {
                        openEnvEditor()
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
                            .padding(4)
                            .background(Circle().fill(Color.purple.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .help("Edit environment keys")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            Divider()
            
            // Content preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: pod.isVirtual ? "key.fill" : pod.framework.icon)
                        .font(.system(size: 10))
                        .foregroundColor(pod.framework.color)
                    Text(pod.isVirtual ? "VIRTUAL · ENV" : pod.framework.rawValue)
                        .font(.system(size: 10))
                        .foregroundColor(pod.framework.color)
                    if pod.isVirtual {
                        Text("\(pod.environmentVariables.count) keys")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                
                if pod.isVirtual {
                    Text(pod.environmentVariables.prefix(3).map(\.key).joined(separator: ", ")
                          + (pod.environmentVariables.count > 3 ? "…" : ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .lineLimit(2)
                    
                    if isSelected {
                        Button {
                            openEnvEditor()
                        } label: {
                            Label("Edit Environment…", systemImage: "slider.horizontal.3")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        .help("Open the env editor for this Inference hub")
                    }
                } else if let mainFile = pod.selectedFile, !mainFile.content.isEmpty {
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
            
            // Relationship ports: left = input, right = output
            HStack {
                ConnectionPointView(
                    pod: pod,
                    isOutput: false,
                    isConnected: hasInputConnections,
                    isHovered: hoveredConnectionPoint?.podId == pod.id && hoveredConnectionPoint?.isOutput == false,
                    color: pod.framework.color,
                    onDragChanged: nil,
                    onDragEnded: nil,
                    onTapInput: {
                        if let from = projectManager.connectingFromPodId, from != pod.id {
                            projectManager.connectPods(from: from, to: pod.id)
                            onConnectionCancel()
                        }
                    }
                )
                
                Spacer()
                
                ConnectionPointView(
                    pod: pod,
                    isOutput: true,
                    isConnected: hasOutputConnections,
                    isHovered: hoveredConnectionPoint?.podId == pod.id && hoveredConnectionPoint?.isOutput == true,
                    color: pod.framework.color,
                    onDragChanged: { canvas in
                        onConnectionDragChanged(canvas)
                    },
                    onDragEnded: { canvas in
                        onConnectionDragEnded(canvas)
                    },
                    onTapInput: nil
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: PodCanvasView.podCardWidth, height: PodCanvasView.podCardHeight, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(pod.isVirtual
                      ? Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.08)
                      : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isBeingDragged
                                ? Color.accentColor
                                : (pod.isVirtual
                                   ? Color(red: 0.55, green: 0.35, blue: 0.95).opacity(isSelected ? 1 : 0.55)
                                   : (isSelected ? pod.language.color : Color.clear)),
                            style: StrokeStyle(
                                lineWidth: isBeingDragged ? 2.5 : (pod.isVirtual ? (isSelected ? 2.5 : 1.5) : (isSelected ? 3 : 0)),
                                dash: pod.isVirtual && !isBeingDragged ? [6, 4] : []
                            )
                        )
                )
                .shadow(
                    color: isBeingDragged
                        ? Color.accentColor.opacity(0.35)
                        : (isSelected
                           ? (pod.isVirtual ? Color.purple.opacity(0.35) : pod.language.color.opacity(0.4))
                           : .black.opacity(0.1)),
                    radius: isBeingDragged ? 12 : (isSelected ? 8 : 5),
                    y: isBeingDragged ? 6 : 2
                )
        )
        .opacity(isBeingDragged ? 0.95 : 1)
        // minDistance 0 so a plain click selects; movement past threshold moves the pod.
        // Connection ports keep highPriorityGesture so linking still wins on the ports.
        .gesture(podPointerGesture)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard projectManager.connectingFromPodId == nil else { return }
                if isInference {
                    openEnvEditor()
                } else if !isRenaming {
                    startRenaming()
                }
            }
        )
        .sheet(isPresented: $showEnvEditor) {
            InferenceEnvEditorView(podId: pod.id)
                .environmentObject(projectManager)
        }
        .onChange(of: isRenaming) { newValue in
            if !newValue && !renameText.isEmpty && renameText != pod.name {
                finishRenaming()
            }
        }
    }
    
    /// Click = select; drag past threshold = move. Works even when TapGesture alone
    /// would lose to DragGesture (common macOS SwiftUI conflict).
    private var podPointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("podCanvas"))
            .onChanged { value in
                guard projectManager.connectingFromPodId == nil else { return }
                
                if !didSelectThisGesture {
                    didSelectThisGesture = true
                    onSelect()
                }
                
                let dist = hypot(value.translation.width, value.translation.height)
                if dist >= moveThreshold {
                    isActivelyMoving = true
                    onBodyDragChanged(value.translation)
                }
            }
            .onEnded { value in
                let dist = hypot(value.translation.width, value.translation.height)
                if isActivelyMoving || dist >= moveThreshold {
                    onBodyDragEnded()
                }
                didSelectThisGesture = false
                isActivelyMoving = false
            }
    }
    
    private func openEnvEditor() {
        projectManager.saveCurrentPodFiles()
        if let live = projectManager.pods.first(where: { $0.id == pod.id }) {
            projectManager.selectedPod = live
        }
        showEnvEditor = true
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
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onTapInput: (() -> Void)?
    
    @EnvironmentObject var projectManager: ProjectManager
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Generous hit target
            Circle()
                .fill(Color.primary.opacity(0.001))
                .frame(width: 28, height: 28)
            
            Circle()
                .fill(isConnected || isHovered || isDragging ? color : Color(NSColor.controlBackgroundColor))
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(color, lineWidth: isHovered || isDragging ? 3 : 2)
                )
                .shadow(color: (isHovered || isDragging) ? color.opacity(0.45) : .clear, radius: 4)
                .scaleEffect(isHovered || isDragging ? 1.25 : 1.0)
                .animation(.spring(response: 0.2), value: isHovered || isDragging)
        }
        .contentShape(Rectangle())
        .help(isOutput
              ? "Drag from this port to another pod’s left port to link them"
              : "Drop a link here from another pod’s right port")
        .highPriorityGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("podCanvas"))
                .onChanged { value in
                    guard isOutput else { return }
                    isDragging = true
                    // value.location is already in podCanvas space (matches .position)
                    onDragChanged?(value.location)
                }
                .onEnded { value in
                    guard isOutput else { return }
                    isDragging = false
                    onDragEnded?(value.location)
                }
        )
        .onTapGesture {
            if !isOutput {
                onTapInput?()
            } else if projectManager.connectingFromPodId == pod.id {
                projectManager.endConnection()
            }
        }
        .contextMenu {
            if isConnected {
                Button("Disconnect relationships", role: .destructive) {
                    if isOutput {
                        if let index = projectManager.pods.firstIndex(where: { $0.id == pod.id }) {
                            projectManager.pods[index].connections.removeAll()
                        }
                    } else {
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
    /// Points already in view/canvas space (with pan applied).
    let from: CGPoint
    let to: CGPoint
    let color: Color
    var isTemporary: Bool = false
    
    var body: some View {
        ZStack {
            // Soft glow under the stroke
            path
                .stroke(
                    color.opacity(isTemporary ? 0.15 : 0.2),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
            
            path
                .stroke(
                    isTemporary ? color.opacity(0.55) : color.opacity(0.85),
                    style: StrokeStyle(
                        lineWidth: isTemporary ? 2 : 2.5,
                        lineCap: .round,
                        dash: isTemporary ? [6, 5] : []
                    )
                )
            
            // Arrow tip at the input end
            if !isTemporary {
                arrowHead
            }
        }
        .allowsHitTesting(false)
    }
    
    private var path: Path {
        Path { p in
            p.move(to: from)
            let dx = to.x - from.x
            let control1 = CGPoint(x: from.x + max(40, dx * 0.45), y: from.y)
            let control2 = CGPoint(x: to.x - max(40, dx * 0.45), y: to.y)
            p.addCurve(to: to, control1: control1, control2: control2)
        }
    }
    
    private var arrowHead: some View {
        let angle = atan2(to.y - from.y, to.x - from.x)
        return Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: 8))
            .foregroundStyle(color.opacity(0.9))
            .rotationEffect(.radians(Double(angle)))
            .position(to)
    }
}

