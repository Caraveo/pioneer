import Foundation

// MARK: - Models

struct GitBranch: Identifiable, Hashable {
    let name: String
    let isCurrent: Bool
    let isRemote: Bool
    var id: String { "\(isRemote ? "r:" : "l:")\(name)" }
    
    var displayName: String {
        if isRemote { return name }
        return name
    }
}

struct GitCommitInfo: Identifiable, Hashable {
    let hash: String
    let shortHash: String
    let message: String
    let author: String
    let relativeDate: String
    let date: String
    var id: String { hash }
}

struct GitStatusEntry: Identifiable, Hashable {
    enum Kind: String {
        case staged = "Staged"
        case unstaged = "Changed"
        case untracked = "Untracked"
    }
    let path: String
    let statusCode: String
    let kind: Kind
    var id: String { "\(kind.rawValue):\(path):\(statusCode)" }
}

struct GitRemoteInfo: Hashable {
    let name: String
    let url: String
}

struct GitRepoSnapshot {
    var isRepo: Bool
    var rootPath: String
    var branch: String
    var upstream: String?
    var remotes: [GitRemoteInfo]
    var localBranches: [GitBranch]
    var remoteBranches: [GitBranch]
    var commits: [GitCommitInfo]
    var staged: [GitStatusEntry]
    var unstaged: [GitStatusEntry]
    var untracked: [GitStatusEntry]
    var ahead: Int
    var behind: Int
    var lastError: String?
    
    static let empty = GitRepoSnapshot(
        isRepo: false,
        rootPath: "",
        branch: "",
        upstream: nil,
        remotes: [],
        localBranches: [],
        remoteBranches: [],
        commits: [],
        staged: [],
        unstaged: [],
        untracked: [],
        ahead: 0,
        behind: 0,
        lastError: nil
    )
    
    var dirtyCount: Int { staged.count + unstaged.count + untracked.count }
    var hasOrigin: Bool { remotes.contains { $0.name == "origin" } }
}

/// Each Pioneer pod is its **own** git repository (not a monorepo).
/// Design intent: Android / Apple / Web teams scale independently — simpler ownership, CI, and releases.
enum GitService {
    
    // MARK: - Ensure repo
    
    /// Initialize a git repo in the pod project path if missing.
    @discardableResult
    static func ensureRepository(at projectPath: URL, podName: String) async -> String {
        let fm = FileManager.default
        try? fm.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        let gitDir = projectPath.appendingPathComponent(".git")
        if fm.fileExists(atPath: gitDir.path) {
            return "Git repo ready at \(projectPath.path)"
        }
        
        // Sensible default ignore
        let gitignore = projectPath.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: gitignore.path) {
            let ignore = """
            # Pioneer pod defaults
            .DS_Store
            *.xcuserstate
            DerivedData/
            build/
            .build/
            node_modules/
            venv/
            __pycache__/
            *.pyc
            .env
            .idea/
            *.iml
            local.properties
            .gradle/
            """
            try? ignore.write(to: gitignore, atomically: true, encoding: .utf8)
        }
        
        var log = await run(projectPath, ["init", "-b", "main"])
        _ = await run(projectPath, ["config", "user.useConfigOnly", "false"])
        
