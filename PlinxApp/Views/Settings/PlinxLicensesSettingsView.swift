import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Open-source notices (parent-only)
//
// Plinx and the Strimr code it absorbed are GPL-3.0; the third-party list and
// license texts are upstream's (`OpenSourceLicense`, bundled `License-*.txt`).
// Only reachable inside parent-gated Settings, so the source links on iPhone
// and iPad never appear in kid-facing UI.
// ─────────────────────────────────────────────────────────────────────────────

struct PlinxLicensesSettingsView: View {
    var body: some View {
        List {
            Section {
                row(Self.plinx)
                row(.strimr)
            }

            Section {
                ForEach(OpenSourceLicense.dependencies) { license in
                    row(license)
                }
            } header: {
                Text("settings.licenses.dependencies")
            }
        }
        .plinxSettingsListPage(title: Text("settings.licenses.title"))
        .accessibilityIdentifier("settings.licenses.screen")
    }

    private func row(_ license: OpenSourceLicense) -> some View {
        NavigationLink {
            PlinxLicenseDetailView(license: license)
        } label: {
            HStack(spacing: 18) {
                Text(verbatim: license.name)
                Spacer(minLength: 18)
                Text(verbatim: license.license)
                    .foregroundStyle(.secondary)
                #if os(tvOS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                #endif
            }
        }
        #if os(tvOS)
        .plinxSettingsListButton()
        #endif
    }

    static let plinx = OpenSourceLicense(
        name: "Plinx",
        license: "GPL-3.0",
        url: PlinxSettingsLinks.plinxSource,
        textFiles: ["GPL-3.0"]
    )
}

private struct PlinxLicenseDetailView: View {
    let license: OpenSourceLicense
    private let paragraphs: [String]

    init(license: OpenSourceLicense) {
        self.license = license
        paragraphs = license.text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        #if os(tvOS)
        // Each paragraph takes focus so the remote can scroll the whole text.
        List {
            Section {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    PlinxLicenseParagraph(text: paragraph)
                }
            } header: {
                Text(verbatim: license.url.absoluteString)
            }
        }
        .plinxSettingsListPage(title: Text(verbatim: license.name))
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(destination: license.url) {
                    Label("settings.licenses.source", systemImage: "arrow.up.right.square")
                }
                Text(verbatim: paragraphs.joined(separator: "\n\n"))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(Text(verbatim: license.name))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.appBackground.ignoresSafeArea())
        .plinxSettingsChrome()
        #endif
    }
}

#if os(tvOS)
private struct PlinxLicenseParagraph: View {
    let text: String

    var body: some View {
        Button {} label: {
            Text(verbatim: text)
                .font(.system(size: 22, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
        .plinxSettingsListButton()
    }
}
#endif
