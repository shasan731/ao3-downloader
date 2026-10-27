import SwiftUI

struct SettingsView: View {
    @AppStorage("minimumRequestInterval") private var interval = 15.0
    @AppStorage("allowAdultContent") private var allowAdultContent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader

                GroupBox("Content Access") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Allow public Mature/Explicit works", isOn: $allowAdultContent)
                        Text("Equivalent to choosing “Yes, continue” on AO3’s warning page. ArchiveBind never uses your browser session, AO3 account, or login-only works.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Network Courtesy") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Minimum request interval: \(Int(interval)) seconds", value: $interval, in: 10...120, step: 5)
                        Text("Requests remain globally serialized. This conservative app setting is not an AO3-provided quota; a longer interval is gentler. Changes apply after relaunch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Privacy") {
                    Label {
                        Text("Downloads and Library history stay on this Mac. ArchiveBind has no telemetry, ads, or cloud account.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Settings")
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings").font(.largeTitle.weight(.semibold))
            Text("Control content consent and the pace of network requests.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
