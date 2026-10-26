import SwiftUI

struct DownloadQueueView: View { var body: some View { ContentUnavailableView("No queued downloads", systemImage: "list.bullet", description: Text("Downloads in progress will appear here.")) } }
struct HistoryView: View { var body: some View { ContentUnavailableView("No download history", systemImage: "books.vertical", description: Text("Verified downloads will appear here.")) } }
struct SettingsView: View { @AppStorage("minimumRequestInterval") private var interval = 15.0; var body: some View { Form { Section("Network Courtesy") { Stepper("Minimum request interval: \(Int(interval)) seconds", value: $interval, in: 10...120, step: 5); Text("This conservative setting is not an AO3-provided quota. Slower is gentler.").foregroundStyle(.secondary) } }.padding().frame(minWidth: 480) } }
struct AboutView: View { var body: some View { VStack(spacing: 16) { Image(systemName: "arrow.down.doc").font(.system(size: 56)); Text("AO3 Downloader").font(.largeTitle); Text("Unofficial application; not affiliated with AO3 or the Organization for Transformative Works.").multilineTextAlignment(.center); Link("Source repository", destination: URL(string: "https://github.com/shasan731/ao3-downloader")!); Link("AO3 Terms of Service FAQ", destination: URL(string: "https://archiveofourown.org/tos_faq")!) }.padding(40).frame(maxWidth: 600) } }

