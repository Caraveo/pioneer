import SwiftUI

struct FrameworkSettingsView: View {
    @StateObject private var frameworkManager = FrameworkManager()
    @Environment(\.dismiss) private var dismiss
    
    private let categories: [(title: String, frameworks: [Framework])] = [
        ("Apple (macOS / iOS)", [.swiftui, .swift, .objectiveC]),
        ("Android", [.kotlin, .jetpackCompose, .androidJava]),
        ("Cross-platform", [.reactNative, .flutter]),
        ("JavaScript / TypeScript", [.nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs]),
        ("Python", [.django, .flask, .fastapi, .purepy]),
        ("Database", [.postgresql, .mysql, .mongodb, .redis, .sqlite]),
        ("Vault / Storage", [.vault, .minio, .s3, .localVolume, .nfs, .seaweedfs]),
        ("Systems", [.rust, .go]),
        ("Java / JVM", [.java, .spring]),
        ("Infrastructure", [.docker, .kubernetes, .terraform])
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    Text("Enable frameworks globally. The Properties panel only shows frameworks assumed for the selected Pod Type.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Pod type → framework cheat sheet
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pod Type → Framework")
                            .font(.headline)
                        ForEach(PodType.allCases) { type in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: type.icon)
                                        .foregroundColor(type.color)
                                    Text(type.rawValue)
                                        .fontWeight(.semibold)
                                    Text("default: \(type.defaultFramework.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(type.compatibleFrameworks.map(\.rawValue).joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                    ForEach(categories, id: \.title) { category in
                        FrameworkCategorySection(
                            title: category.title,
                            frameworks: category.frameworks,
                            frameworkManager: frameworkManager
                        )
                    }
                }
                .padding(.bottom)
            }
        }
        .frame(width: 640, height: 560)
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
        .padding(.horizontal)
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
