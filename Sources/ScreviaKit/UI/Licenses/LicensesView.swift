import AppKit
import LicenseList
import SwiftUI

struct LicensesView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Library.libraries) { library in
                    LicenseRow(library: library)
                }
            } footer: {
                Text(L10n.text("licenses.frameworksNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LicenseRow: View {
    let library: Library

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(library.licenseBody)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.name)

                    if let host = library.url?.host() {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let licenseLabel = library.licenseLabel {
                    Text(licenseLabel)
                        .font(ScreviaTheme.utilityFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            ScreviaTheme.surface,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }

                if let url = library.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(url.absoluteString)
                }
            }
        }
    }
}

extension Library {
    /// A short badge for the license, sniffed from the text's opening lines.
    ///
    /// Returns nil rather than guessing when the text is not recognised — an
    /// unlabelled row is honest, a mislabelled one is not.
    var licenseLabel: String? {
        let head = licenseBody.prefix(300).lowercased()

        if head.contains("mit license") {
            return "MIT"
        }
        if head.contains("apache license") {
            return "Apache 2.0"
        }
        if head.contains("mozilla public license") {
            return "MPL 2.0"
        }
        if head.contains("gnu general public license") {
            return "GPL"
        }
        if head.contains("redistribution and use in source and binary forms") {
            return "BSD"
        }
        return nil
    }
}

#if DEBUG
#Preview("Licenses") {
    LicensesView()
        .frame(width: 520, height: 460)
}
#endif
