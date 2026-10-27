import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .accessibilityLabel("ArchiveBind icon")
                VStack(spacing: 5) {
                    Text("ArchiveBind").font(.largeTitle.weight(.semibold))
                    Text("Your stories, beautifully bound")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text("A private, local-first macOS companion for saving public AO3 works and crafting polished personal ebooks.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Link("GitHub Repository", destination: URL(string: "https://github.com/shasan731/ao3-downloader")!)
                    Link("User Guide", destination: URL(string: "https://github.com/shasan731/ao3-downloader/blob/main/docs/USER_GUIDE.md")!)
                }
                Divider()
                Label("No telemetry • No account access • Local Library", systemImage: "lock.shield.fill")
                    .foregroundStyle(.secondary)
                Text("ArchiveBind is unofficial and is not affiliated with Archive of Our Own or the Organization for Transformative Works. Please download responsibly and respect creators’ choices.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Link("AO3 Terms of Service FAQ", destination: URL(string: "https://archiveofourown.org/tos_faq")!)
            }
            .padding(36)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
    }
}
