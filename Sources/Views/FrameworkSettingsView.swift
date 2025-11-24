import SwiftUI

struct FrameworkSettingsView: View {
    @StateObject private var frameworkManager = FrameworkManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Framework Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enable or disable frameworks to customize which options appear when creating nodes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Framework categories
                    FrameworkCategorySection(
                        title: "JavaScript/TypeScript",
                        frameworks: [.nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs],
                        frameworkManager: frameworkManager
                    )
                    
                    FrameworkCategorySection(
                        title: "Python",
                        frameworks: [.django, .flask, .fastapi, .purepy],
                        frameworkManager: frameworkManager
                    )
                    
                    FrameworkCategorySection(
                        title: "Systems Programming",
                        frameworks: [.rust, .go],
                        frameworkManager: frameworkManager
                    )
                    
                    FrameworkCategorySection(
                        title: "Swift",
                        frameworks: [.swift, .swiftui],
                        frameworkManager: frameworkManager
                    )
                    
                    FrameworkCategorySection(
                        title: "Java",
                        frameworks: [.java, .spring],
                        frameworkManager: frameworkManager
                    )
                    
                    FrameworkCategorySection(
                        title: "Infrastructure",
                        frameworks: [.docker, .kubernetes, .terraform],
                        frameworkManager: frameworkManager
                    )
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
}

struct FrameworkCategorySection: View {
    let title: String
    let frameworks: [Framework]
    @ObservedObject var frameworkManager: FrameworkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            ForEach(frameworks) { framework in
                FrameworkToggleRow(
                    framework: framework,
                    isEnabled: frameworkManager.isEnabled(framework),
                    onToggle: { enabled in
                        frameworkManager.setEnabled(framework, enabled: enabled)
                    }
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct FrameworkToggleRow: View {
    let framework: Framework
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: framework.icon)
                .foregroundColor(framework.color)
                .frame(width: 24)
            
            Text(framework.rawValue)
                .font(.body)
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

