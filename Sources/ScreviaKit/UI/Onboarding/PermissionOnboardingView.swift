import SwiftUI

/// Shown at launch while Screen Recording is not granted. macOS prompts only
/// once per app, so after that this window is the only guidance a user gets.
struct PermissionOnboardingView: View {
    let onOpenSettings: () -> Void
    let onRelaunch: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                AboutAppIcon()
                    .scaleEffect(56.0 / 84.0)
                    .frame(width: 56, height: 56)

                Text(L10n.text("permission.title"))
                    .font(.system(size: 15, weight: .bold))
            }

            Text(L10n.text("permission.message"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                step(1, L10n.text("permission.step.openSettings"))
                step(2, L10n.text("permission.step.enable"))
                step(3, L10n.text("permission.step.relaunch"))
            }
            .padding(.top, 16)

            HStack {
                Button(L10n.text("permission.later"), action: onLater)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.text("permission.relaunch"), action: onRelaunch)

                Button(L10n.text("permission.openSettings"), action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(ScreviaTheme.accent, in: Circle())

            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Permission onboarding") {
    PermissionOnboardingView(onOpenSettings: {}, onRelaunch: {}, onLater: {})
}
#endif
