import SwiftUI
import UIKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("logoColorScheme") private var storedColorScheme = LogoColorScheme.default.rawValue
    @State private var iconChangeError: String?

    private var colorScheme: LogoColorScheme {
        LogoColorScheme(rawValue: storedColorScheme) ?? .default
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        LogoMark(size: 84, colorScheme: colorScheme)
                        Text("Memento")
                            .font(.system(.title, design: .serif).weight(.semibold))
                        Text("Tommy Le")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(versionString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)

                    Text("A personal-CRM for remembering the people in your life — a running notebook per person, a family tree that draws itself, and a calendar of every birthday and anniversary that matters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 16)], spacing: 16) {
                        ForEach(LogoColorScheme.allCases) { scheme in
                            swatch(for: scheme)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("App Icon Color")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(supportsIconChange
                            ? "Changes both the Home Screen icon and the logo shown in Memento. iOS may ask you to confirm the change."
                            : "Changes the logo shown in Memento. The Dock icon can't be changed on Mac.")
                        if let iconChangeError {
                            Text(iconChangeError)
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
                }

                Section {
                    LabeledContent("Built with", value: "SwiftUI + SwiftData")
                    LabeledContent("Sync", value: "Private iCloud (CloudKit)")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("About Memento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func swatch(for scheme: LogoColorScheme) -> some View {
        let isSelected = scheme == colorScheme
        return Button {
            select(scheme)
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(
                        colors: [scheme.bg1, scheme.bg2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(Theme.aegean.opacity(isSelected ? 0.5 : 0), lineWidth: 2)
                            .padding(-3)
                    }
                Text(scheme.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scheme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Alternate app icons aren't supported when the iOS app runs on a Mac
    /// (Designed for iPad) — the Dock icon is fixed at install. Without this
    /// guard every swatch pick surfaced a spurious error while the in-app
    /// logo recolored fine.
    private var supportsIconChange: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private func select(_ scheme: LogoColorScheme) {
        storedColorScheme = scheme.rawValue
        iconChangeError = nil
        guard supportsIconChange else { return }
        UIApplication.shared.setAlternateIconName(scheme.iconAssetName) { error in
            guard let error else { return }
            Task { @MainActor in
                iconChangeError = "Couldn't update the Home Screen icon: \(error.localizedDescription)"
            }
        }
    }
}
