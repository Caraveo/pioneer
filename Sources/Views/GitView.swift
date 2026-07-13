import SwiftUI
import AppKit

/// Per-pod Git workspace. Each pod is its own repository for team scale
/// (Android / Apple / Web) — independent ownership, CI, and release cadence.
struct GitView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    @State private var snapshot = GitRepoSnapshot.empty
    @State private var isLoading = false
    @State private var isBusy = false
    @State private var commitMessage = ""
    @State private var newBranchName = ""
    @State private var remoteURL = ""
    @State private var mergeTarget = ""
    @State private var logText = ""
    @State private var showRationale = false
    @State private var selectedCommitId: String?
    
    var body: some View {
        Group {
            if let pod = projectManager.selectedPod {
                gitWorkspace(for: pod)
            } else {
                emptyState
            }
        }
        .onAppear { Task { await refresh() } }
        .onChange(of: projectManager.selectedPod?.id) { _ in
            Task { await refresh() }
        }
    }
    
    // MARK: - Empty
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Pod Selected")
                .font(.title3.weight(.semibold))
            Text("Select a pod to manage its private git repository.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Workspace
    
    @ViewBuilder
    private func gitWorkspace(for pod: Pod) -> some View {
        VStack(spacing: 0) {
            header(pod: pod)
            Divider()
            
            if isLoading && !snapshot.isRepo {
                ProgressView("Loading git…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !snapshot.isRepo {
                initRepoCard(pod: pod)
            } else {
                HSplitView {
                    // Left: branches + remotes
                    leftColumn(pod: pod)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    
                    // Center: changes + commit
                    centerColumn(pod: pod)
                        .frame(minWidth: 320)
                    
                    // Right: history
                    rightColumn
                        .frame(minWidth: 280, idealWidth: 340)
                }
            }
            
            if !logText.isEmpty {
                Divider()
                logBar
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Header
    
    private func header(pod: Pod) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("GIT")
                    .font(.headline)
                Text("\(pod.name) · own repository · \(pod.type.rawValue) · \(pod.framework.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if snapshot.isRepo {
                branchBadge
                if snapshot.ahead > 0 || snapshot.behind > 0 {
                    Text("↑\(snapshot.ahead) ↓\(snapshot.behind)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            
            Button {
                showRationale.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Why each pod is its own git repo")
            .popover(isPresented: $showRationale, arrowEdge: .bottom) {
                rationalePopover
            }
            
            Button {
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var branchBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
            Text(snapshot.branch.isEmpty ? "—" : snapshot.branch)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.15))
        )
        .foregroundStyle(Color.accentColor)
    }
    
    private var rationalePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why one git repo per pod?")
                .font(.headline)
            Text("Scale & growth")
                .font(.subheadline.weight(.semibold))
            Text("Android team, Apple team, and Web team can own their pods independently — separate review, CI, permissions, and release trains without monorepo coordination tax.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Simplification")
                .font(.subheadline.weight(.semibold))
            Text("Each pod already maps to one codebase + one Kubernetes pod. Giving it its own git remote matches that boundary: clone, push, and merge stay obvious.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }
    
    // MARK: - Init
    
    private func initRepoCard(pod: Pod) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No git repository yet")
                .font(.title3.weight(.semibold))
            Text("This pod will get its own repo under the project folder.\nTeams (Android / Apple / Web) can own and ship independently.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            
            Button {
                Task { await initRepo(pod: pod) }
            } label: {
                Label("Initialize Git Repo", systemImage: "plus.circle.fill")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Left: branches
    
    private func leftColumn(pod: Pod) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Branches", icon: "arrow.triangle.branch")
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.localBranches) { branch in
                        branchRow(branch)
                    }
                    
                    if !snapshot.remoteBranches.isEmpty {
                        Text("Remote")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                            .padding(.horizontal, 12)
                        ForEach(snapshot.remoteBranches) { branch in
                            branchRow(branch)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("New branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("feature/…", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create") {
                        Task { await createBranch() }
                    }
                    .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                }
                
                Text("Merge into current")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                HStack {
                    Picker("Merge", selection: $mergeTarget) {
                        Text("Select…").tag("")
                        ForEach(snapshot.localBranches.filter { !$0.isCurrent }) { b in
                            Text(b.name).tag(b.name)
                        }
                    }
                    .labelsHidden()
                    Button("Merge") {
                        Task { await mergeBranch() }
                    }
                    .disabled(mergeTarget.isEmpty || isBusy)
                }
            }
            .padding(12)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote origin")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let origin = snapshot.remotes.first(where: { $0.name == "origin" }) {
                    Text(origin.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                TextField("git@github.com:org/pod.git", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                Button("Save origin") {
                    Task { await saveRemote() }
                }
                .disabled(remoteURL.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
            }
            .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
    }
    
    private func branchRow(_ branch: GitBranch) -> some View {
        Button {
            guard !branch.isCurrent, !branch.isRemote else {
                if branch.isRemote {
                    // checkout remote tracking local name if possible
                    let local = branch.name.replacingOccurrences(of: "origin/", with: "")
                    Task { await checkout(local) }
                }
                return
            }
            Task { await checkout(branch.name) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(branch.isCurrent ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
                Text(branch.name)
                    .font(.system(size: 12, weight: branch.isCurrent ? .semibold : .regular, design: .default))
                    .foregroundStyle(branch.isCurrent ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer()
                if branch.isCurrent {
                    Text("HEAD")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
    
    // MARK: - Center: changes + commit + push
    
    private func centerColumn(pod: Pod) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Changes", icon: "doc.badge.gearshape")
            
            // Action bar
            HStack(spacing: 8) {
                Button {
                    Task { await runAction { await GitService.stageAll(at: projectURL(for: pod)) } }
                } label: {
                    Label("Stage all", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                
                Button {
                    Task { await runAction { await GitService.unstageAll(at: projectURL(for: pod)) } }
                } label: {
                    Label("Unstage", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    Task { await runAction { await GitService.fetch(at: projectURL(for: pod)) } }
                } label: {
                    Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                
                Button {
                    Task { await runAction { await GitService.pull(branch: snapshot.branch, at: projectURL(for: pod)) } }
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                
                Button {
                    Task { await runAction {
                        await GitService.push(branch: snapshot.branch, at: projectURL(for: pod), setUpstream: true)
                    } }
                } label: {
                    Label("Push origin", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statusGroup("Staged", entries: snapshot.staged, color: .green)
                    statusGroup("Modified", entries: snapshot.unstaged, color: .orange)
                    statusGroup("Untracked", entries: snapshot.untracked, color: .blue)
                    
                    if snapshot.dirtyCount == 0 {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Working tree clean")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
            }
            
            Divider()
            
            // Commit box
            VStack(alignment: .leading, spacing: 10) {
                Text("Commit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Describe this change…", text: $commitMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                
                HStack {
                    Text(snapshot.dirtyCount == 0 ? "Nothing to commit" : "\(snapshot.dirtyCount) file(s) will be staged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await commit(pod: pod) }
                    } label: {
                        Label("Commit", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    
                    Button {
                        Task { await commitAndPush(pod: pod) }
                    } label: {
                        Label("Commit & Push", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
    
    private func statusGroup(_ title: String, entries: [GitStatusEntry], color: Color) -> some View {
        Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.statusCode)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(color)
                                .frame(width: 16)
                            Text(entry.path)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color.opacity(0.06))
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Right: history
    
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("History", icon: "clock.arrow.circlepath")
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.commits) { commit in
                        commitRow(commit)
                        Divider().padding(.leading, 28)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.25))
    }
    
    private func commitRow(_ commit: GitCommitInfo) -> some View {
        Button {
            selectedCommitId = commit.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                        .background(Circle().fill(selectedCommitId == commit.id ? Color.accentColor : Color.clear))
                        .frame(width: 10, height: 10)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 12)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(commit.shortHash)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                        Text(commit.author)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(commit.relativeDate)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Shared chrome
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var logBar: some View {
        ScrollView {
            Text(logText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(maxHeight: 100)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func projectURL(for pod: Pod) -> URL {
        if let path = pod.projectPath {
            return URL(fileURLWithPath: path)
        }
        return projectManager.podProjectService.getProjectPath(
            for: pod,
            projectName: projectManager.projectName
        )
    }
    
    @MainActor
    private func appendLog(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if logText.isEmpty {
            logText = trimmed
        } else {
            logText += "\n" + trimmed
        }
        // keep log short
        let lines = logText.components(separatedBy: "\n")
        if lines.count > 80 {
            logText = lines.suffix(80).joined(separator: "\n")
        }
    }
    
    private func refresh() async {
        guard let pod = await MainActor.run(body: { projectManager.selectedPod }) else {
            await MainActor.run { snapshot = .empty }
            return
        }
        await MainActor.run { isLoading = true }
        let url = await MainActor.run { projectURL(for: pod) }
        let snap = await GitService.snapshot(at: url)
        await MainActor.run {
            snapshot = snap
            if remoteURL.isEmpty, let origin = snap.remotes.first(where: { $0.name == "origin" }) {
                remoteURL = origin.url
            }
            if mergeTarget.isEmpty == false,
               !snap.localBranches.contains(where: { $0.name == mergeTarget }) {
                mergeTarget = ""
            }
            isLoading = false
        }
    }
    
    private func initRepo(pod: Pod) async {
        await MainActor.run { isBusy = true }
        let url = await MainActor.run { projectURL(for: pod) }
        // Ensure path on model
        await MainActor.run {
            if let idx = projectManager.pods.firstIndex(where: { $0.id == pod.id }) {
                projectManager.pods[idx].projectPath = url.path
                projectManager.selectedPod = projectManager.pods[idx]
            }
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Persist current code first
        if let latest = await MainActor.run(body: { projectManager.selectedPod }) {
            try? await projectManager.podProjectService.saveAllFiles(pod: latest, projectPath: url)
        }
        let log = await GitService.ensureRepository(at: url, podName: pod.name)
        await MainActor.run {
            appendLog(log)
            isBusy = false
        }
        await refresh()
    }
    
    private func runAction(_ body: () async -> String) async {
        await MainActor.run { isBusy = true }
        let out = await body()
        await MainActor.run {
            appendLog(out)
            isBusy = false
        }
        await refresh()
    }
    
    private func commit(pod: Pod) async {
        let msg = commitMessage
        await MainActor.run { isBusy = true }
        let url = projectURL(for: pod)
        // Save editor files into the pod folder before commit
        if let latest = await MainActor.run(body: { () -> Pod? in
            if let idx = projectManager.pods.firstIndex(where: { $0.id == pod.id }) {
                return projectManager.pods[idx]
            }
            return projectManager.selectedPod
        }) {
            try? await projectManager.podProjectService.saveAllFiles(pod: latest, projectPath: url)
        }
        let out = await GitService.commit(message: msg, at: url)
        await MainActor.run {
            appendLog(out)
            if !out.lowercased().contains("error") && !out.lowercased().contains("nothing to commit") {
                commitMessage = ""
            }
            isBusy = false
        }
        await refresh()
    }
    
    private func commitAndPush(pod: Pod) async {
        await commit(pod: pod)
        await runAction {
            await GitService.push(branch: snapshot.branch, at: projectURL(for: pod), setUpstream: true)
        }
    }
    
    private func createBranch() async {
        let name = newBranchName
        await runAction {
            let out = await GitService.createBranch(name, checkout: true, at: projectURL(for: projectManager.selectedPod!))
            return out
        }
        await MainActor.run { newBranchName = "" }
    }
    
    private func checkout(_ name: String) async {
        await runAction {
            await GitService.checkout(branch: name, at: projectURL(for: projectManager.selectedPod!))
        }
    }
    
    private func mergeBranch() async {
        let target = mergeTarget
        await runAction {
            await GitService.merge(branch: target, at: projectURL(for: projectManager.selectedPod!))
        }
    }
    
    private func saveRemote() async {
        let url = remoteURL
        await runAction {
            await GitService.setRemote(url: url, at: projectURL(for: projectManager.selectedPod!))
        }
    }
}