        // Initial commit if there is anything to commit
        _ = await run(projectPath, ["add", "-A"])
        let status = await run(projectPath, ["status", "--porcelain"])
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msg = "chore: initial commit for pod \(podName)"
            log += await run(projectPath, ["commit", "-m", msg, "--allow-empty-message"])
        }
        return "Initialized git repo for pod “\(podName)”\n" + log
    }
    
    // MARK: - Snapshot
    
    static func snapshot(at projectPath: URL) async -> GitRepoSnapshot {
        var snap = GitRepoSnapshot.empty
        snap.rootPath = projectPath.path
        
        let gitDir = projectPath.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            snap.lastError = "Not a git repository yet"
            return snap
        }
        snap.isRepo = true
        
        let branch = await run(projectPath, ["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        snap.branch = branch == "HEAD" ? "(detached)" : branch
        
        let upstream = await run(projectPath, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !upstream.isEmpty && !upstream.lowercased().contains("error") && !upstream.contains("fatal") {
            snap.upstream = upstream
        }
        
        // ahead/behind
        if let up = snap.upstream {
            let counts = await run(projectPath, ["rev-list", "--left-right", "--count", "\(up)...HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = counts.split(whereSeparator: { $0.isWhitespace })
            if parts.count == 2 {
                snap.behind = Int(parts[0]) ?? 0
                snap.ahead = Int(parts[1]) ?? 0
            }
        }
        
        // remotes
        let remoteOut = await run(projectPath, ["remote", "-v"])
        var remoteMap: [String: String] = [:]
        for line in remoteOut.components(separatedBy: .newlines) {
            let cols = line.split(whereSeparator: { $0.isWhitespace })
            guard cols.count >= 2 else { continue }
            let name = String(cols[0])
            let url = String(cols[1])
            if remoteMap[name] == nil { remoteMap[name] = url }
        }
        snap.remotes = remoteMap.map { GitRemoteInfo(name: $0.key, url: $0.value) }.sorted { $0.name < $1.name }
        
        // branches
        let localOut = await run(projectPath, ["branch", "--format=%(refname:short)%09%(HEAD)"])
        var locals: [GitBranch] = []
        for line in localOut.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            let rawName = parts.first?.trimmingCharacters(in: .whitespaces) ?? line
            let name = rawName.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            locals.append(GitBranch(name: name, isCurrent: name == snap.branch, isRemote: false))
        }
        locals = locals.map { b in
            GitBranch(name: b.name, isCurrent: b.name == snap.branch, isRemote: false)
        }
        snap.localBranches = locals.sorted { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent }
            return a.name < b.name
        }
        
        let remoteOutB = await run(projectPath, ["branch", "-r", "--format=%(refname:short)"])
        snap.remoteBranches = remoteOutB.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("->") }
            .map { GitBranch(name: $0, isCurrent: false, isRemote: true) }
        
        // commits
        let logFormat = "%H%x09%h%x09%s%x09%an%x09%ar%x09%ai"
        let logOut = await run(projectPath, ["log", "-n", "40", "--format=\(logFormat)"])
        var commits: [GitCommitInfo] = []
        for line in logOut.components(separatedBy: .newlines) where !line.isEmpty {
            let p = line.components(separatedBy: "\t")
            guard p.count >= 6 else { continue }
            commits.append(GitCommitInfo(
                hash: p[0],
                shortHash: p[1],
                message: p[2],
                author: p[3],
                relativeDate: p[4],
                date: p[5]
            ))
        }
        snap.commits = commits
        
        // status porcelain
        let st = await run(projectPath, ["status", "--porcelain"])
        for line in st.components(separatedBy: .newlines) where line.count >= 3 {
            let x = String(line.prefix(1))
            let y = String(line.dropFirst().prefix(1))
            var path = String(line.dropFirst(3))
            if path.contains(" -> ") {
                path = path.components(separatedBy: " -> ").last ?? path
            }
            if x != " " && x != "?" {
                snap.staged.append(GitStatusEntry(path: path, statusCode: x, kind: .staged))
            }
            if y != " " && y != "?" {
                snap.unstaged.append(GitStatusEntry(path: path, statusCode: y, kind: .unstaged))
            }
            if x == "?" || y == "?" {
                snap.untracked.append(GitStatusEntry(path: path, statusCode: "?", kind: .untracked))
            }
        }
        
        return snap
    }
    
    // MARK: - Actions
    
    static func stageAll(at path: URL) async -> String {
        await run(path, ["add", "-A"])
    }
    
    static func stage(paths: [String], at path: URL) async -> String {
        guard !paths.isEmpty else { return "" }
        return await run(path, ["add"] + paths)
    }
    
    static func unstageAll(at path: URL) async -> String {
        await run(path, ["restore", "--staged", "."])
    }
    
    static func commit(message: String, at path: URL) async -> String {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return "Commit message is empty" }
        _ = await stageAll(at: path)
        return await run(path, ["commit", "-m", msg])
    }
    
    static func push(remote: String = "origin", branch: String? = nil, at path: URL, setUpstream: Bool = true) async -> String {
        var args = ["push"]
        if setUpstream { args.append("-u") }
        args.append(remote)
        if let branch, !branch.isEmpty {
            args.append(branch)
        }
        return await run(path, args)
    }
    
    static func pull(remote: String = "origin", branch: String? = nil, at path: URL) async -> String {
        var args = ["pull", "--no-edit", remote]
        if let branch, !branch.isEmpty { args.append(branch) }
        return await run(path, args)
    }
    
    static func fetch(remote: String = "origin", at path: URL) async -> String {
        await run(path, ["fetch", remote, "--prune"])
    }
    
    static func checkout(branch: String, at path: URL) async -> String {
        await run(path, ["checkout", branch])
    }
    
    static func createBranch(_ name: String, checkout: Bool = true, at path: URL) async -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Branch name is empty" }
        if checkout {
            return await run(path, ["checkout", "-b", trimmed])
        }
        return await run(path, ["branch", trimmed])
    }
    
    static func merge(branch: String, at path: URL) async -> String {
        await run(path, ["merge", "--no-edit", branch])
    }
    
    static func setRemote(name: String = "origin", url: String, at path: URL) async -> String {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return "Remote URL is empty" }
        let existing = await run(path, ["remote"])
        if existing.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces) == name }) {
            return await run(path, ["remote", "set-url", name, u])
        }
        return await run(path, ["remote", "add", name, u])
    }
    
    static func discardWorkingTree(at path: URL) async -> String {
        let a = await run(path, ["checkout", "--", "."])
        let b = await run(path, ["clean", "-fd"])
        return a + b
    }
    
    // MARK: - Shell
    
    private static func run(_ projectPath: URL, _ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            let out = Pipe()
            let err = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", projectPath.path] + arguments
            process.standardOutput = out
            process.standardError = err
            
            var env = ProcessInfo.processInfo.environment
            let extras = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
            env["PATH"] = extras.joined(separator: ":") + ":" + (env["PATH"] ?? "")
            // Prefer non-interactive push/pull failures over hanging on credentials when possible
            env["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = env
            
            process.terminationHandler = { _ in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                var result = o
                if !e.isEmpty { result += (result.isEmpty ? "" : "") + e }
                continuation.resume(returning: result)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)\n")
                }
            }
        }
    }
}
